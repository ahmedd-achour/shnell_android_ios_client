import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shnell/calls/AgoraService.dart';
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

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('calls')
          .where('callStatus', whereIn: ['ringing', 'connected'])
          .where(Filter.or(
            Filter('callerFirebaseUid', isEqualTo: user!.uid),
            Filter('receiverFirebaseUid', isEqualTo: user.uid),
          ))
          .orderBy('createdAt', descending: true)
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
            _snack("Call ended / no active call");
            _lastCallId = null;
            _lastStatus = null;
            unawaited(AgoraService().leave());
          }
          return widget.child;
        }

        final doc = docs.first;
        final data = doc.data() as Map<String, dynamic>;

        final status = (data['callStatus'] ?? '').toString();
        final isCaller = data['callerFirebaseUid'] == user.uid;

        // Transition logging
        if (_lastCallId != doc.id) {
          _snack("Call doc detected: ${doc.id}");
          _lastCallId = doc.id;
          _lastStatus = null; // reset status tracking for new call
        }

        if (_lastStatus != status) {
          _lastStatus = status;

          if (status == 'ringing') {
            _snack(isCaller ? "Calling..." : "Incoming call...");
          } else if (status == 'connected') {
            _snack("Call connected");
          } else {
            _snack("Call status: $status");
          }
        }

        return Material(
          color: Colors.black,
          child: status == 'connected'
              ? AgoraActiveCallScreen(data: data)
              : isCaller
                  ? OutgoingCallOverlay(data: data)
                  : IncomingCallOverlay(data: data),
        );
      },
    );
  }
}
