import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:http/http.dart' as http;
import 'package:shnell/calls/AgoraService.dart';

class IncomingCallOverlay extends StatefulWidget {
  final Map<String, dynamic> data;
  const IncomingCallOverlay({super.key, required this.data});

  @override
  State<IncomingCallOverlay> createState() => _IncomingCallOverlayState();
}

class _IncomingCallOverlayState extends State<IncomingCallOverlay> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override

  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(); // Pulsating effect for the ring
  }

  final AgoraService _agoraService = AgoraService();

  @override
  Widget build(BuildContext context) {
    final String callerName = "Guest";

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // 1. Blurred Background
          Container(
            decoration: const BoxDecoration(
              image: DecorationImage(
                image: NetworkImage("https://your-placeholder.com/bg.jpg"),
                fit: BoxFit.cover,
              ),
            ),
          ),
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(color: Colors.black.withOpacity(0.6)),
          ),

          // 2. Main Content
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Column(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Caller Info
                    Column(
                      children: [
                        Text(callerName, style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 10),
                        const Text("Incoming Audio Call", style: TextStyle(color: Colors.white70, fontSize: 18)),
                      ],
                    ),

                    // Pulsating Avatar
                    AnimatedBuilder(
                      animation: _controller,
                      builder: (context, child) {
                        return Container(
                          padding: EdgeInsets.all(20 * _controller.value),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withOpacity(0.1 * (1 - _controller.value)),
                          ),
                          child: CircleAvatar(
                            radius: constraints.maxWidth * 0.2,
                            backgroundImage: const NetworkImage("https://your-placeholder.com/avatar.jpg"),
                          ),
                        );
                      },
                    ),

                    // Action Buttons (Accept / Decline)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        // Decline Button -> Calls endCall
                        _actionButton(
                          icon: Icons.call_end,
                          color: Colors.redAccent,
                          label: "Decline",
                          onPressed: ()async {
                               try{
                             await FlutterCallkitIncoming.endAllCalls();

                             }catch(r){

                             }
                             await _agoraService.leave();
                             // final callerDoc = await FirebaseFirestore.instance.collection('users').doc(FirebaseAuth.instance.currentUser!.uid).get();
                               // final callerFcm = callerDoc['fcmToken'];
                                    unawaited(
                        http.post(
              Uri.parse("$cloudFunctionUrl/terminateCall"),
              headers: {"Content-Type": "application/json"},
              body: jsonEncode({
                "dealId":  widget.data['dealId'],
               // "receiverFCMToken": reciverFcm,
               "callerFCMToken" : widget.data['callerFirebaseUid']
              }),
            ));
            await FirebaseFirestore.instance.collection('calls').doc(widget.data['dealId']).delete();
                            }
                        ),
                        // Accept Button -> Calls acceptCall
                        _actionButton(
                          icon: Icons.call,
                          color: Colors.greenAccent,
                          label: "Accept",
                      onPressed: () async {
  try {
    // 1. Tell the OS to stop the ringing and lock in the background priority
    // (We do this first so the phone stops vibrating/making noise)
    await FlutterCallkitIncoming.setCallConnected(widget.data['dealId']);

    // 2. Initialize the hardware (Agora)
    // This is the "Heavy" part. If this fails, we catch it before updating Firestore.
    await _agoraService.init(
      channel: widget.data['dealId'], 
      token: widget.data['receiverToken'], 
      uid: widget.data['receiverUid'],
    );

    // 3. Hardware is ready! Now tell the cloud to start the session.
    await FirebaseFirestore.instance
        .collection('calls')
        .doc(widget.data['dealId'])
        .update({'callStatus': 'connected'});
        
  } catch (e) {
    debugPrint("Safety Error: $e");
    // If something critical failed, tell the system the call is over
    await FlutterCallkitIncoming.endAllCalls();
    // Show the user an error message
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Failed to connect call. Please try again."))
    );
  }
}
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionButton({required IconData icon, required Color color, required String label, required VoidCallback onPressed}) {
    return Column(
      children: [
        RawMaterialButton(
          onPressed: onPressed,
          shape: const CircleBorder(),
          fillColor: color,
          padding: const EdgeInsets.all(20),
          child: Icon(icon, color: Colors.white, size: 35),
        ),
        const SizedBox(height: 10),
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 14)),
      ],
    );
  }
}