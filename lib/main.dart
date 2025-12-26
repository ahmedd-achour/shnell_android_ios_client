





















import 'dart:async';
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
import 'package:shnell/FcmManagement.dart';
import 'package:shnell/SignInScreen.dart';
import 'package:shnell/calls/VoiceCall.dart';
import 'package:shnell/calls/customIncommingCall.dart';
import 'package:shnell/dots.dart';
import 'package:shnell/firebase_options.dart';
import 'package:shnell/mainUsers.dart';
import 'package:shnell/model/calls.dart';
import 'package:shnell/updateApp.dart';
import 'package:shnell/verrifyInternet.dart';


// Update FCM token when app starts or token refreshes
Future<void> updateFcmToken() async {
  String? token = await FirebaseMessaging.instance.getToken();
  if (token != null && FirebaseAuth.instance.currentUser != null) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    await FirebaseFirestore.instance.collection('users').doc(uid).update({
      'fcmToken': token,
    });
  }

  FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
    if (FirebaseAuth.instance.currentUser != null) {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      FirebaseFirestore.instance.collection('users').doc(uid).update({
        'fcmToken': newToken,
      });
    }
  });
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  final data = message.data;

  if (data['type'] == 'call') {
    final params = CallKitParams(
      id: data['dealId'],
      nameCaller: data['callerName'] ?? 'Shnell Driver',
      appName: 'Shnell Driver',
      handle: 'Incoming Call',
      type: 0,
      duration: 45000,
      extra: Map<String, dynamic>.from(data),
      android: const AndroidParams(
        isCustomNotification: true,
        ringtonePath: 'system_ringtone_default',
        isShowFullLockedScreen: true,
      ),
      ios: const IOSParams(
        supportsVideo: false,
        maximumCallsPerCallGroup: 1,
        iconName: 'CallKitIcon', // Optional: add your app icon in iOS assets
      ),
    );

    await FlutterCallkitIncoming.showCallkitIncoming(params);
  }

  if (data['type'] == 'call_terminated') {
    await FlutterCallkitIncoming.endAllCalls();
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  // Initialize FCM token if user is already logged in
  if (FirebaseAuth.instance.currentUser != null) {
    FCMTokenManager().initialize();
    unawaited(updateFcmToken());
  }

  // Global CallKit listener (works even after cold start)
 //await CallService().init();

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  static void setLocale(BuildContext context, Locale newLocale) {
    _MyAppState? state = context.findAncestorStateOfType<_MyAppState>();
    state?.setLocale(newLocale);
  }

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  final Connectivity _connectivity = Connectivity();
  late StreamSubscription<List<ConnectivityResult>> _connectivitySubscription;
  List<ConnectivityResult> _connectionStatus = [ConnectivityResult.mobile];

  StreamSubscription<CallEvent?>? _callKitSubscription;

  Locale? _locale;
  static const String _currentAppVersion = "2.0.0";

  String? _activeCallId;

  @override

  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _initConnectivity();
    _setupCallKitListener();
    _setupForegroundMessaging();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Optional: react to lifecycle changes if needed
  }

  void setLocale(Locale locale) {
    setState(() => _locale = locale);
  }

  // Connectivity
  Future<void> _initConnectivity() async {
    try {
      final result = await _connectivity.checkConnectivity();
      if (mounted) _updateConnectionStatus(result);
    } on PlatformException catch (_) {}
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(_updateConnectionStatus);
  }

  void _updateConnectionStatus(List<ConnectivityResult> result) {
    setState(() => _connectionStatus = result);
  }

  // Foreground FCM handling – show custom overlay ONLY when app is active
