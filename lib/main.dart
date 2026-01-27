import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_callkit_incoming/entities/android_params.dart';
import 'package:flutter_callkit_incoming/entities/call_event.dart';
import 'package:flutter_callkit_incoming/entities/call_kit_params.dart';
import 'package:flutter_callkit_incoming/entities/ios_params.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;

import 'package:shnell/calls/AgoraService.dart';
import 'package:shnell/calls/agoraActiveCall.dart';
import 'package:shnell/calls/callUIController.dart';
import 'package:shnell/calls/incommingCall.dart';
import 'package:shnell/calls/outGoingCall.dart';
import 'package:shnell/customMapStyle.dart';           // ← your map styles
import 'package:shnell/dots.dart';                    // ← RotatingDotsIndicator
import 'package:shnell/firebase_options.dart';
import 'package:shnell/mainUsers.dart';
import 'package:shnell/updateApp.dart';
import 'package:shnell/verrifyInternet.dart';         // ← VerifyInternetScreen
import 'package:shnell/welcome.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final ValueNotifier<String> mapStyleNotifier = ValueNotifier<String>('');
final ValueNotifier<int> persistentTabController = ValueNotifier<int>(0);
// You can adjust this value according to your current version
const String _currentAppVersion = "21.21.22";
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  final data = message.data;

  if (data['type'] == 'call') {
    final params = CallKitParams(
      id: data['dealId'],
      nameCaller: data['callerName'] ?? 'Shnell',
      appName: 'Shnell',
      handle: 'Incoming Call',
      type: 0,
      extra: Map<String, dynamic>.from(data),
      android: const AndroidParams(
        isCustomNotification: true,
        ringtonePath: 'system_ringtone_default',
        isShowFullLockedScreen: true,
      ),
      ios: const IOSParams(
        supportsVideo: false,
        maximumCallsPerCallGroup: 1,
        iconName: 'CallKitIcon',
      ),
    );
    await FlutterCallkitIncoming.showCallkitIncoming(params);
  }

  if (data['type'] == 'call_terminated') {
    await FlutterCallkitIncoming.endAllCalls();
    await AgoraService().leave();
  }
}

// ─────────────────────────────────────────────
// Global CallKit Listener
// ─────────────────────────────────────────────
void _setupGlobalCallKitListener() {
  FlutterCallkitIncoming.onEvent.listen((CallEvent? event) async {
    if (event == null) return;
    try {
      final body = Map<String, dynamic>.from(event.body ?? {});
      final extra = Map<String, dynamic>.from(body['extra'] ?? {});
      final String? dealId = body['id']?.toString() ?? extra['dealId']?.toString();

      if (dealId == null) return;

      switch (event.event) {
        case Event.actionCallAccept:
          await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

        
          // 1. Init Agora
          await AgoraService().init(
            token: extra['receiverToken'] ?? '',
            channel: dealId,
            uid: int.parse(extra["receiverUid"].toString()),
          );
             await FirebaseFirestore.instance.collection('calls').doc(dealId).update({
            'callStatus': 'connected'
          });

          // 2. Update Firestore
       

          await FlutterCallkitIncoming.setCallConnected(dealId);
          break;

        case Event.actionCallDecline:
        case Event.actionCallEnded:
          await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
        
          await AgoraService().leave();
            await http.post(
              Uri.parse("$cloudFunctionUrl/terminateCall"),
              headers: {"Content-Type": "application/json"},
              body: jsonEncode({
                "dealId": dealId,
                "callerFCMToken": extra['callerFCMToken'],
              }),
            );
            await FirebaseFirestore.instance.collection('calls').doc(dealId).delete();
          

          await FlutterCallkitIncoming.endAllCalls();
          break;

        default:
          break;
      }
    } catch (e, st) {
      debugPrint('⚠️ CallKit error: $e\n$st');
    }
  });
}

Future<void> _warmUpCallQueries() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  await FirebaseFirestore.instance
      .collection('calls')
      .where('callStatus', whereIn: ['ringing', 'connected'])
      .where(Filter.or(
        Filter('callerFirebaseUid', isEqualTo: user.uid),
        Filter('receiverFirebaseUid', isEqualTo: user.uid),
      ))
      .orderBy('createdAt', descending: true)
      .limit(1)
      .get(const GetOptions(source: Source.serverAndCache));
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  _setupGlobalCallKitListener();
  unawaited(_warmUpCallQueries());
  runApp(const CallPriorityApp());
}

class CallPriorityApp extends StatefulWidget {
  const CallPriorityApp({super.key});

  @override
  State<CallPriorityApp> createState() => _CallPriorityAppState();
}

class _CallPriorityAppState extends State<CallPriorityApp> with WidgetsBindingObserver {
  final Connectivity _connectivity = Connectivity();
  late StreamSubscription<List<ConnectivityResult>> _connectivitySubscription;
  List<ConnectivityResult> _connectionStatus = [ConnectivityResult.mobile];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initConnectivity();
  }

  Future<void> _initConnectivity() async {
    try {
      final result = await _connectivity.checkConnectivity();
      if (mounted) setState(() => _connectionStatus = result );
    } on PlatformException catch (_) {}
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen((result) {
      if (mounted) setState(() => _connectionStatus = result);
    });
  }

  @override
  void dispose() {
    _connectivitySubscription.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnapshot) {
        if (authSnapshot.connectionState == ConnectionState.waiting) {
          return _buildMinimalLoader();
        }

        final user = authSnapshot.data;

        return CallRootRouter(
          user: user,
          connectionStatus: _connectionStatus,
        );
      },
    );
  }

  Widget _buildMinimalLoader() {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(child: RotatingDotsIndicator()),
      ),
    );
  }
}

