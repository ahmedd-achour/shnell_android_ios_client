import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shnell/calls/AgoraService.dart';

class OutgoingCallOverlay extends StatefulWidget {
  final Map<String, dynamic> data;
  const OutgoingCallOverlay({super.key, required this.data});

  @override
  State<OutgoingCallOverlay> createState() => _OutgoingCallOverlayState();
}
  final AgoraService _agoraService = AgoraService();

class _OutgoingCallOverlayState extends State<OutgoingCallOverlay> {
  @override
  Widget build(BuildContext context) {
    final String callerName = widget.data['sessionId'] ?? "User";

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Blurred Background Image
          Image.network(
            "https://your-placeholder-avatar.com/user.jpg", // Replace with real avatar URL
            fit: BoxFit.cover,
          ),
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
            child: Container(color: Colors.black.withOpacity(0.5)),
          ),

          // 2. Responsive Content Layout
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                double verticalPadding = constraints.maxHeight * 0.1;
                
                return Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Top Section: Name & Status
                    Padding(
                      padding: EdgeInsets.only(top: verticalPadding),
                      child: Column(
                        children: [
                          Text(
                            callerName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 32,
                              fontWeight: FontWeight.w300,
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            "Calling...",
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 16,
                              letterSpacing: 2,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Middle Section: Avatar
                    CircleAvatar(
                      radius: constraints.maxWidth * 0.2, // Proportional size
                      backgroundColor: Colors.white24,
                      child: CircleAvatar(
                        radius: constraints.maxWidth * 0.18,
                        backgroundImage: const NetworkImage("https://your-placeholder-avatar.com/user.jpg"),
                      ),
                    ),

                    // Bottom Section: Action Buttons
                    Padding(
                      padding: EdgeInsets.only(bottom: verticalPadding),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _callActionButton(
                            icon: Icons.call_end,
                            color: Colors.redAccent,
                            onPressed: ()async{
                              await _agoraService.leave();
                          
                             // final callerDoc = await FirebaseFirestore.instance.collection('users').doc(FirebaseAuth.instance.currentUser!.uid).get();
                               // final callerFcm = callerDoc['fcmToken'];
                                  final recieverDoc = await FirebaseFirestore.instance.collection('users').doc(widget.data['receiverFirebaseUid']).get();
                                final reciverFcm = recieverDoc['fcmToken'];
                                    unawaited(
                        http.post(
              Uri.parse("$cloudFunctionUrl/terminateCall"),
              headers: {"Content-Type": "application/json"},
              body: jsonEncode({
                "dealId":  widget.data['dealId'],
                "receiverFCMToken": reciverFcm,
               // "callerFCMToken" : callerFCMToken
              }),
            ));
            await FirebaseFirestore.instance.collection('calls').doc(widget.data['dealId']).delete();
            
                            })
                           
                        ],
                      ),
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

  Widget _callActionButton({required IconData icon, required Color color, required VoidCallback onPressed}) {
    return RawMaterialButton(
      onPressed: onPressed,
      shape: const CircleBorder(),
      elevation: 10.0,
      fillColor: color,
      padding: const EdgeInsets.all(20.0),
      child: Icon(icon, color: Colors.white, size: 35.0),
    );
  }
}    