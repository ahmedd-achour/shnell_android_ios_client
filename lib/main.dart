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
import 'package:shnell/calls/callUIController.dart';
import 'package:shnell/customMapStyle.dart';
import 'package:shnell/dots.dart';
import 'package:shnell/emailVerif.dart';
import 'package:shnell/firebase_options.dart';
import 'package:shnell/mainUsers.dart';
import 'package:shnell/updateApp.dart';
import 'package:shnell/verrifyInternet.dart';
import 'package:shnell/welcome.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final ValueNotifier<String> mapStyleNotifier = ValueNotifier<String>('');
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  final data = message.data;
  if (data['type'] == 'call') {
    // this is a new incoming call app must be inittiated in a call screen , crusial 
    final params = CallKitParams(
      id: data['dealId'],
      nameCaller: data['callerName'] ?? 'Shnell Driver',
      appName: 'Shnell Driver',
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
  }
}


void _setupGlobalCallKitListener() {
  FlutterCallkitIncoming.onEvent.listen((CallEvent? event) async {
    if (event == null) return;
    try {
      final Map<String, dynamic> body = Map<String, dynamic>.from(event.body ?? {});
      final Map<String, dynamic> extra = Map<String, dynamic>.from(body['extra'] ?? {});
      final String? dealId = body['id']?.toString() ?? extra['dealId']?.toString();

      if (dealId == null) return;

      switch (event.event) {
        case Event.actionCallAccept:
          // 1. Hand off to Native System UI (stops ringtone)
          await FlutterCallkitIncoming.setCallConnected(dealId);
          
          // 2. Init Agora (Instance A)
          await AgoraService().init(
            token: extra['receiverToken'], 
            channel: dealId, 
            uid: extra["receiverUid"]
          );
          
          // 3. Update Firestore
          await FirebaseFirestore.instance.collection('calls').doc(dealId).update({
            'callStatus': 'connected'
          });
          break;

        case Event.actionCallDecline:
        case Event.actionCallEnded:
          // --- THE SMART CLEANUP START ---
          
          // 1. ALWAYS free hardware resources immediately
          await AgoraService().leave(); 
          
          // 2. Check if the call still exists in DB before notifying
          final callDoc = await FirebaseFirestore.instance.collection('calls').doc(dealId).get();

          if (callDoc.exists) {
            // I am the first to hang up, notify the other person
            unawaited(http.post(
              Uri.parse("$cloudFunctionUrl/terminateCall"),
              headers: {"Content-Type": "application/json"},
              body: jsonEncode({
                "dealId": dealId,
                "callerFCMToken": extra['callerFCMToken'],
                "receiverFCMToken": extra['receiverFCMToken'],
              }),
            ));

            // Delete the doc so the peer doesn't trigger a loop back to us
            await FirebaseFirestore.instance.collection('calls').doc(dealId).delete();
            debugPrint('✅ Call terminated manually. Peer notified.');
          } else {
            // Doc is already gone. Peer must have hung up first.
            debugPrint('🧹 Doc already gone. Just cleaned local hardware.');
          }
          
          // 3. Clear all system UI notifications
          await FlutterCallkitIncoming.endAllCalls();
          break;

        default:
          break;
      }
    } catch (e, st) {
      debugPrint('⚠️ Error in CallKit listener: $e\n$st');
    }
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  _setupGlobalCallKitListener();

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
  final Connectivity _connectivity = Connectivity();
  late StreamSubscription<List<ConnectivityResult>> _connectivitySubscription;
  List<ConnectivityResult> _connectionStatus = [ConnectivityResult.mobile];

  Locale? _locale;
  static const String _currentAppVersion = "8.12.32";
  late Stream<DocumentSnapshot> _configStream;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _configStream = FirebaseFirestore.instance.collection('settings').doc('config').snapshots();
    _initConnectivity();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {}


  void setLocale(Locale locale) {
    setState(() => _locale = locale);
  }

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

  @override
  void dispose() {
    _connectivitySubscription.cancel();
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
    if (_connectionStatus.contains(ConnectivityResult.none)) {
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
              home: const ShnellWelcomeScreen(),
            );
          }

          return StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance.collection('users').doc(authSnapshot.data!.uid).snapshots(),
            builder: (context, userSnapshot) {
              if (userSnapshot.connectionState == ConnectionState.waiting) {
                return const MaterialApp(
                  debugShowCheckedModeBanner: false,
                  home: Scaffold(body: Center(child: RotatingDotsIndicator())),
                );
              }

              final userData = userSnapshot.data?.data() as Map<String, dynamic>?;
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
                home: const VerifyInternetScreen(),
              );
            },
          );
        },
      );
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: _configStream
      ,      builder: (context, snapshot) {
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
                  home: const ShnellWelcomeScreen(),
                );
              }
              return StreamBuilder<DocumentSnapshot>(
                stream: FirebaseFirestore.instance.collection('users').doc(authSnapshot.data!.uid).snapshots(),
                builder: (context, userSnapshot) {
                  if (userSnapshot.connectionState == ConnectionState.waiting) {
                    return const MaterialApp(
                      debugShowCheckedModeBanner: false,
                      home: Scaffold(body: Center(child: RotatingDotsIndicator())),
                    );
                  }

                  final userData = userSnapshot.data?.data() as Map<String, dynamic>?;
                  final bool darkMode = userData!['darkMode'] ?? true;
                  final String languageCode = userData['language'] ?? 'fr';

                  return MaterialApp(
                    navigatorKey: navigatorKey,
                    debugShowCheckedModeBanner: false,
                    locale: Locale(languageCode),
                    supportedLocales: AppLocalizations.supportedLocales,
                    localizationsDelegates: AppLocalizations.localizationsDelegates,
                    theme: getLightTheme(),
                    darkTheme: getDarkTheme(),
                    themeMode: darkMode ? ThemeMode.dark : ThemeMode.light,
                    home: const UpdateAppScreen(),
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
        home: const ShnellWelcomeScreen(),
      );
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(authSnapshot.data!.uid)
          .snapshots(),
      builder: (context, userSnapshot) {
        if (userSnapshot.connectionState == ConnectionState.waiting) {
          return const MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(body: Center(child: RotatingDotsIndicator())),
          );
        }

        final userData = userSnapshot.data?.data() as Map<String, dynamic>?;

        // SECURITY: If document missing or role invalid → sign out immediately
    

        final bool darkMode = userData!['darkMode'] ?? true;
        final String languageCode = userData['language'] ?? 'fr';

        WidgetsBinding.instance.addPostFrameCallback((_) {
          mapStyleNotifier.value = darkMode ? darkMapStyle : lightMapStyle;
        });

        return MaterialApp(
          navigatorKey: navigatorKey,
          debugShowCheckedModeBanner: false,
          locale: Locale(languageCode),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          theme: getLightTheme(),
          darkTheme: getDarkTheme(),
          themeMode: darkMode ? ThemeMode.dark : ThemeMode.light,
          home: FirebaseAuth.instance.currentUser!.emailVerified ==true ? CallOverlayWrapper(child: MainUsersScreen()):
          const EmailVerificationScreen(),
        );
      },
    );
  },
); },
    );
  }
}



