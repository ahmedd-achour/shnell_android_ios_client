// functions/index.js
const functions = require("firebase-functions");
const admin = require("firebase-admin");
const { RtcTokenBuilder, RtcRole } = require("agora-access-token");

admin.initializeApp();

const AGORA_APP_ID = "392d2910e2f34b4a885212cd49edcffa";

exports.initiateCall = functions.https.onRequest(async (req, res) => {
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'POST');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }

  try {
    const { receiverFCMToken, dealId } = req.body;

    console.log("HTTPS REQUEST BODY:", req.body);

    if (!receiverFCMToken || !dealId) {
      return res.status(400).json({ error: "missing fields" });
    }

    const channel = dealId;
    const expire = Math.floor(Date.now() / 1000) + 3600;

    const callerToken = RtcTokenBuilder.buildTokenWithUid(AGORA_APP_ID, "", channel, 0, RtcRole.PUBLISHER, expire, expire);
    const receiverToken = RtcTokenBuilder.buildTokenWithUid(AGORA_APP_ID, "", channel, 1, RtcRole.PUBLISHER, expire, expire);
/*
    await admin.firestore().collection("calls").doc(dealId).set({
      callStatus: "dialing",
      agoraChannel: channel,
      callerToken,
      receiverToken,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
    });*/s

    await admin.messaging().send({
      token: receiverFCMToken,
      data: {
        type: "call",
        dealId,
        uuid: "0",
        callerName: "Shnell Driver",
        agoraChannel: channel,
        agoraToken: receiverToken,
      },
      notification: { title: "Appel entrant", body: "Shnell Driver vous appelle" },
      android: { priority: "high" },
      apns: { headers: { "apns-priority": "10" } },
    });

    res.json({ success: true, token: callerToken });
  } catch (error) {
    console.error("ERROR:", error);
    res.status(500).json({ error: error.message });
  }
});

// ADD THIS FUNCTION — ONE FUNCTION TO RULE THEM ALL
exports.terminateCall = functions.https.onRequest(async (req, res) => {
  res.set('Access-Control-Allow-Origin', '*');
  if (req.method === 'OPTIONS') return res.status(204).send('');

  try {
    const { dealId, status = "ended", callerFCMToken, receiverFCMToken } = req.body;

    if (!dealId) {
      return res.status(400).json({ error: "dealId is required" });
    }

    // Update Firestore
    /*
    await admin.firestore().collection("calls").doc(dealId).update({
      callStatus: status, // "ended", "declined", or "canceled"
      endedAt: admin.firestore.FieldValue.serverTimestamp(),
    });*/

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