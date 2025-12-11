import 'dart:async';
import 'dart:convert';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:shnell/mainUsers.dart' show MainUsersScreen;
import 'package:shnell/model/calls.dart';

class VoiceCallScreen extends StatefulWidget {
  final Call call;
  final bool isCaller;

  const VoiceCallScreen({
    super.key,
    required this.call,
    required this.isCaller,
  });

  @override
  State<VoiceCallScreen> createState() => _VoiceCallScreenState();
}

class _VoiceCallScreenState extends State<VoiceCallScreen> with WidgetsBindingObserver {
  late RtcEngine _engine;
  int? _remoteUid;
  bool _isMicMuted = false;
  bool _isSpeakerOn = true;
  bool _isCallEnded = false;
  bool _isConnected = false;

  final String _appId = "392d2910e2f34b4a885212cd49edcffa";
  final FlutterRingtonePlayer _ringtonePlayer = FlutterRingtonePlayer();

  Timer? _durationTimer;
  int _callDurationSeconds = 0;

  StreamSubscription<DocumentSnapshot>? _callStatusSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startRingingIfOutgoing();
    _initializeAgora();
    _listenToCallStatus();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && !_isCallEnded) {
      _endCall(reason: 'ended');
    }
  }

  void _startRingingIfOutgoing() {
    if (widget.isCaller) {
      _ringtonePlayer.play(
        android: AndroidSounds.ringtone,
        ios: IosSounds.glass,
        looping: true,
        volume: 1.0,
      );
    }
  }

  void _listenToCallStatus() {
    _callStatusSubscription = FirebaseFirestore.instance
        .collection('calls')
        .doc(widget.call.dealId)
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;
      if (!snapshot.exists) {
        _endCall(reason: 'canceled');
        return;
      }

      final data = snapshot.data()!;
      final status = data['callStatus'] as String?;

      if (status == 'connected') {
        setState(() => _isConnected = true);
        _ringtonePlayer.stop();
        _durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (mounted) setState(() => _callDurationSeconds++);
        });
      }

      // Improved: Handle decline/cancel/missed/ended from ANY side
      if (status == 'declined' || status == 'canceled' || status == 'missed' || status == 'ended') {
        _endCall(reason: status ?? 'ended');
      }
    });
  }

  Future<void> _initializeAgora() async {
    await [Permission.microphone].request();

    _engine = createAgoraRtcEngine();
    await _engine.initialize(
      RtcEngineContext(
        appId: _appId,
        channelProfile: ChannelProfileType.channelProfileCommunication,
      ),
    );

    _engine.registerEventHandler(
      RtcEngineEventHandler(
        onJoinChannelSuccess: (connection, elapsed) {
          if (!mounted) return;
          _engine.setEnableSpeakerphone(true);
          setState(() => _isSpeakerOn = true);
        },

        onUserJoined: (connection, remoteUid, elapsed) {
          if (!mounted) return;
          setState(() => _remoteUid = remoteUid);
        },

        onUserOffline: (connection, remoteUid, reason) async {
          _endCall(reason: 'ended');
        },

        onConnectionStateChanged: (connection, state, reason) {
          if (state == ConnectionStateType.connectionStateFailed ||
              state == ConnectionStateType.connectionStateDisconnected) {
            if (_remoteUid == null && widget.isCaller) {
              _endCall(reason: 'canceled');
            }
          }
        },
      ),
    );

    await _engine.enableAudio();
    await _engine.setClientRole(role: ClientRoleType.clientRoleBroadcaster);

    String tokenToUse = widget.isCaller
        ? (widget.call.callerToken ?? widget.call.agoraToken)
        : (widget.call.receiverToken ?? widget.call.agoraToken);

    try {
      await _engine.joinChannel(
        token: tokenToUse,
        channelId: widget.call.agoraChannel,
        uid: 0,
        options: const ChannelMediaOptions(
          publishMicrophoneTrack: true,
          autoSubscribeAudio: true,
        ),
      );
    } catch (e) {
      debugPrint("Join channel failed: $e");
      _endCall(reason: 'failed');
    }
  }

