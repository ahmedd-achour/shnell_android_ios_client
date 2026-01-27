const functions = require("firebase-functions");
const admin = require("firebase-admin");
const { RtcTokenBuilder, RtcRole } = require("agora-access-token");

admin.initializeApp();
const AGORA_APP_ID = "392d2910e2f34b4a885212cd49edcffa";
const AGORA_APP_CERTIFICATE = "cbb19d0678874ea8b851b41d97f3fde6";

// Helper: Convert Firebase UID (string) to a unique 32-bit integer for Agora
function stringToUid(str) {
  if (!str) return 1;
  let hash = 0;
  for (let i = 0; i < str.length; i++) {
    const char = str.charCodeAt(i);
    hash = (hash << 5) - hash + char; // hash * 31 + char
    hash = hash & hash; // Convert to 32-bit integer
  }
  const uid = Math.abs(hash);
  return uid === 0 ? 1 : uid; // Agora UID 0 is reserved
}

exports.initiateCall = functions.https.onRequest(async (req, res) => {
  // ===== CORS =====
  res.set("Access-Control-Allow-Origin", "*");
  res.set("Access-Control-Allow-Methods", "POST");
  res.set("Access-Control-Allow-Headers", "Content-Type, Authorization");
  if (req.method === "OPTIONS") return res.status(204).send("");

  try {
    const {
      receiverFCMToken,
      dealId,
      callerName,
      callerFCMToken,
      callerFirebaseUid,   // MUST be sent from authenticated client
      receiverFirebaseUid, // You need to know this (from Firestore deal doc)
      idToken,             // Firebase ID token for verification
    } = req.body;

    if (!receiverFCMToken || !dealId || !callerFirebaseUid || !receiverFirebaseUid || !idToken) {
      return res.status(400).json({ error: "Missing required fields" });
    }

    // ===== SECURITY: Verify the caller is who they say they are =====
    let decodedToken;
    try {
      decodedToken = await admin.auth().verifyIdToken(idToken);
      if (decodedToken.uid !== callerFirebaseUid) {
        return res.status(401).json({ error: "Unauthorized: UID mismatch" });
      }
    } catch (error) {
      return res.status(401).json({ error: "Invalid ID token" });
    }

    // ===== Generate dynamic UIDs =====
    const callerUid = stringToUid(callerFirebaseUid);
    let receiverUid = stringToUid(receiverFirebaseUid);

    // Rare collision fix
    if (callerUid === receiverUid) {
      receiverUid = (receiverUid + 1) || 2;
    }

    const channel = dealId;
    const expireTime = 3600; // 1 hour
    const privilegeExpireTime = Math.floor(Date.now() / 1000) + expireTime;

    // ===== Generate Agora tokens =====
    const callerToken = RtcTokenBuilder.buildTokenWithUid(
      AGORA_APP_ID,
      AGORA_APP_CERTIFICATE,
      channel,
      callerUid,
      RtcRole.PUBLISHER,
      privilegeExpireTime
    );

    const receiverToken = RtcTokenBuilder.buildTokenWithUid(
      AGORA_APP_ID,
      AGORA_APP_CERTIFICATE,
      channel,
      receiverUid,
      RtcRole.PUBLISHER,
      privilegeExpireTime
    );

    // ===== Update Firestore call document =====
    const callDoc = {
      dealId,
      callStatus: "ringing",
      callerName: callerName || "Shnell",
      agoraChannel: channel,
      callerUid,
      receiverUid,
      callerFirebaseUid,
      receiverFirebaseUid,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      callerToken,
      receiverToken,
      callerFCMToken,
      receiverFCMToken
    };

    await admin.firestore().collection("calls").doc(dealId).set(callDoc);

    // ===== FCM payload for receiver =====
    const fcmPayload = {
      data: {
        type: "call",
        dealId,
        callerName: callerName || "Shnell Driver",
        agoraChannel: channel,
        agoraToken: receiverToken,
        callerUid: callerUid.toString(),
        receiverUid: receiverUid.toString(),
        callerFirebaseUid,
        callerFCMToken,
        receiverFCMToken,
        receiverToken,
        

      },
      notification: {
        title: "Appel entrant",
        body: `${callerName || "Quelqu'un"} vous appelle`,
      },
      android: { priority: "high" },
      apns: {
        headers: { "apns-priority": "10" },
        payload: { aps: { "content-available": 1 } },
      },
    };

    await admin.messaging().send({ ...fcmPayload, token: receiverFCMToken });
    // ===== Return to caller client =====
    return res.json({
      success: true,
      agoraToken: callerToken,
      agoraChannel: channel,
      callerUid,
      receiverUid,
      callerFirebaseUid,
      receiverFirebaseUid,
    });
  } catch (error) {
    console.error("initiateCall error:", error);
    return res.status(500).json({ error: error.message });
  }
});
// Ensure admin is initialized (usually at the top of your file)
exports.terminateCall = functions.https.onRequest(async (req, res) => {
  res.set('Access-Control-Allow-Origin', '*');
  if (req.method === 'OPTIONS') return res.status(204).send('');

  try {
    const { dealId, status = "ended", callerFCMToken, receiverFCMToken } = req.body;

    if (!dealId) {
      return res.status(400).json({ error: "dealId is required" });
    }
    // Send silent FCM to kill CallKit on BOTH devices
    const payload = {
      data: {
        type: "call_terminated",
        dealId: dealId,
        status: status,
      },
      android: { priority: "high" },
      apns: { headers: { "apns-priority": "10" } },
    };

    const tokens = [];
    if (callerFCMToken) tokens.push(callerFCMToken);
    if (receiverFCMToken) tokens.push(receiverFCMToken);

    if (tokens.length > 0) {
      await admin.messaging().sendEach(
        tokens.map(token => ({ ...payload, token }))
      );
    }

    res.json({ success: true });
  } catch (error) {
    console.error("terminateCall error:", error);
    res.status(500).json({ error: error.message });
  }
});