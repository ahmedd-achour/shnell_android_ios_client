/*import 'dart:async';
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
import 'package:shnell/SignInScreen.dart';
import 'package:shnell/calls/VoiceCall.dart';
import 'package:shnell/calls/customIncommingCall.dart'; // Your custom incoming call overlay
import 'package:shnell/dots.dart';
import 'package:shnell/firebase_options.dart';
import 'package:shnell/mainUsers.dart';
import 'package:shnell/model/calls.dart';
import 'package:shnell/updateApp.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// Background handler – App killed or in background
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  final data = message.data;

  if (data['type'] == 'call') {
    final params = CallKitParams(
      id: data['dealId'],
      nameCaller: data['callerName'] ?? 'Shnell',
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
      ),
    );

    await FlutterCallkitIncoming.showCallkitIncoming(params);
  }

  if (data['type'] == 'call_terminated') {
    await FlutterCallkitIncoming.endAllCalls();
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  // Setup CallKit listener as early as possible
  //_setupCallKitListener();


  runApp(const MyApp());
}






// Global CallKit event listener (works in all app states)

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
  Locale? _locale;
  String? _activeDealId;

    StreamSubscription? _callKitSub;
  StreamSubscription? _connectivitySub;
  static const String _currentAppVersion = "1.0.0";
  void _setupForegroundFCM() {
    FirebaseMessaging.onMessage.listen((message) async {
      final data = message.data;
      if (data['type'] != 'call') return;

      if (WidgetsBinding.instance.lifecycleState !=
          AppLifecycleState.resumed) return;

      final dealId = data['dealId'];
      if (dealId == null || dealId == _activeDealId) return;

      final doc = await FirebaseFirestore.instance
          .collection('calls')
          .doc(dealId)
          .get();

      if (!doc.exists) return;

      final call = Call.fromFirestore(doc);
      _activeDealId = dealId;

      navigatorKey.currentState?.push(
        PageRouteBuilder(
          opaque: false,
          barrierColor: Colors.black.withOpacity(0.7),
          pageBuilder: (_, __, ___) => IncomingCallOverlay(
            call: call,
            onAccept: () async {
              await FirebaseFirestore.instance
                  .collection('calls')
                  .doc(dealId)
                  .update({'callStatus': 'connected'});
                  

              navigatorKey.currentState?.pop();
              navigatorKey.currentState?.push(
                MaterialPageRoute(
                  builder: (_) =>
                      VoiceCallScreen(call: call, isCaller: false),
                ),
              );
            },
            onDecline: () async {
              await FirebaseFirestore.instance
                  .collection('calls')
                  .doc(dealId)
                  .update({'callStatus': 'declined'});
              _activeDealId = null;
              navigatorKey.currentState?.pop();
            },
          ),
        ),
      );
    });
  }

    void _setupCallKitListener() {
    _callKitSub = FlutterCallkitIncoming.onEvent.listen((event) async {
      if (event == null) return;

      final body = Map<String, dynamic>.from(event.body ?? {});
      final extra = Map<String, dynamic>.from(body['extra'] ?? {});
      final dealId = extra['dealId'];
      if (dealId == null) return;

      switch (event.event) {
        case Event.actionCallAccept:
          _activeDealId = dealId;

          final doc = await FirebaseFirestore.instance
              .collection('calls')
              .doc(dealId)
              .get();

          if (!doc.exists) return;

          navigatorKey.currentState?.push(
            MaterialPageRoute(
              builder: (_) => VoiceCallScreen(
                call: Call.fromFirestore(doc),
                isCaller: false,
              ),
            ),
          );
          break;

        case Event.actionCallDecline:
        case Event.actionCallEnded:
          await FirebaseFirestore.instance
              .collection('calls')
              .doc(dealId)
              .update({'callStatus': 'declined'});

          _activeDealId = null;
          await FlutterCallkitIncoming.endAllCalls();
          break;

        default:
          break;
      }
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
       super.initState();
    _setupCallKitListener();
    initConnectivity();
    _setupForegroundFCM();
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(_updateConnectionStatus);
    // Foreground FCM handling
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
  }

  @override

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
        WidgetsBinding.instance.removeObserver(this);
    _callKitSub?.cancel();
    _connectivitySub?.cancel();
    _connectivitySubscription.cancel();
    super.dispose();
  }
  List<ConnectivityResult> _connectionStatus = [ConnectivityResult.mobile];

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
    // 1. Check Internet Connectivity
    if (_connectionStatus.contains(ConnectivityResult.none)) {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(body: Center(child: RotatingDotsIndicator())),
      );
    }

    // 2. Check App Version from Firestore Settings
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('settings').doc('config').snapshots(),
      builder: (context, settingsSnapshot) {
        // While checking version, show loader
        if (settingsSnapshot.connectionState == ConnectionState.waiting) {
          return const MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(body: Center(child: RotatingDotsIndicator())),
          );
        }

        if (settingsSnapshot.hasError || !settingsSnapshot.hasData || !settingsSnapshot.data!.exists) {
          return const MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(body: Center(child: Text("Configuration Error"))),
          );
        }

        final settingsData = settingsSnapshot.data!.data() as Map<String, dynamic>;
        final String requiredVersion = settingsData['version_customer_app'] ?? '';

        // VERSION CHECK LOGIC
        if (requiredVersion != _currentAppVersion) {
          return  MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData.dark(),
            darkTheme: ThemeData.dark(),
            themeMode: ThemeMode.light,
            
            home: UpdateAppScreen()
          );
        }

        // 3. Version OK -> Proceed to Auth Check
        return StreamBuilder<User?>(
          stream: FirebaseAuth.instance.authStateChanges(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const MaterialApp(
                debugShowCheckedModeBanner: false,
                home: Scaffold(body: Center(child: RotatingDotsIndicator())),
              );
            }

            // Case: No user logged in (Off Registration Mode)
            if (!snapshot.hasData) {
              return MaterialApp(
                debugShowCheckedModeBanner: false,
                // ICI: On utilise la variable _locale, ou 'fr' par défaut si null
                locale: _locale ?? const Locale('fr'), 
                supportedLocales: AppLocalizations.supportedLocales,
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                theme: getLightTheme(),
                darkTheme: getDarkTheme(),
                themeMode: ThemeMode.light,
                home: const SignInScreen(),
              );
            }

            // Case: User is logged in
            final user = snapshot.data!;
            return StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots(),
              builder: (context, userSnapshot) {
                if (userSnapshot.connectionState == ConnectionState.waiting) {
                  return const MaterialApp(
                    debugShowCheckedModeBanner: false,
                    home: Scaffold(body: Center(child: RotatingDotsIndicator())),
                  );
                }

                final data = userSnapshot.data?.data() as Map<String, dynamic>?;

                if (data == null) {
                  // Create default document if missing
                  FirebaseFirestore.instance.collection('users').doc(user.uid).set({
                    'email': user.email ?? '',
                    'name': user.displayName ?? 'User',
                    'language': 'fr',
                    'darkMode': true,
                  }, SetOptions(merge: true));

                  return MaterialApp(
                    debugShowCheckedModeBanner: false,
                    locale: const Locale('fr'),
                    supportedLocales: AppLocalizations.supportedLocales,
                    localizationsDelegates: AppLocalizations.localizationsDelegates,
                    theme: getDarkTheme(),
                    darkTheme: getDarkTheme(),
                    themeMode: ThemeMode.dark,
                    home: const MainUsersScreen(),
                  );
                }

                // Retrieve values from Firebase
                final bool darkMode = data['darkMode'] ?? true;
                final String role = data['role'] ?? 'user';
                final String languageCode = data['language'] ?? 'fr';

                return MaterialApp(
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



}*/


