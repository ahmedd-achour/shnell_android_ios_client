import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/call_event.dart';
import 'package:flutter_callkit_incoming/entities/call_kit_params.dart';
import 'package:flutter_callkit_incoming/entities/android_params.dart';
import 'package:flutter_callkit_incoming/entities/ios_params.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shnell/calls/VoiceCall.dart';
import 'package:shnell/calls/customIncommingCall.dart'; // Your custom incoming call overlay
import 'package:shnell/dots.dart';
import 'package:shnell/firebase_options.dart';
import 'package:shnell/mainUsers.dart';
import 'package:shnell/model/calls.dart';
import 'package:shnell/updateApp.dart';
import 'package:shnell/SignInScreen.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// Background handler – App killed or in background
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  if (message.data['type'] == 'call') {
    final data = message.data;

    final CallKitParams params = CallKitParams(
      id: data['dealId'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
      nameCaller: data['callerName'] ?? data['driverId'] ?? 'Shnell Driver',
      appName: 'Shnell',
      handle: 'Incoming call',
      type: 0,
      duration: 45000,
      extra: <String, dynamic>{'dealId': data['dealId'], ...data},
      android: const AndroidParams(
        isCustomNotification: true,
        isShowLogo: true,
        ringtonePath: 'system_ringtone_default',
        backgroundColor: '#0955fa',
        actionColor: '#4CAF50',
        isShowFullLockedScreen: true,
      ),
      ios: const IOSParams(
        handleType: 'generic',
        supportsVideo: false,
        maximumCallGroups: 1,
        maximumCallsPerCallGroup: 1,
        iconName: 'CallKitLogo', // Optional: add your icon in iOS Runner/Assets.xcassets
      ),
    );

    await FlutterCallkitIncoming.showCallkitIncoming(params);
  } else if (message.data['type'] == 'call_terminated') {
    await FlutterCallkitIncoming.endAllCalls();
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  // Setup CallKit listener as early as possible
  _setupCallKitListener();

  runApp(const MyApp());
}

// Global CallKit event listener (works in all app states)
void _setupCallKitListener() {
  FlutterCallkitIncoming.onEvent.listen((CallEvent? event) async {
    if (event == null) return;

    final String? callId = event.body['id']?.toString();
    final Map<String, dynamic>? extra =
        event.body['extra'] is Map ? Map<String, dynamic>.from(event.body['extra']) : null;
    final String? dealId = extra?['dealId']?.toString() ?? callId;

    if (dealId == null) return;

    switch (event.event) {
      case Event.actionCallAccept:
        await FirebaseFirestore.instance
            .collection('calls')
            .doc(dealId)
            .update({'callStatus': 'connected'});

        final doc = await FirebaseFirestore.instance.collection('calls').doc(dealId).get();
        if (!doc.exists) return;

        final data = doc.data()!;
        final call = Call(
          dealId: dealId,
          callerId: data['callerId'] ?? '',
          receiverId: data['receiverId'] ?? '',
          driverId: data['receiverId'] ?? '',
          callStatus: 'connected',
          agoraChannel: data['agoraChannel'] ?? '',
          agoraToken: data['receiverToken'] ?? '',
          userId: '',
          callId: dealId,
        );

        // Navigate only if the app is open
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (navigatorKey.currentState?.mounted ?? false) {
            navigatorKey.currentState?.pushAndRemoveUntil(
              MaterialPageRoute(
                builder: (_) => VoiceCallScreen(call: call, isCaller: false),
              ),
              (route) => route.isFirst,
            );
          }
        });
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

      default:
        break;
    }
  });
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();

  static void setLocale(BuildContext context, Locale newLocale) {
    final state = context.findAncestorStateOfType<_MyAppState>();
    state?.setLocale(newLocale);
  }
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  final Connectivity _connectivity = Connectivity();
  late StreamSubscription<List<ConnectivityResult>> _connectivitySubscription;
  List<ConnectivityResult> _connectionStatus = [ConnectivityResult.mobile];
  Locale? _locale;

  static const String _currentAppVersion = "1.0.0";

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    initConnectivity();
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(_updateConnectionStatus);

    // Foreground FCM handling
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connectivitySubscription.cancel();
    super.dispose();
  }

  // Handle FCM when app is in FOREGROUND → show custom overlay instead of CallKit
  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    if (message.data['type'] == 'call') {
      final String dealId = message.data['dealId'].toString();

      final doc = await FirebaseFirestore.instance.collection('calls').doc(dealId).get();
      if (!doc.exists) return;

      final data = doc.data()!;
      final call = Call(
        dealId: dealId,
        callerId: data['callerId'] ?? 'Unknown Caller',
        receiverId: data['receiverId'] ?? '',
        driverId: data['receiverId'] ?? '',
        callStatus: data['callStatus'] ?? 'ringing',
        agoraChannel: data['agoraChannel'] ?? '',
        agoraToken: data['receiverToken'] ?? '',
        userId: '',
        callId: dealId,
      );

      // Show custom full-screen overlay only when app is resumed
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed &&
          navigatorKey.currentState != null) {
        navigatorKey.currentState?.push(
          PageRouteBuilder(
            opaque: false,
            barrierColor: Colors.black.withOpacity(0.8),
            transitionDuration: const Duration(milliseconds: 300),
            pageBuilder: (_, __, ___) => IncomingCallOverlay(
              call: call,
              onAccept: () async {
                 await FirebaseFirestore.instance
            .collection('calls')
            .doc(dealId)
            .update({'callStatus': 'connected'});
               navigatorKey.currentState?.pop(); // Close overlay
                navigatorKey.currentState?.push(
                  MaterialPageRoute(
                    builder: (_) => VoiceCallScreen(call: call, isCaller: false),
                  ),
                );
              },
              onDecline: () async {
                             await FirebaseFirestore.instance
            .collection('calls')
            .doc(dealId)
            .update({'callStatus': 'declined'});
                           navigatorKey.currentState?.pop(); // Close overlay
                  await FlutterCallkitIncoming.endAllCalls();
// Safety cleanup
              },
            ),
          ),
        );
      }
      // If not in foreground → background handler already showed CallKit
    } else if (message.data['type'] == 'call_terminated') {
      await FlutterCallkitIncoming.endAllCalls();
    }
  }
  void setLocale(Locale value) {
    setState(() => _locale = value);
  }

  Future<void> initConnectivity() async {
    try {
      final result = await _connectivity.checkConnectivity();
      if (!mounted) return;
      _updateConnectionStatus(result);
    } on PlatformException catch (e) {
      debugPrint('Connectivity Error: $e');
    }
  }

  void _updateConnectionStatus(List<ConnectivityResult> result) {
    setState(() => _connectionStatus = result);
  }

  ThemeData getLightTheme() => ThemeData(
        fontFamily: GoogleFonts.inter().fontFamily,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.amber,
          brightness: Brightness.light,
        ),
        primaryColor: const Color.fromARGB(255, 255, 193, 7),
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
        ),
        brightness: Brightness.light,
        useMaterial3: true,
      );

  ThemeData getDarkTheme() => ThemeData(
        fontFamily: GoogleFonts.inter().fontFamily,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.amber,
          brightness: Brightness.dark,
        ),
        primaryColor: const Color.fromARGB(255, 255, 193, 7),
        scaffoldBackgroundColor: Colors.black,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        brightness: Brightness.dark,
        useMaterial3: true,
      );

  @override
  Widget build(BuildContext context) {
    // No internet connection
    if (_connectionStatus.contains(ConnectivityResult.none)) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(child: RotatingDotsIndicator()),
        ),
      );
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('settings').doc('config').snapshots(),
      builder: (context, settingsSnapshot) {
        if (settingsSnapshot.connectionState == ConnectionState.waiting) {
          return const MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(body: Center(child: RotatingDotsIndicator())),
          );
        }

        if (!settingsSnapshot.hasData || !settingsSnapshot.data!.exists) {
          return const MaterialApp(
            home: Scaffold(body: Center(child: Text("Config Error"))),
          );
        }

        final settingsData = settingsSnapshot.data!.data() as Map<String, dynamic>;
        final String requiredVersion = settingsData['version_customer_app'] ?? '';

        // Force update if version mismatch
        if (requiredVersion != _currentAppVersion) {
          return const MaterialApp(
            debugShowCheckedModeBanner: false,
            home: UpdateAppScreen(),
          );
        }

        return StreamBuilder<User?>(
          stream: FirebaseAuth.instance.authStateChanges(),
          builder: (context, authSnapshot) {
            if (authSnapshot.connectionState == ConnectionState.waiting) {
              return const MaterialApp(
                debugShowCheckedModeBanner: false,
                home: Scaffold(body: Center(child: RotatingDotsIndicator())),
              );
            }

            final user = authSnapshot.data;

            // Not logged in
            if (user == null) {
              return MaterialApp(
                navigatorKey: navigatorKey,
                locale: _locale ?? const Locale('fr'),
                supportedLocales: AppLocalizations.supportedLocales,
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                theme: getLightTheme(),
                darkTheme: getDarkTheme(),
                themeMode: ThemeMode.light,
                debugShowCheckedModeBanner: false,
                home: const SignInScreen(),
              );
            }

            // Logged in – fetch user profile
            return StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots(),
              builder: (context, userSnapshot) {
                if (userSnapshot.connectionState == ConnectionState.waiting ||
                    !userSnapshot.hasData ||
                    !userSnapshot.data!.exists) {
                  return MaterialApp(
                    navigatorKey: navigatorKey,
                    debugShowCheckedModeBanner: false,
                    home: const Scaffold(body: Center(child: RotatingDotsIndicator())),
                  );
                }

                final data = userSnapshot.data!.data() as Map<String, dynamic>;
                final bool darkMode = data['darkMode'] ?? true;
                final String languageCode = data['language'] ?? 'fr';
                final String role = data['role'] ?? 'user';

                return MaterialApp(
                  navigatorKey: navigatorKey,
                  locale: Locale(languageCode),
                  supportedLocales: AppLocalizations.supportedLocales,
                  localizationsDelegates: AppLocalizations.localizationsDelegates,
                  theme: getLightTheme(),
                  darkTheme: getDarkTheme(),
                  themeMode: darkMode ? ThemeMode.dark : ThemeMode.light,
                  debugShowCheckedModeBanner: false,
                  home: role == 'user' ? const MainUsersScreen() : const SignInScreen(),
                );
              },
            );
          },
        );
      },
    );
  }
}