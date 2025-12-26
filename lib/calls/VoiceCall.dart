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
  late final RtcEngine _engine;
  int? _remoteUid;
  bool _isMicMuted = false;
  bool _isSpeakerOn = true;
  bool _isConnected = false;
  bool _isEnding = false; // Prevents double execution

  final String _appId = "392d2910e2f34b4a885212cd49edcffa";
  final FlutterRingtonePlayer _ringtonePlayer = FlutterRingtonePlayer();

  Timer? _durationTimer;
  int _callDurationSeconds = 0;

  StreamSubscription<DocumentSnapshot>? _callStatusSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCall();
  }

  Future<void> _initializeCall() async {
    if (widget.isCaller) {
      _ringtonePlayer.play(
        android: AndroidSounds.ringtone,
        ios: IosSounds.glass,
        looping: true,
        volume: 1.0,
      );
    }

    await _requestPermissions();
    await _initializeAgora();
    _listenToCallStatus();
  }

  Future<void> _requestPermissions() async {
    await [Permission.microphone].request();
  }

  void _listenToCallStatus() {
    _callStatusSubscription = FirebaseFirestore.instance
        .collection('calls')
        .doc(widget.call.dealId)
        .snapshots()
        .listen((snapshot) async {
      if (!mounted || _isEnding) return;

      if (!snapshot.exists) {
        await _endCall(reason: 'canceled');
        return;
      }

      final status = snapshot.data()?['callStatus'] as String?;

      if (status == 'connected' && !_isConnected) {
        setState(() => _isConnected = true);
        _ringtonePlayer.stop();
        _startDurationTimer();
      }

      if (['declined', 'canceled', 'missed', 'ended'].contains(status)) {
        await _endCall(reason: status ?? 'ended');
      }
    });
  }

  void _startDurationTimer() {
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _callDurationSeconds++);
    });
  }

  Future<void> _initializeAgora() async {
    _engine = createAgoraRtcEngine();
    await _engine.initialize(RtcEngineContext(appId: _appId));

    _engine.registerEventHandler(
      RtcEngineEventHandler(
        onJoinChannelSuccess: (_, __) {
          if (!mounted) return;
          _engine.setEnableSpeakerphone(true);
          setState(() => _isSpeakerOn = true);
        },
        onUserJoined: (_, remoteUid, __) {
          if (mounted) setState(() => _remoteUid = remoteUid);
        },
        onUserOffline: (_, remoteUid, reason) async {
          await _endCall(reason: 'ended');
        },
        onConnectionStateChanged: (_, state, reason) {
          if (state == ConnectionStateType.connectionStateFailed ||
              state == ConnectionStateType.connectionStateDisconnected) {
            if (_remoteUid == null && widget.isCaller) {
              _endCall(reason: 'timeout');
            }
          }
        },
      ),
    );

    await _engine.enableAudio();
    await _engine.setClientRole(role: ClientRoleType.clientRoleBroadcaster);

    final token = widget.isCaller
        ? (widget.call.callerToken ?? widget.call.agoraToken)
        : (widget.call.receiverToken ?? widget.call.agoraToken);

    try {
      await _engine.joinChannel(
        token: token,
        channelId: widget.call.agoraChannel,
        uid: 0,
        options: const ChannelMediaOptions(
          publishMicrophoneTrack: true,
          autoSubscribeAudio: true,
        ),
      );
    } catch (e) {
      debugPrint("Agora join failed: $e");
      if (mounted) await _endCall(reason: 'failed');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && !_isEnding) {
      _endCall(reason: 'backgrounded');
    }
  }

  Future<void> _endCall({required String reason}) async {
    if (!mounted || _isEnding) return;
    _isEnding = true;

    if (mounted) setState(() {});

    // Stop everything immediately
    _ringtonePlayer.stop();
    _durationTimer?.cancel();
    _callStatusSubscription?.cancel();

    // Notify backend
    unawaited(_notifyTermination(reason));

    // Leave Agora
    try {
      await _engine.leaveChannel();
      await _engine.release();
    } catch (_) {}

    // End CallKit
    try {
      await FlutterCallkitIncoming.endAllCalls();
    } catch (_) {}

    if (!mounted) return;

    // Navigate back safely
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const MainUsersScreen()),
      (route) => false,
    );
  }

  Future<void> _notifyTermination(String reason) async {
    String? receiverFcmToken;
    try {
      final receiverId = widget.isCaller ? widget.call.receiverId : widget.call.driverId;
      if (receiverId.isNotEmpty) {
        final doc = await FirebaseFirestore.instance.collection('users').doc(receiverId).get();
        receiverFcmToken = doc.data()?['fcmToken'];
      }
    } catch (_) {}

    try {
      await http.post(
        Uri.parse('https://us-central1-shnell-393a6.cloudfunctions.net/terminateCall'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'dealId': widget.call.dealId,
          'status': reason,
          if (receiverFcmToken != null) 'receiverFCMToken': receiverFcmToken,
        }),
      );
    } catch (e) {
      debugPrint("terminateCall failed (non-critical): $e");
    }
  }

  void _toggleMute() {
    if (_isEnding) return;
    setState(() => _isMicMuted = !_isMicMuted);
    _engine.muteLocalAudioStream(_isMicMuted);
  }

  void _toggleSpeaker() {
    if (_isEnding) return;
    setState(() => _isSpeakerOn = !_isSpeakerOn);
    _engine.setEnableSpeakerphone(_isSpeakerOn);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _callStatusSubscription?.cancel();
    _durationTimer?.cancel();
    _ringtonePlayer.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (!didPop) _endCall(reason: 'ended');
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF1C1C1E),
        body: SafeArea(
          child: Column(
            children: [
              const Spacer(flex: 2),

              // Avatar
              Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: Colors.grey[800],
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.5),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: const Icon(Icons.person, size: 90, color: Colors.white),
              ),

              const SizedBox(height: 32),

              // Name
              Text(
                widget.isCaller ? "Appel en cours…" : "Client Shnell",
                style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w600),
              ),

              const SizedBox(height: 12),

              // Status & Duration
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
                child: _isConnected
                    ? Column(
                        key: const ValueKey('connected'),
                        children: [
                          const Text(
                            "Connecté",
                            style: TextStyle(color: Colors.greenAccent, fontSize: 28, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _formatDuration(_callDurationSeconds),
                            style: const TextStyle(color: Colors.white70, fontSize: 20),
                          ),
                        ],
                      )
                    : Text(
                        widget.isCaller ? "Sonnerie en cours…" : "Connexion…",
                        key: const ValueKey('ringing'),
                        style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 18),
                      ),
              ),

              const Spacer(flex: 3),

              // Controls
              Padding(
                padding: const EdgeInsets.only(bottom: 80),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _controlButton(
                      icon: _isMicMuted ? Icons.mic_off : Icons.mic,
                      active: _isMicMuted,
                      onTap: _toggleMute,
                      enabled: !_isEnding,
                    ),

                    // End Call Button
                    GestureDetector(
                      onTap: _isEnding ? null : () => _endCall(reason: 'ended'),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.all(28),
                        decoration: BoxDecoration(
                          color: _isEnding ? Colors.grey[600] : Colors.redAccent,
                          shape: BoxShape.circle,
                          boxShadow: _isEnding
                              ? []
                              : [
                                  BoxShadow(
                                    color: Colors.redAccent.withOpacity(0.6),
                                    blurRadius: 20,
                                    spreadRadius: 2,
                                  ),
                                ],
                        ),
                        child: _isEnding
                            ? const SizedBox(
                                width: 40,
                                height: 40,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 3,
                                ),
                              )
                            : const Icon(Icons.call_end, color: Colors.white, size: 40),
                      ),
                    ),

                    _controlButton(
                      icon: _isSpeakerOn ? Icons.volume_up : Icons.volume_down,
                      active: _isSpeakerOn,
                      onTap: _toggleSpeaker,
                      enabled: !_isEnding,
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
    required bool enabled,
  }) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedOpacity(
        opacity: enabled ? 1.0 : 0.4,
        duration: const Duration(milliseconds: 200),
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
      ),
    );
  }
}