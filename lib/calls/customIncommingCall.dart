import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:shnell/model/calls.dart';
class IncomingCallOverlay extends StatefulWidget {
  final Call call;
  final VoidCallback onDecline;
  final VoidCallback onAccept;

  const IncomingCallOverlay({
    super.key,
    required this.call,
    required this.onDecline,
    required this.onAccept,
  });

  @override
  State<IncomingCallOverlay> createState() => _IncomingCallOverlayState();
}

class _IncomingCallOverlayState extends State<IncomingCallOverlay> {
  String _callerName = 'Incoming call';

  @override
  void initState() {
    super.initState();
    _startRingtone();
    _loadCallerName();
  }

  /// 🔊 Play system default ringtone
  void _startRingtone() {
    FlutterRingtonePlayer().playRingtone(
      looping: true,
      volume: 1.0,
    );
  }

  /// 🛑 Stop ringtone safely
  void _stopRingtone() {
    FlutterRingtonePlayer().stop();
  }

  /// 👤 Resolve caller name instead of ID
  Future<void> _loadCallerName() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.call.callerId)
          .get();

      if (!mounted) return;

      if (doc.exists) {
        final data = doc.data();
        final name = data?['name'] ?? data?['fullName'];

        if (name != null && name.toString().isNotEmpty) {
          setState(() => _callerName = name);
        }
      }
    } catch (_) {
      // silent fallback (never break incoming call UI)
    }
  }

  @override
  void dispose() {
    _stopRingtone();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withOpacity(0.6),
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.phone_in_talk,
                size: 70,
                color: Colors.green,
              ),
              const SizedBox(height: 14),
              Text(
                _callerName,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              const Text(
                'Incoming call',
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 28),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                    ),
                    onPressed: () {
                      _stopRingtone();
                      widget.onDecline();
                    },
                    child: const Text('Decline'),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                    ),
                    onPressed: () {
                      _stopRingtone();
                      widget.onAccept();
                    },
                    child: const Text('Accept'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