import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_callkit_incoming/entities/android_params.dart';
import 'package:flutter_callkit_incoming/entities/call_kit_params.dart';
import 'package:flutter_callkit_incoming/entities/ios_params.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
// 1. Add localization imports
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shnell/FcmManagement.dart';

import 'package:shnell/SignInScreen.dart';
import 'package:shnell/calls/CallService.dart';
import 'package:shnell/dots.dart';
import 'package:shnell/firebase_options.dart';
import 'package:shnell/mainUsers.dart';
import 'package:shnell/updateApp.dart';

// Dans votre main.dart ou un écran de splash
// À ajouter dans le initState de votre widget principal ou dans main()
Future<void> updateFcmToken() async {
  // 1. Get the current token
  String? token = await FirebaseMessaging.instance.getToken();
  
  if (token != null) {
    String uid = FirebaseAuth.instance.currentUser!.uid;
    
    // 2. Save it to Firestore (overwrite the old one)
    await FirebaseFirestore.instance.collection('users').doc(uid).update({
      'fcmToken': token,
    });
  }

  // 3. Listen for future changes (e.g. if token rotates while app is running)
  FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
    String uid = FirebaseAuth.instance.currentUser!.uid;
    FirebaseFirestore.instance.collection('users').doc(uid).update({
      'fcmToken': newToken,
    });
 
  });

  FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
  if (message.data['type'] == 'call_terminated') {
    await FlutterCallkitIncoming.endAllCalls();
  }});
}

// 2. Import du Wrapper d'appel

// 3. Clé de navigation globale (Doit être en top-level)

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  if (message.data['type'] == 'call') {
    final data = message.data;

    final params = CallKitParams(
      id: data['uuid'] ?? data['dealId'],
      nameCaller: data['driverId'] ?? 'Shnell Driver',
      appName: 'Shnell',
      handle: 'Appel entrant',
      type: 0,
      duration: 45000,
      extra: <String, dynamic>{...data},
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
      ),
    );

    await FlutterCallkitIncoming.showCallkitIncoming(params);

  } // ← THIS } WAS MISSING!!!

  else if (message.data['type'] == 'call_terminated') {
    // This will now RUN
    await Future.delayed(const Duration(milliseconds: 300));
    await FlutterCallkitIncoming.endAllCalls();
  }
}


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  
  // Initialisation FCM si user déjà connecté (pour le cold start)
  if(FirebaseAuth.instance.currentUser != null) {
    FCMTokenManager().initialize();
  }
   if(FirebaseAuth.instance.currentUser != null){
      await updateFcmToken();
    }


    // THIS IS THE MAGIC LINE — GLOBAL LISTENER THAT WORKS EVEN AFTER COLD START
