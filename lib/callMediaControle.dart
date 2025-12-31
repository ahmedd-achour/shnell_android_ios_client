import 'package:agora_rtc_engine/agora_rtc_engine.dart';

class CallMediaController {
  CallMediaController._internal();
  static final CallMediaController instance = CallMediaController._internal();

  RtcEngine? _engine;
  bool _audioStopped = false;

  void attachEngine(RtcEngine engine) {
    _engine = engine;
    _audioStopped = false;
  }

  Future<void> hardStopAudio() async {
    if (_audioStopped) return;
    _audioStopped = true;

    final engine = _engine;
    if (engine == null) return;

    try {
      // 1️⃣ Stop capturing immediately
      await engine.muteLocalAudioStream(true);

      // 2️⃣ Release mic hardware
      await engine.enableLocalAudio(false);

      // 3️⃣ Stop publishing track
      await engine.updateChannelMediaOptions(
        const ChannelMediaOptions(
          publishMicrophoneTrack: false,
          autoSubscribeAudio: false,
        ),
      );
    } catch (_) {}
  }

  Future<void> release() async {
    final engine = _engine;
    _engine = null;

    try {
      await engine?.leaveChannel();
      await engine?.release();
    } catch (_) {}
  }
}
