/**import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shnell/calls/agoraActiveCall.dart';
import 'package:shnell/calls/incommingCall.dart';
import 'package:shnell/calls/outGoingCall.dart';

class CallOverlayWrapper extends StatefulWidget {
  final Widget child;
  const CallOverlayWrapper({super.key, required this.child});

  @override
  State<CallOverlayWrapper> createState() => _CallOverlayWrapperState();
}

class _CallOverlayWrapperState extends State<CallOverlayWrapper> {
  String? _lastCallId;
  String? _lastStatus; // to detect status transitions
  DateTime _lastSnackAt = DateTime.fromMillisecondsSinceEpoch(0);

  void _snack(String msg, {bool replace = true}) {
    if (!mounted) return;

    // throttle: avoid spam during rapid rebuilds
    final now = DateTime.now();
    if (now.difference(_lastSnackAt).inMilliseconds < 700) return;
    _lastSnackAt = now;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      if (messenger == null) return;

      if (replace) messenger.hideCurrentSnackBar();

      messenger.showSnackBar(
        SnackBar(
          content: Text(msg),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return widget.child;
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('calls')
          .where('callStatus', whereIn: ['ringing', 'connecting', 'connected'])
          .where(Filter.or(
            Filter('callerFirebaseUid', isEqualTo: user.uid),
            Filter('receiverFirebaseUid', isEqualTo: user.uid),
          ))
          .orderBy('createdAt', descending: true)
          .limit(1) // We only ever care about the most recent call
          .snapshots(),
      builder: (context, snapshot) {
        // show stream errors (useful for index errors)
        if (snapshot.hasError) {
          _snack("Call stream error: ${snapshot.error}", replace: true);
          return widget.child;
        }

        // Don’t do anything while loading first snapshot
        if (snapshot.connectionState == ConnectionState.waiting) {
          return widget.child;
        }

        final docs = snapshot.data?.docs ?? [];

        if (docs.isEmpty) {
          if (_lastCallId != null) {
           // _snack("Call ended / no active call");
            _lastCallId = null;
            _lastStatus = null;
            // No need to leave here, the active call screen's dispose() handles it.
            // unawaited(AgoraService().leave());
          }
          return widget.child;
        }

        final doc = docs.first;
        final data = doc.data() as Map<String, dynamic>;

        final status = (data['callStatus'] ?? '').toString();
        final isCaller = data['callerFirebaseUid'] == user.uid;

        // Transition logging
        if (_lastCallId != doc.id) {
         // _snack("Call doc detected: ${doc.id}");
          _lastCallId = doc.id;
          _lastStatus = null; // reset status tracking for new call
        }

        if (_lastStatus != status) {
          _lastStatus = status;

          if (status == 'ringing') {
           // _snack(isCaller ? "Calling..." : "Incoming call...");
          } else if (status == 'connecting') {
            //_snack(isCaller ? "Connecting..." : "Accepting call...");
          } else if (status == 'connected') {
           // _snack("Call connected");
          } else {
            //_snack("Call status: $status");
          }
        }

        // If a call is ringing or connecting, show the appropriate UI.
        // Once connected, it's always the active call screen.
        if (status == 'connected') {
          return Material(color: Colors.black, child: AgoraActiveCallScreen(data: data));
        }

        if (status == 'ringing' || status == 'connecting') {
          return Material(
            color: Colors.black,
            child: isCaller
                ? OutgoingCallOverlay(data: data)
                : IncomingCallOverlay(data: data),
          );
        }

        // If status is something else (e.g. ended, declined), show the main app
        return widget.child;
      },
    );
  }
}
 */

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shnell/calls/AgoraService.dart';
import 'package:shnell/calls/agoraActiveCall.dart';
import 'package:shnell/calls/incommingCall.dart';
import 'package:shnell/calls/outGoingCall.dart';

class CallOverlayWrapper extends StatelessWidget {
  final Widget child;

  const CallOverlayWrapper({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    // We place 'child' outside the StreamBuilders so the main app 
    // is never rebuilt/reloaded just because a call status changed.
        final user = FirebaseAuth.instance.currentUser;
            if (user == null) return  child;


    return      StreamBuilder<QuerySnapshot>(
          // Listen for calls involving ME
          stream: FirebaseFirestore.instance
              .collection('calls')
              .where('callStatus', whereIn: ['ringing', 'connected'])
              .where(Filter.or(
                Filter('callerFirebaseUid', isEqualTo: user.uid),
                Filter('receiverFirebaseUid', isEqualTo: user.uid),
              ))
              .snapshots(),
          builder: (context, snapshot) {
            // A. If no call, return NOTHING (let the user see the map)
            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              unawaited(AgoraService().leave()); // Ensure we leave any ongoing call
              return child;
            }

            // B. If call exists, render the Black Overlay
            final data = snapshot.data!.docs.first.data() as Map<String, dynamic>;
            final status = data['callStatus'];
            
            return Material(
              color: Colors.black, // Opaque background
              child: status == 'connected' 
                  ? AgoraActiveCallScreen(data: data) // The Video
                  : (data['callerFirebaseUid'] == user.uid)
                      ? OutgoingCallOverlay(data: data) // Calling...
                      : IncomingCallOverlay(data: data), // Ringing...
            );
          },
        );
}
  // Separated the query logic for clarity
}