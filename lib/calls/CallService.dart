import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_callkit_incoming/entities/android_params.dart';
import 'package:flutter_callkit_incoming/entities/call_kit_params.dart';
import 'package:flutter_callkit_incoming/entities/ios_params.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:http/http.dart' as http;
import 'package:shnell/model/calls.dart';
import 'package:shnell/calls/VoiceCall.dart';
import 'package:flutter/material.dart';

class CallService {
  static final CallService _instance = CallService._internal();
  factory CallService() => _instance;
  CallService._internal();

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String? _currentActiveCallId;


  Future<void> init() async {
    await _requestPermissions();
    _setupFCMListener();
    _checkForActiveCallOnColdStart();
  }

  Future<void> _requestPermissions() async {
    await FlutterCallkitIncoming.requestNotificationPermission({
      "title": "Notifications",
      "rationaleMessagePermission": "Allow notifications for incoming calls",
    });
    if (await FlutterCallkitIncoming.canUseFullScreenIntent() == false) {
      await FlutterCallkitIncoming.requestFullIntentPermission();
    }
  }


  void _launchAppWithCallScreen(Call call) {
    runApp(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: VoiceCallScreen(call: call, isCaller: false),
      theme: ThemeData.dark(),
    ));
  }

  Future<void> _checkForActiveCallOnColdStart() async {
   // await Future.delayed(const Duration(milliseconds: 1000));

    final activeCalls = await FlutterCallkitIncoming.activeCalls();
    if (activeCalls.isEmpty) return;

    final callData = activeCalls.first;
    final extra = callData.extra as Map<String, dynamic>?;
    final dealId = extra?['dealId'] as String?;

    if (dealId == null) return;

    final doc = await _firestore.collection('calls').doc(dealId).get();
    if (!doc.exists) return;

    final data = doc.data()!;
    final call = Call(
      dealId: dealId,
      driverId: data['receiverId'] ?? '',
      receiverId: data['receiverId'] ?? '',
      callerId: data['callerId'] ?? '',
      callStatus: data['callStatus'] ?? 'connected',
      agoraChannel: data['agoraChannel'] ?? '',
      agoraToken: data['receiverToken'] ?? '',
      userId: '',
      callId: dealId,
    );

    _launchAppWithCallScreen(call);
  }

  void _setupFCMListener() {
    FirebaseMessaging.onMessage.listen((message) async {
      if (message.data['type'] == 'call') {
        await _showIncomingCall(message.data);
      }
    });

    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      if (message.data['type'] == 'call') {
        final dealId = message.data['dealId'];
        if (dealId != null) _checkForActiveCallOnColdStart();
      }
    });
  }

  Future<void> _showIncomingCall(Map<String, dynamic> data) async {
    final dealId = data['dealId'] as String?;
    if (dealId == null || _currentActiveCallId == dealId) return;

    _currentActiveCallId = dealId;

    final params = CallKitParams(
      id: data['uuid'] ?? dealId,
      nameCaller: data['callerName'] ?? 'Shnell Driver',
      appName: 'Shnell',
      handle: 'Appel entrant',
      type: 0,
      duration: 45000,
      extra: data,
      android: const AndroidParams(
        isCustomNotification: true,
        isShowFullLockedScreen: true,
        ringtonePath: 'system_ringtone_default',
      ),
      ios: const IOSParams(handleType: 'generic'),
    );

    await FlutterCallkitIncoming.showCallkitIncoming(params);
  }

  Future<void> updateCallStatus(String dealId, String status) async {
    await _firestore.collection('calls').doc(dealId).update({
      'callStatus': status,
      if (status != 'dialing' && status != 'connected') 'endedAt': FieldValue.serverTimestamp(),
    });
  }

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

  Future<Call?> getActiveIncomingCallIfAny() async {
   // await Future.delayed(const Duration(milliseconds: 800));

    final activeCalls = await FlutterCallkitIncoming.activeCalls();
    if (activeCalls.isEmpty) return null;

    final callData = activeCalls.first;
    final extra = callData.extra as Map<String, dynamic>?;
    final String? dealId = extra?['dealId'] as String?;

    if (dealId == null) return null;

    final doc = await FirebaseFirestore.instance.collection('calls').doc(dealId).get();
    

    final data = doc.data()!;
    final call = Call(
      dealId: dealId,
      driverId: data['receiverId'] ?? '',
      receiverId: data['receiverId'] ?? '',
      callerId: data['callerId'] ?? '',
      callStatus: data['callStatus'] ?? 'connected',
      agoraChannel: data['agoraChannel'] ?? '',
      agoraToken: data['receiverToken'] ?? '',
      userId: '',
      callId: dealId,
    );

    if (call.callStatus != 'connected') {
      await updateCallStatus(dealId, 'connected');
    }

    return call;
  }
}