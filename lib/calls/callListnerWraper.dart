import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_callkit_incoming/entities/call_event.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:shnell/calls/VoiceCall.dart';
import 'package:shnell/model/calls.dart';

class CallListenerWrapper extends StatefulWidget {
  final Widget child;
  final GlobalKey<NavigatorState> navigatorKey;

  const CallListenerWrapper({
    super.key,
    required this.child,
    required this.navigatorKey,
  });

  @override
  State<CallListenerWrapper> createState() => _CallListenerWrapperState();
}

class _CallListenerWrapperState extends State<CallListenerWrapper> {
  @override
  void initState() {
    super.initState();
    _setupCallKitListener();
    _checkPendingCallOnLaunch();
  }

  void _setupCallKitListener() {
    FlutterCallkitIncoming.onEvent.listen((event) async {
      if (event == null) return;

      final Map<String, dynamic> body = Map<String, dynamic>.from(event.body as Map);
      final String? dealId = body['extra']?['dealId'] as String? ?? body['id'] as String?;

      if (dealId == null) return;

      switch (event.event) {
        case Event.actionCallAccept:
          debugPrint("CALL ACCEPTED → Opening VoiceCallScreen");
          
          await FirebaseFirestore.instance
              .collection('calls')
              .doc(dealId)
              .update({'callStatus': 'connected'});

          final doc = await FirebaseFirestore.instance.collection('calls').doc(dealId).get();
          if (!doc.exists) return;

          final data = doc.data()!;
          final call = Call(
            dealId: dealId,
            driverId: data['receiverId'] ?? '',
            receiverId: data['receiverId'] ?? '',
            callerId: data['callerId'] ?? '',
            callStatus: 'connected',
            agoraChannel: data['agoraChannel'] ?? '',
            agoraToken: data['receiverToken'] ?? '',
            userId: '',
            callId: dealId,
          );

          widget.navigatorKey.currentState?.pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => VoiceCallScreen(call: call, isCaller: false)),
            (route) => route.isFirst,
          );
          break;

case Event.actionCallCustom:

print("=======================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================");

  await http.post(
    Uri.parse('https://us-central1-shnell-393a6.cloudfunctions.net/terminateCall'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({
      'dealId': dealId,
      'status': 'declined',
      // You can optionally pass FCM tokens if you have them
    }),
  );
   await FirebaseFirestore.instance
              .collection('calls')
              .doc(dealId)
              .update({'callStatus': 'declined'});
          

  await FlutterCallkitIncoming.endAllCalls();
  break;
         

        case Event.actionCallTimeout:
          await FirebaseFirestore.instance
              .collection('calls')
              .doc(dealId)
              .update({'callStatus': 'missed'});
          await FlutterCallkitIncoming.endAllCalls(); // ← Clears stuck state
          break;
        default:
        print("=======================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================================");

          break;
      }
    });
  }

  Future<void> _checkPendingCallOnLaunch() async {
    await Future.delayed(const Duration(milliseconds: 1500));

    final calls = await FlutterCallkitIncoming.activeCalls();
    if (calls.isEmpty) return;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}