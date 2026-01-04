// lib/calls/agoraActiveCall.dart


import 'dart:async';
import 'dart:convert';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:http/http.dart' as http;
import 'package:shnell/calls/AgoraService.dart';

class AgoraActiveCallScreen extends StatefulWidget {
  final Map<String, dynamic> data;

  const AgoraActiveCallScreen({Key? key, required this.data}) : super(key: key);

  @override
  State<AgoraActiveCallScreen> createState() => _AgoraActiveCallScreenState();
}

class _AgoraActiveCallScreenState extends State<AgoraActiveCallScreen> {
  final AgoraService _agoraService = AgoraService(); 
  
  RtcEngine? get _engine => _agoraService.engine; // Getter for cleaner code

  bool _isLocalVideoEnabled = false;    // Camera ON by default
  bool _isMuted = false;
  bool _isFrontCamera = true;
  late final String _channelName;
  late final String _token;
  late final int _uid;
  late final bool _isCaller;
  late final String _callId;
  late final String _callerFCMToken;
  late final String _receiverFCMToken;

  final String _currentUserUid = FirebaseAuth.instance.currentUser!.uid;

  @override
  void initState() {
    super.initState();
    _extractCallData();
  }

  void _extractCallData() {
    final data = widget.data;
    _callId = data['dealId'];

    _channelName = (data['dealId'] ?? _callId) as String;

    final callerId = data['callerFirebaseUid'] ?? data['callerFirebaseUid'] as String;
    _isCaller = callerId == _currentUserUid;

    if (_isCaller) {
      _token =  data['callerToken']?? data['agoraToken'] as String;
      _callerFCMToken = data['callerFCMToken'] ?? '';
      _uid = data['receiverUid']; // remote uid

      _receiverFCMToken = data['receiverFCMToken'] ?? '';
    } else {
      _token =  data['receiverToken'] ?? data['agoraToken'] ;
            _uid = data['callerUid'];

      _callerFCMToken = data['callerFCMToken'] ?? '';
      _receiverFCMToken = data['receiverFCMToken'] ?? '';
    }
  }


Future<void> _toggleCamera() async {
  final bool nextState = !_isLocalVideoEnabled;

  if (nextState) {
    // 1. Physically turn on the camera hardware
    await _engine!.startPreview(); 
    // 2. Tell the peer "I am sending video now"
    await _engine!.muteLocalVideoStream(false);
    // 3. Update channel options to publish the track
    await _engine!.updateChannelMediaOptions(
      const ChannelMediaOptions(publishCameraTrack: true),
    );
  } else {
    // 1. Tell the peer "I stopped video"
    await _engine!.muteLocalVideoStream(true);
    // 2. Turn off the camera hardware (Privacy & Battery)
    await _engine!.stopPreview();
    // 3. Update channel options
    await _engine!.updateChannelMediaOptions(
      const ChannelMediaOptions(publishCameraTrack: false),
    );
  }

  setState(() => _isLocalVideoEnabled = nextState);
}

  Future<void> _toggleMute() async {
    setState(() => _isMuted = !_isMuted);
    await _engine!.muteLocalAudioStream(_isMuted);
  }

  Future<void> _switchCamera() async {
    await _engine!.switchCamera();
    setState(() => _isFrontCamera = !_isFrontCamera);
  }
_endCall()async{
     await _agoraService.leave();
  if(_isCaller){
         await FlutterCallkitIncoming.endAllCalls();

    unawaited(
        http.post(
              Uri.parse("$cloudFunctionUrl/terminateCall"),
              headers: {"Content-Type": "application/json"},
              body: jsonEncode({
                "dealId": widget.data['dealId'],
                "receiverFCMToken":  _receiverFCMToken ,
                //"callerFCMToken" : callerFCMToken
              }),
            ));
  await FirebaseFirestore.instance.collection('calls').doc(widget.data["dealId"]).delete();

  }else{


         await FlutterCallkitIncoming.endAllCalls();

   unawaited(
        http.post(
              Uri.parse("$cloudFunctionUrl/terminateCall"),
              headers: {"Content-Type": "application/json"},
              body: jsonEncode({
                "dealId": widget.data['dealId'],
                //"receiverFCMToken":  widget.data['receiverFCMToken'] ,
                "callerFCMToken" :_callerFCMToken
              }),
            ));
  await FirebaseFirestore.instance.collection('calls').doc(widget.data["dealId"]).delete();

  }

}
  @override
  void dispose() {
    try{
    _engine?.leaveChannel();
    }catch(e){
      print("not joined , we only release");
    }
    _engine?.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
            Stack(
              children: [
                // Remote video (full screen)
                
                // Remote Video (Full Screen)
// Inside your build method
ValueListenableBuilder<bool>(
  valueListenable: _agoraService.isRemoteVideoActive,
  builder: (context, isRemoteActive, _) {
    return isRemoteActive 
      ? AgoraVideoView(
          controller: VideoViewController.remote(
            rtcEngine: _engine!,
            canvas: VideoCanvas(uid: _uid),
            connection: RtcConnection(channelId: _channelName),
          ),
        )
      : Container(
          color: Colors.black,
          child: Center(
            child: CircleAvatar(
              radius: 40,
              backgroundColor: Colors.white10,
              child: Icon(Icons.videocam_off, color: Colors.white30),
            ),
          ),
        );
  },
),               

                // Local preview (small top-right)
                if (_isLocalVideoEnabled)
                  Align(
                    alignment: Alignment.topRight,
                    child: Container(
                      width: 120,
                      height: 170,
                      margin: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white38, width: 2),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: AgoraVideoView(
                          controller: VideoViewController(
                            rtcEngine: _engine!,
                            canvas:  VideoCanvas(uid: 0),
                          ),
                        ),
                      ),
                    ),
                  ),

                // Top info bar
                Positioned(
                  top: MediaQuery.of(context).padding.top + 20,
                  left: 0,
                  right: 0,
                  child: Column(
                    children: [
                      const SizedBox(height: 8),
                      Text(
                        _uid!=null  ? 'Connected' : 'Ringing...',
                        style: const TextStyle(color: Colors.white70, fontSize: 16),
                      ),
                    ],
                  ),
                ),

                // Bottom controls
                Positioned(
                  bottom: 60,
                  left: 0,
                  right: 0,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _controlButton(_isMuted ? Icons.mic_off : Icons.mic, Colors.grey[800]!, _toggleMute),
                      _controlButton(
                        _isLocalVideoEnabled ? Icons.videocam : Icons.videocam_off,
                        _isLocalVideoEnabled ? Colors.green : Colors.grey[800]!,
                        _toggleCamera,
                      ),
                      _controlButton(Icons.call_end, Colors.red, _endCall),
                      _controlButton(
                        _isFrontCamera ? Icons.camera_front : Icons.camera_rear,
                        _isLocalVideoEnabled ? Colors.grey[800]! : Colors.grey[600]!,
                        _isLocalVideoEnabled ? _switchCamera : null,
                      ),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
  Widget _controlButton(IconData icon, Color background, VoidCallback? onTap) {
    return FloatingActionButton(
      backgroundColor: background,
      onPressed: onTap,
      heroTag: null,
      child: Icon(icon, color: Colors.white, size: 28),
    );
  }
}