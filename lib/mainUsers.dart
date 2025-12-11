
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_callkit_incoming/entities/call_event.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:shnell/Account.dart';
import 'package:shnell/History.dart';
import 'package:shnell/drawer.dart';
import 'package:shnell/tabsControlerMultipleAsignements.dart';
import 'package:shnell/calls/VoiceCall.dart';
import 'package:shnell/model/calls.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class MainUsersScreen extends StatefulWidget {
  final int? initialIndex;

  const MainUsersScreen({super.key, this.initialIndex});

  @override
  State<MainUsersScreen> createState() => _MainUsersScreenState();
}

class _MainUsersScreenState extends State<MainUsersScreen> {
  late int _currentIndex;
  final List<Widget> _tabs = [
    const MultipleTrackingScreen(),
    const UserActivityDashboard(),
    const SettingsScreen(),
  ];

  // This will be set when an incoming call is active
  Call? _activeIncomingCall;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex ?? 0;

    // Listen to CallKit events globally
    _setupCallKitListener();

    // Check if there's already an active call when screen is opened
    _checkForActiveCall();
  }

  void _setupCallKitListener() {
    FlutterCallkitIncoming.onEvent.listen((event) async {
      if (event == null) return;

      final body = Map<String, dynamic>.from(event.body as Map);
      final extra = body['extra'] is Map ? Map<String, dynamic>.from(body['extra']) : null;
      final String? dealId = extra?['dealId'] as String? ?? body['id'] as String?;

      if (dealId == null) return;

      switch (event.event) {
        case Event.actionCallAccept:
          // Update Firebase immediately
          await FirebaseFirestore.instance.collection('calls').doc(dealId).update({
            'callStatus': 'connected',
          });

          // Load call data
          final doc = await FirebaseFirestore.instance.collection('calls').doc(dealId).get();
          if (!doc.exists) return;

          final data = doc.data()!;
          final call = Call(
            dealId: dealId,
            driverId: data['receiverId'] ?? '',
            receiverId: data['receiverId'] ?? '',
            callerId: data['callerId'] ?? '',
            callStatus: 'connected',
            agoraChannel: data['agoraChannel'] ?? '',
            agoraToken: data['receiverToken'] ?? '',
            userId: '',
            callId: dealId,
          );

          // Show your custom call screen
          setState(() {
            _activeIncomingCall = call;
          });

          // Optional: End CallKit call to avoid duplicate ringing
          await FlutterCallkitIncoming.endCall(dealId);
          break;

            case Event.actionCallDecline:
   await FirebaseFirestore.instance
              .collection('calls')
              .doc(dealId)
              .update({'callStatus': 'declined'});

  await FlutterCallkitIncoming.endAllCalls();
  break;
         

        case Event.actionCallTimeout:
        case Event.actionCallEnded:
            await FlutterCallkitIncoming.endAllCalls();



          break;
        case Event.actionDidUpdateDevicePushTokenVoip:
          // TODO: Handle this case.
          throw UnimplementedError();
        case Event.actionCallIncoming:
          // TODO: Handle this case.
          throw UnimplementedError();
        case Event.actionCallStart:
          // TODO: Handle this case.
          throw UnimplementedError();
        case Event.actionCallConnected:
          // TODO: Handle this case.
          throw UnimplementedError();
        case Event.actionCallCallback:
          // TODO: Handle this case.
          throw UnimplementedError();
        case Event.actionCallToggleHold:
          // TODO: Handle this case.
          throw UnimplementedError();
        case Event.actionCallToggleMute:
          // TODO: Handle this case.
          throw UnimplementedError();
        case Event.actionCallToggleDmtf:
          // TODO: Handle this case.
          throw UnimplementedError();
        case Event.actionCallToggleGroup:
          // TODO: Handle this case.
          throw UnimplementedError();
        case Event.actionCallToggleAudioSession:
          // TODO: Handle this case.
          throw UnimplementedError();
        case Event.actionCallCustom:
          // TODO: Handle this case.
          throw UnimplementedError();
          // TODO: Handle this case.
      }
    });
  }

  Future<void> _checkForActiveCall() async {
    await Future.delayed(const Duration(milliseconds: 800));

    final activeCalls = await FlutterCallkitIncoming.activeCalls();
    if (activeCalls.isEmpty) return;

    final callData = activeCalls.first;
    final extra = callData.extra as Map<String, dynamic>?;
    final String? dealId = extra?['dealId'] as String?;

    if (dealId == null) return;

    final doc = await FirebaseFirestore.instance.collection('calls').doc(dealId).get();
    if (!doc.exists) return;

    final data = doc.data()!;
    final call = Call(
      dealId: dealId,
      driverId: data['receiverId'] ?? '',
      receiverId: data['receiverId'] ?? '',
      callerId: data['callerId'] ?? '',
      callStatus: data['callStatus'] ?? 'connected',
      agoraChannel: data['agoraChannel'] ?? '',
      agoraToken: data['receiverToken'] ?? '',
      userId: '',
      callId: dealId,
    );

    // If call is connected → show screen
    if (call.callStatus == 'connected') {
      setState(() {
        _activeIncomingCall = call;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    // If there's an active incoming call → show ONLY the call screen
    if (_activeIncomingCall != null) {
      return VoiceCallScreen(
        call: _activeIncomingCall!,
        isCaller: false,
      );
    }

    // Normal app UI
    return Scaffold(
      drawer: ShnellDrawer(initialIndex: _currentIndex),
      body: IndexedStack(
        index: _currentIndex,
        children: _tabs,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: [
          BottomNavigationBarItem(
            icon: const Icon(Icons.home_outlined),
            label: l10n.home,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.history_edu_outlined, size: 26),
            label: l10n.history,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.person_outlined),
            label: l10n.account,
          ),
        ],
        selectedItemColor: const Color.fromARGB(255, 187, 152, 48),
        unselectedItemColor: const Color.fromARGB(255, 197, 197, 195),
        type: BottomNavigationBarType.fixed,
      ),
    );
  }
}