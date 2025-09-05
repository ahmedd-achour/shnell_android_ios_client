const functions = require('firebase-functions');
const admin = require('firebase-admin');
admin.initializeApp();

exports.awakenCall = functions.firestore
  .document('calls/{callId}')
  .onUpdate(async (change, context) => {
    const before = change.before.data();
    const after = change.after.data();

    if (before.status !== 'calling' && after.status === 'calling') {
      const token = after.receiverToken; // user's device FCM token

      await admin.messaging().send({
        token: token,
        data: {
          type: 'incoming_call',
          callId: context.params.callId,
          callerId: after.callerId,
        },
        android: { priority: 'high' },
        apns: { headers: { 'apns-priority': '10' } },
      });
    }
  });
