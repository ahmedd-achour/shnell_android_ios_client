import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:shnell/model/calls.dart';

class CallService {
  static final CallService _instance = CallService._internal();
  factory CallService() => _instance;
  CallService._internal();

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;



  Future<bool> makeCall({required Call call}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    final idToken = await user.getIdToken();
    final receiverDoc = await _firestore.collection('users').doc(call.driverId).get();
    final fcmToken = receiverDoc.data()?['fcmToken'] as String?;

    if (fcmToken == null) return false;
final response = await http.post(
      Uri.parse('https://us-central1-shnell-393a6.cloudfunctions.net/initiateCall'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $idToken',
      },
      body: jsonEncode({
        'receiverFCMToken': fcmToken,
        'dealId': call.dealId,
      }),
    );
if(response.statusCode == 200){
    await _firestore.collection('calls').doc(call.dealId).set({
      'callerId': user.uid,
      'receiverId': call.driverId,
      'callStatus': 'dialing',
      'agoraChannel': call.agoraChannel,
      'timestamp': FieldValue.serverTimestamp(),
    });
}
  

   

    return response.statusCode == 200;
  }
}