Future<void> _endCall({String reason = 'ended'}) async {
  if (_isCallEnded) return;
  _isCallEnded = true;
    

  _ringtonePlayer.stop();
  _durationTimer?.cancel();
  _callStatusSubscription?.cancel();
   final receiverDoc = await FirebaseFirestore.instance.collection('users').doc(widget.call.driverId).get();
    final fcmToken = receiverDoc.data()?['fcmToken'] as String?;
    await http.post(
    Uri.parse('https://us-central1-shnell-393a6.cloudfunctions.net/terminateCall'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({
      'dealId': widget.call.dealId,
      'status': 'ended',
      'receiverFCMToken': fcmToken,  // kills receiver's ringing CallKit
      // You can optionally pass FCM tokens if you have them
    }));

  try {
    await _engine.leaveChannel();
  } catch (_) {}
  _engine.release();


  // Always clean CallKit state on exit
  await FlutterCallkitIncoming.endAllCalls();

  if (!mounted) return;

  if (Navigator.canPop(context)) {
    Navigator.pop(context);
  } else {
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const MainUsersScreen()));
  }
}


  void _toggleMute() {
    setState(() => _isMicMuted = !_isMicMuted);
    _engine.muteLocalAudioStream(_isMicMuted);
  }

  void _toggleSpeaker() {
    setState(() => _isSpeakerOn = !_isSpeakerOn);
    _engine.setEnableSpeakerphone(_isSpeakerOn);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _callStatusSubscription?.cancel();
    _endCall(reason: 'ended');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (!didPop) _endCall();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF1C1C1E),
        body: SafeArea(
          child: Column(
            children: [
              const Spacer(flex: 2),

              Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: Colors.grey[800],
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.person, size: 90, color: Colors.white),
              ),

              const SizedBox(height: 32),

              Text(
                widget.isCaller ? "Appel en cours…" : "Client Shnell",
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.w600,
                ),
              ),

              const SizedBox(height: 12),

              AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
                child: _isConnected
                    ? Column(
                        key: const ValueKey('connected'),
                        children: [
                          Text(
                            "Connecté",
                            style: const TextStyle(
                              color: Colors.greenAccent,
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _formatDuration(_callDurationSeconds),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 20,
                            ),
                          ),
                        ],
                      )
                    : Text(
                        widget.isCaller ? "Sonnerie en cours…" : "Connexion…",
                        key: const ValueKey('ringing'),
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 18,
                        ),
                      ),
              ),

              const Spacer(flex: 3),

              Padding(
                padding: const EdgeInsets.only(bottom: 80),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _controlButton(
                      icon: _isMicMuted ? Icons.mic_off : Icons.mic,
                      active: _isMicMuted,
                      onTap: _toggleMute,
                    ),

                    GestureDetector(
                      onTap: () => _endCall(reason: 'ended'),
                      child: Container(
                        padding: const EdgeInsets.all(28),
                        decoration: const BoxDecoration(
                          color: Colors.redAccent,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.redAccent,
                              blurRadius: 20,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        child: const Icon(Icons.call_end, color: Colors.white, size: 40),
                      ),
                    ),

                    _controlButton(
                      icon: _isSpeakerOn ? Icons.volume_up : Icons.volume_down,
                      active: _isSpeakerOn,
                      onTap: _toggleSpeaker,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDuration(int seconds) {
    final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
    final secs = (seconds % 60).toString().padLeft(2, '0');
    return "$minutes:$secs";
  }

  Widget _controlButton({
    required IconData icon,
    required bool active,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.white.withOpacity(0.15),
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          color: active ? Colors.black : Colors.white,
          size: 32,
        ),
      ),
    );
  }
}