void _setupForegroundMessaging() {
  FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
    final data = message.data;

    if (data['type'] == 'call_terminated') {
      await FlutterCallkitIncoming.endAllCalls();
      if (_activeCallId != null && navigatorKey.currentState?.canPop() == true) {
        navigatorKey.currentState?.pop();
      }
      _activeCallId = null;
      return;
    }

    if (data['type'] != 'call') return;

    final String dealId = data['dealId'];
    if (_activeCallId == dealId) return;

    // Only if truly in foreground
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return; // Let background handler show CallKit
    }

    final doc = await FirebaseFirestore.instance.collection('calls').doc(dealId).get();
    if (!doc.exists) return;

    final call = Call.fromFirestore(doc);
    _activeCallId = dealId;

    // CRITICAL: Suppress native CallKit UI in foreground
    //await FlutterCallkitIncoming.endAllCalls();

    // Show your beautiful full-screen custom overlay
    navigatorKey.currentState?.push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => IncomingCallOverlay(
          call: call,
          onAccept: () async {
            await FirebaseFirestore.instance.collection('calls').doc(dealId).update({
              'callStatus': 'connected',
            });
            navigatorKey.currentState?.pop();
            navigatorKey.currentState?.push(
              MaterialPageRoute(builder: (_) => VoiceCallScreen(call: call, isCaller: false)),
            );
          },
          onDecline: () async {
            await FirebaseFirestore.instance.collection('calls').doc(dealId).update({
              'callStatus': 'declined',
            });
            _activeCallId = null;
            navigatorKey.currentState?.pop();
            await FlutterCallkitIncoming.endAllCalls();
          },
        ),
      ),
    );
  });
}
  // Global CallKit listener – handles accept/decline from native UI (background/terminated)
 
 
 
  void _setupCallKitListener() {
    _callKitSubscription = FlutterCallkitIncoming.onEvent.listen((CallEvent? event) async {
      if (event == null) return;

      final extra = Map<String, dynamic>.from(event.body['extra'] ?? {});
      final String? dealId = extra['dealId']?.toString();
      if (dealId == null) return;

      switch (event.event) {
        case Event.actionCallAccept:
          _activeCallId = dealId;

          final doc = await FirebaseFirestore.instance.collection('calls').doc(dealId).get();
          if (!doc.exists) return;

          final call = Call.fromFirestore(doc);

          // Update status
          await FirebaseFirestore.instance
              .collection('calls')
              .doc(dealId)
              .update({'callStatus': 'connected'});

          navigatorKey.currentState?.push(
            MaterialPageRoute(
              builder: (_) => VoiceCallScreen(call: call, isCaller: false),
            ),
          );
          break;

        case Event.actionCallDecline:
        case Event.actionCallTimeout:
        case Event.actionCallEnded:
          await FirebaseFirestore.instance
              .collection('calls')
              .doc(dealId)
              .update({'callStatus': 'declined'});

          _activeCallId = null;
          await FlutterCallkitIncoming.endAllCalls();
          break;

        default:
          break;
      }
    });
  }

  @override
  void dispose() {
    _connectivitySubscription.cancel();
    _callKitSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  ThemeData getLightTheme() => ThemeData(
        fontFamily: GoogleFonts.inter().fontFamily,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.amber, brightness: Brightness.light),
        primaryColor: const Color.fromARGB(255, 255, 193, 7),
        scaffoldBackgroundColor: Colors.white,
        brightness: Brightness.light,
      );

  ThemeData getDarkTheme() => ThemeData(
        fontFamily: GoogleFonts.inter().fontFamily,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.amber, brightness: Brightness.dark),
        primaryColor: const Color.fromARGB(255, 255, 193, 7),
        scaffoldBackgroundColor: Colors.black,
        brightness: Brightness.dark,
      );

  @override
  Widget build(BuildContext context) {
    // No internet
    if (_connectionStatus.contains(ConnectivityResult.none)) {
      return  StreamBuilder<User?>(
          stream: FirebaseAuth.instance.authStateChanges(),
          builder: (context, authSnapshot) {
            if (authSnapshot.connectionState == ConnectionState.waiting) {
              return const MaterialApp(
                debugShowCheckedModeBanner: false,
                home: Scaffold(body: Center(child: RotatingDotsIndicator())),
              );
            }

            if (!authSnapshot.hasData) {
              return MaterialApp(
                navigatorKey: navigatorKey,
                debugShowCheckedModeBanner: false,
                locale: _locale ?? const Locale('fr'),
                supportedLocales: AppLocalizations.supportedLocales,
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                theme: getLightTheme(),
                darkTheme: getDarkTheme(),
                themeMode: ThemeMode.light,
                home: const SignInScreen(),
              );
            }

            final user = authSnapshot.data!;

            return StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots(),
              builder: (context, userSnapshot) {
                if (userSnapshot.connectionState == ConnectionState.waiting) {
                  return const MaterialApp(
                    debugShowCheckedModeBanner: false,
                    home: Scaffold(body: Center(child: RotatingDotsIndicator())),
                  );
                }

                final userData = userSnapshot.data?.data() as Map<String, dynamic>?;

                if (userData == null) {
                  FirebaseFirestore.instance.collection('users').doc(user.uid).set({
                    'email': user.email ?? '',
                    'name': user.displayName ?? 'User',
                    'language': 'fr',
                    'darkMode': true,
                  }, SetOptions(merge: true));
                }

                final bool darkMode = userData?['darkMode'] ?? true;
                final String languageCode = userData?['language'] ?? 'fr';

                return MaterialApp(
                  navigatorKey: navigatorKey,
                  debugShowCheckedModeBanner: false,
                  locale: Locale(languageCode),
                  supportedLocales: AppLocalizations.supportedLocales,
                  localizationsDelegates: AppLocalizations.localizationsDelegates,
                  theme: getLightTheme(),
                  darkTheme: getDarkTheme(),
                  themeMode: darkMode ? ThemeMode.dark : ThemeMode.light,
                  home: VerifyInternetScreen()
                );
              },
            );
          },
        );
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('settings').doc('config').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(body: Center(child: RotatingDotsIndicator())),
          );
        }

        if (snapshot.hasError || !snapshot.hasData || !snapshot.data!.exists) {
          return const MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(body: Center(child: Text("Configuration Error"))),
          );
        }

        final data = snapshot.data!.data() as Map<String, dynamic>;
        final String requiredVersion = data['version_customer_app'] ?? '';

        if (requiredVersion != _currentAppVersion) {
          return  StreamBuilder<User?>(
          stream: FirebaseAuth.instance.authStateChanges(),
          builder: (context, authSnapshot) {
            if (authSnapshot.connectionState == ConnectionState.waiting) {
              return const MaterialApp(
                debugShowCheckedModeBanner: false,
                home: Scaffold(body: Center(child: RotatingDotsIndicator())),
              );
            }

            if (!authSnapshot.hasData) {
              return MaterialApp(
                navigatorKey: navigatorKey,
                debugShowCheckedModeBanner: false,
                locale: _locale ?? const Locale('fr'),
                supportedLocales: AppLocalizations.supportedLocales,
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                theme: getLightTheme(),
                darkTheme: getDarkTheme(),
                themeMode: ThemeMode.light,
                home: const SignInScreen(),
              );
            }

            final user = authSnapshot.data!;

            return StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots(),
              builder: (context, userSnapshot) {
                if (userSnapshot.connectionState == ConnectionState.waiting) {
                  return const MaterialApp(
                    debugShowCheckedModeBanner: false,
                    home: Scaffold(body: Center(child: RotatingDotsIndicator())),
                  );
                }

                final userData = userSnapshot.data?.data() as Map<String, dynamic>?;

                if (userData == null) {
                  FirebaseFirestore.instance.collection('users').doc(user.uid).set({
                    'email': user.email ?? '',
                    'name': user.displayName ?? 'User',
                    'language': 'fr',
                    'darkMode': true,
                  }, SetOptions(merge: true));
                }

                final bool darkMode = userData?['darkMode'] ?? true;
                final String languageCode = userData?['language'] ?? 'fr';

                return MaterialApp(
                  navigatorKey: navigatorKey,
                  debugShowCheckedModeBanner: false,
                  locale: Locale(languageCode),
                  supportedLocales: AppLocalizations.supportedLocales,
                  localizationsDelegates: AppLocalizations.localizationsDelegates,
                  theme: getLightTheme(),
                  darkTheme: getDarkTheme(),
                  themeMode: darkMode ? ThemeMode.dark : ThemeMode.light,
                  home: UpdateAppScreen()
                );
              },
            );
          },
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

            if (!authSnapshot.hasData) {
              return MaterialApp(
                navigatorKey: navigatorKey,
                debugShowCheckedModeBanner: false,
                locale: _locale ?? const Locale('fr'),
                supportedLocales: AppLocalizations.supportedLocales,
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                theme: getLightTheme(),
                darkTheme: getDarkTheme(),
                themeMode: ThemeMode.light,
                home: const SignInScreen(),
              );
            }

            final user = authSnapshot.data!;

            return StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots(),
              builder: (context, userSnapshot) {
                if (userSnapshot.connectionState == ConnectionState.waiting) {
                  return const MaterialApp(
                    debugShowCheckedModeBanner: false,
                    home: Scaffold(body: Center(child: RotatingDotsIndicator())),
                  );
                }

                final userData = userSnapshot.data?.data() as Map<String, dynamic>?;

                if (userData == null) {
                  FirebaseFirestore.instance.collection('users').doc(user.uid).set({
                    'email': user.email ?? '',
                    'name': user.displayName ?? 'User',
                    'language': 'fr',
                    'darkMode': true,
                  }, SetOptions(merge: true));
                }

                final bool darkMode = userData?['darkMode'] ?? true;
                final String languageCode = userData?['language'] ?? 'fr';
                final String role = userData?['role'] ?? 'user';

                return MaterialApp(
                  navigatorKey: navigatorKey,
                  debugShowCheckedModeBanner: false,
                  locale: Locale(languageCode),
                  supportedLocales: AppLocalizations.supportedLocales,
                  localizationsDelegates: AppLocalizations.localizationsDelegates,
                  theme: getLightTheme(),
                  darkTheme: getDarkTheme(),
                  themeMode: darkMode ? ThemeMode.dark : ThemeMode.light,
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