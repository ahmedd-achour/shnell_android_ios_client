import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shnell/FcmManagement.dart';
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
  
  @override
  void initState() {
    super.initState();
    // Only init FCM/Notifications, NO Agora code here
    if (FirebaseAuth.instance.currentUser != null) {
      FCMTokenManager().initialize();
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return widget.child;

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('calls')
          .where(Filter.or(
            Filter('callerFirebaseUid', isEqualTo: currentUser.uid),
            Filter('receiverFirebaseUid', isEqualTo: currentUser.uid),
          ))
          .snapshots(),
      builder: (context, snapshot) {
        // 1. If no active call docs, just show the app
   if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    // This is the "Safety Net"
    // If the FCM already killed the engine, this does nothing.
    // If the FCM is slow, this kills the Mic/Cam the MOMENT the doc is deleted.
    await AgoraService().leave(); 
  });
  return widget.child;
}

        // 2. Get the first active call
        // Note: You might want to filter for status != 'ended' if you don't delete docs immediately
        final callDoc = snapshot.data!.docs.first; 
        final callData = callDoc.data() as Map<String, dynamic>;
        final String status = callData['callStatus'] ?? 'ended';
        final String callerId = callData['callerFirebaseUid'];

        // 3. If the call is ended, show nothing (return child only)
        if (status == 'ended') {
           // Optional: You might trigger a cleanup function here to delete the doc
           return widget.child;
        }

        // 4. Overlay the Call UI on top of your app
        return Stack(
          children: [
            widget.child, // The App (Map, Dashboard, etc)
            Positioned.fill(
              child: Container(
                color: Colors.black, // Background for the call
                child: _buildCallUI(status, callerId, currentUser.uid, callData),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCallUI(String status, String callerId, String myId, Map<String, dynamic> data) {
    switch (status) {
      case 'ringing':
        // If I am the caller -> Show "Calling..."
        // If I am the receiver -> Show "Incoming Call..."
        return myId == callerId
            ? OutgoingCallOverlay(data: data)
            : IncomingCallOverlay(data: data);

      case 'connected':
        // Both users see this when status flips to 'connected'
       return AgoraActiveCallScreen(
  key: ValueKey(data['dealId']), // Force a fresh initState every call
  data: data,
);

      default:
        // Render nothing if status is unknown/ended
        return const SizedBox.shrink(); 
    }
  }
}