class CallRootRouter extends StatelessWidget {
  final User? user;
  final List<ConnectivityResult> connectionStatus;

  const CallRootRouter({
    super.key,
    this.user,
    required this.connectionStatus,
  });

  @override
  Widget build(BuildContext context) {
    if (connectionStatus.contains(ConnectivityResult.none)) {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: VerifyInternetScreen(),
      );
    }

    return StreamBuilder<QuerySnapshot>(
      stream: user == null
          ? null
          : FirebaseFirestore.instance
              .collection('calls')
              .where('callStatus', whereIn: ['ringing', 'connecting', 'connected'])
              .where(Filter.or(
                Filter('callerFirebaseUid', isEqualTo: user!.uid),
                Filter('receiverFirebaseUid', isEqualTo: user!.uid),
              ))
              .orderBy('createdAt', descending: true)
              .limit(1)
              .snapshots(),
      builder: (context, callSnapshot) {
        // ── ACTIVE CALL PATH ── (highest priority)
        if (callSnapshot.hasData && callSnapshot.data!.docs.isNotEmpty) {
          final doc = callSnapshot.data!.docs.first;
          final data = doc.data() as Map<String, dynamic>;
          final status = (data['callStatus'] ?? '') as String;
          final isCaller = data['callerFirebaseUid'] == user?.uid;

          if (status == 'connected') {
            return MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData.dark(),
              home: Material(color: Colors.black, child: AgoraActiveCallScreen(data: data)),
            );
          }

          if (status == 'ringing' || status == 'connecting') {
            return MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData.dark(),
              home: Material(
                color: Colors.black,
                child: isCaller
                    ? OutgoingCallOverlay(data: data)
                    : IncomingCallOverlay(data: data),
              ),
            );
          }
        }

        // ── NO ACTIVE CALL ── proceed with normal login flow
        if (user == null) {
          return _buildThemedApp(
            darkMode: false,
            locale: const Locale('fr'),
            home: const ShnellWelcomeScreen(),
          );
        }

        // Try cache first for speed
        return FutureBuilder<DocumentSnapshot>(
          future: FirebaseFirestore.instance
              .collection('users')
              .doc(user!.uid)
              .get(const GetOptions(source: Source.cache)),
          builder: (context, cacheSnap) {
            Map<String, dynamic>? initialUserData;
            if (cacheSnap.hasData && cacheSnap.data!.exists) {
              initialUserData = cacheSnap.data!.data() as Map<String, dynamic>?;
            }

            return StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance.collection('users').doc(user!.uid).snapshots(),
              initialData: cacheSnap.data,
              builder: (context, userSnap) {
                if (userSnap.connectionState == ConnectionState.waiting && initialUserData == null) {
                  return _buildMinimalLoader();
                }

                final userData = (userSnap.hasData && userSnap.data!.exists)
                    ? userSnap.data!.data() as Map<String, dynamic>?
                    : initialUserData;

                if (userData == null) {
                  return _buildMinimalLoader();
                }

                final darkMode = userData['darkMode'] as bool? ?? true;
                final languageCode = userData['language'] as String? ?? 'fr';

                WidgetsBinding.instance.addPostFrameCallback((_) {
                  mapStyleNotifier.value = darkMode ? darkMapStyle : lightMapStyle;
                });

                return StreamBuilder<DocumentSnapshot>(
                  stream: FirebaseFirestore.instance.collection('settings').doc('config').snapshots(),
                  builder: (context, configSnap) {
                    if (configSnap.connectionState == ConnectionState.waiting) {
                      return _buildThemedApp(
                        darkMode: darkMode,
                        locale: Locale(languageCode),
                        home: const MainUsersScreen(),
                      );
                    }

                    if (configSnap.hasError || !configSnap.hasData || !configSnap.data!.exists) {
                      return _buildThemedApp(
                        darkMode: darkMode,
                        locale: Locale(languageCode),
                        home: const MainUsersScreen(),
                      );
                    }

                    final requiredVersion = configSnap.data!.get('version_customer_app') as String? ?? '';
                    if (requiredVersion.isNotEmpty && requiredVersion != _currentAppVersion) {
                      return _buildThemedApp(
                        darkMode: darkMode,
                        locale: Locale(languageCode),
                        home: const UpdateAppScreen(),
                      );
                    }

                    return _buildThemedApp(
                      darkMode: darkMode,
                      locale: Locale(languageCode),
                      home: const MainUsersScreen(),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildThemedApp({
    required bool darkMode,
    required Locale locale,
    required Widget home,
  }) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      theme: ThemeData(
        fontFamily: GoogleFonts.inter().fontFamily,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.amber,
          brightness: Brightness.light,
        ),
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        fontFamily: GoogleFonts.inter().fontFamily,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.amber,
          brightness: Brightness.dark,
        ),
        brightness: Brightness.dark,
      ),
      themeMode: darkMode ? ThemeMode.dark : ThemeMode.light,
      home: CallOverlayWrapper(child: home),  // your original overlay wrapper
    );
  }
}


Widget _buildMinimalLoader() {
  return const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      body: Center(child: RotatingDotsIndicator()),
    ),
  );
}