// In callListnerWraper.dart OR in main.dart — wherever you listen
await CallService().init();


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

class _MyAppState extends State<MyApp> {
  final Connectivity _connectivity = Connectivity();
  late StreamSubscription<List<ConnectivityResult>> _connectivitySubscription;
  List<ConnectivityResult> _connectionStatus = [ConnectivityResult.mobile];
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  Locale? _locale;
  static const String _currentAppVersion = "1.0.0";

  @override
  void initState() {
    super.initState();
    initConnectivity();
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(_updateConnectionStatus);
  }
  
  void setLocale(Locale value) {
    setState(() {
      _locale = value;
    });
  }

  @override

  void dispose() {
    _connectivitySubscription.cancel();
    super.dispose();
  }

  Future<void> initConnectivity() async {
    late List<ConnectivityResult> result;
    try {
      result = await _connectivity.checkConnectivity();
    } on PlatformException catch (e) {
      debugPrint('Connectivity Error: $e');
      return;
    }
    if (!mounted) return;
    _updateConnectionStatus(result);
  }

  Future<void> _updateConnectionStatus(List<ConnectivityResult> result) async {
    setState(() => _connectionStatus = result);
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
    // 1. Check Internet Connectivity
    if (_connectionStatus.contains(ConnectivityResult.none)) {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(body: Center(child: RotatingDotsIndicator())),
      );
    }

    // 2. Check App Version from Firestore Settings
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('settings').doc('config').snapshots(),
      builder: (context, settingsSnapshot) {
        // While checking version, show loader
        if (settingsSnapshot.connectionState == ConnectionState.waiting) {
          return const MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(body: Center(child: RotatingDotsIndicator())),
          );
        }

        if (settingsSnapshot.hasError || !settingsSnapshot.hasData || !settingsSnapshot.data!.exists) {
          return const MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(body: Center(child: Text("Configuration Error"))),
          );
        }

        final settingsData = settingsSnapshot.data!.data() as Map<String, dynamic>;
        final String requiredVersion = settingsData['version_customer_app'] ?? '';

        // VERSION CHECK LOGIC
        if (requiredVersion != _currentAppVersion) {
          return  MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData.dark(),
            darkTheme: ThemeData.dark(),
            themeMode: ThemeMode.light,
            
            home: UpdateAppScreen()
          );
        }

        // 3. Version OK -> Proceed to Auth Check
        return StreamBuilder<User?>(
          stream: FirebaseAuth.instance.authStateChanges(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const MaterialApp(
                debugShowCheckedModeBanner: false,
                home: Scaffold(body: Center(child: RotatingDotsIndicator())),
              );
            }

            // Case: No user logged in (Off Registration Mode)
            if (!snapshot.hasData) {
              return MaterialApp(
                debugShowCheckedModeBanner: false,
                // ICI: On utilise la variable _locale, ou 'fr' par défaut si null
                locale: _locale ?? const Locale('fr'), 
                supportedLocales: AppLocalizations.supportedLocales,
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                theme: getLightTheme(),
                darkTheme: getDarkTheme(),
                themeMode: ThemeMode.light,
                home: const SignInScreen(),
              );
            }

            // Case: User is logged in
            final user = snapshot.data!;
            return StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots(),
              builder: (context, userSnapshot) {
                if (userSnapshot.connectionState == ConnectionState.waiting) {
                  return const MaterialApp(
                    debugShowCheckedModeBanner: false,
                    home: Scaffold(body: Center(child: RotatingDotsIndicator())),
                  );
                }

                final data = userSnapshot.data?.data() as Map<String, dynamic>?;

                if (data == null) {
                  // Create default document if missing
                  FirebaseFirestore.instance.collection('users').doc(user.uid).set({
                    'email': user.email ?? '',
                    'name': user.displayName ?? 'User',
                    'language': 'fr',
                    'darkMode': true,
                  }, SetOptions(merge: true));

                  return MaterialApp(
                    debugShowCheckedModeBanner: false,
                    locale: const Locale('fr'),
                    supportedLocales: AppLocalizations.supportedLocales,
                    localizationsDelegates: AppLocalizations.localizationsDelegates,
                    theme: getDarkTheme(),
                    darkTheme: getDarkTheme(),
                    themeMode: ThemeMode.dark,
                    home: const MainUsersScreen(),
                  );
                }

                // Retrieve values from Firebase
                final bool darkMode = data['darkMode'] ?? true;
                final String role = data['role'] ?? 'user';
                final String languageCode = data['language'] ?? 'fr';

                return MaterialApp(
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