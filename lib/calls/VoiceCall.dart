import 'dart:async';
import 'dart:convert';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:shnell/callMediaControle.dart';
import 'package:shnell/dots.dart';
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
  /* if (widget.isCaller) {
      _ringtonePlayer.play(
        android: AndroidSounds.ringtone,
        ios: IosSounds.glass,
        looping: true,
        volume: 1.0,
      );
    }*/
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
CallMediaController.instance.attachEngine(_engine);

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
    await CallMediaController.instance.hardStopAudio();


    // Notify backend
      await _notifyTermination(reason);
      
    // Leave Agora
    try {
      await _engine.leaveChannel();
      await _engine.release();
    } catch (_) {}
    await CallMediaController.instance.hardStopAudio();

    await FirebaseFirestore.instance.collection('calls').doc(widget.call.agoraChannel).update({
      'callStatus': reason,
    });

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
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (!didPop) _endCall(reason: 'ended');
      },
      child: Scaffold(
        // Dynamic background that adjusts to theme brightness
        backgroundColor: theme.colorScheme.surface,
        body: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                theme.colorScheme.surface,
                theme.colorScheme.primaryContainer.withOpacity(0.2),
              ],
            ),
          ),
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Column(
                  children: [
                    const Spacer(flex: 2),

                    // Responsive Avatar
                    _buildAvatar(theme, constraints),

                    const SizedBox(height: 32),

                    // Caller Info
                    _buildCallInfo(theme),

                    const Spacer(flex: 3),

                    // Dynamic Controls
                    _buildControlBar(theme, size),

                    const SizedBox(height: 48),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar(ThemeData theme, BoxConstraints constraints) {
    return Container(
      padding: EdgeInsets.all(constraints.maxWidth * 0.08),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: theme.shadowColor.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Icon(
        Icons.person,
        size: constraints.maxWidth * 0.25,
        color: theme.colorScheme.onSecondaryContainer,
      ),
    );
  }

  Widget _buildCallInfo(ThemeData theme) {
    return Column(
      children: [
        Text(
          widget.isCaller ? "Appel en cours…" : "Client Shnell",
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          child: _isConnected
              ? Column(
                  key: const ValueKey('connected'),
                  children: [
                    Text(
                      _formatDuration(_callDurationSeconds),
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                        fontFeatures: [const FontFeature.tabularFigures()],
                      ),
                    ),
                    Text(
                      "Connecté",
                      style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.w500),
                    ),
                  ],
                )
              : Text(
                  widget.isCaller ? "Sonnerie en cours…" : "Connexion…",
                  key: const ValueKey('ringing'),
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildControlBar(ThemeData theme, Size size) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _controlButton(
            icon: _isMicMuted ? Icons.mic_off : Icons.mic,
            active: _isMicMuted,
            onTap: () {
              setState(() => _isMicMuted = !_isMicMuted);
              _engine.muteLocalAudioStream(_isMicMuted);
            },
            theme: theme,
          ),
          
          // End Call
          _endCallButton(theme),

          _controlButton(
            icon: _isSpeakerOn ? Icons.volume_up : Icons.volume_down,
            active: _isSpeakerOn,
            onTap: () {
              setState(() => _isSpeakerOn = !_isSpeakerOn);
              _engine.setEnableSpeakerphone(_isSpeakerOn);
            },
            theme: theme,
          ),
        ],
      ),
    );
  }

  Widget _endCallButton(ThemeData theme) {
    return GestureDetector(
      onTap: _isEnding ? null : () => _endCall(reason: 'ended'),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: theme.colorScheme.error,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: theme.colorScheme.error.withOpacity(0.3),
              blurRadius: 15,
              spreadRadius: 2,
            ),
          ],
        ),
        child: _isEnding
            ? const SizedBox(width: 32, height: 32, child: RotatingDotsIndicator())
            : const Icon(Icons.call_end, color: Colors.white, size: 36),
      ),
    );
  }

  Widget _controlButton({
    required IconData icon,
    required bool active,
    required VoidCallback onTap,
    required ThemeData theme,
  }) {
    return InkWell(
      onTap: _isEnding ? null : onTap,
      borderRadius: BorderRadius.circular(50),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: active ? theme.colorScheme.primary : theme.colorScheme.onSurface.withOpacity(0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          color: active ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface,
          size: 28,
        ),
      ),
    );
  }

  String _formatDuration(int seconds) {
    final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
    final secs = (seconds % 60).toString().padLeft(2, '0');
    return "$minutes:$secs";
  }


}
