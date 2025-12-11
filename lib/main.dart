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
import 'package:shnell/calls/callListnerWraper.dart';
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
    if (_connectionStatus.contains(ConnectivityResult.none)) {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(body: Center(child: RotatingDotsIndicator())),
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

        if (settingsSnapshot.hasError || !settingsSnapshot.hasData || !settingsSnapshot.data!.exists) {
          return const MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(body: Center(child: Text("Config Error"))),
          );
        }

        final settingsData = settingsSnapshot.data!.data() as Map<String, dynamic>;
        final String requiredVersion = settingsData['version_customer_app'] ?? '';

        if (requiredVersion != _currentAppVersion) {
          return MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData.dark(),
              home: const UpdateAppScreen(),
          
          );
        }

        return StreamBuilder<User?>(
          stream: FirebaseAuth.instance.authStateChanges(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const MaterialApp(
                debugShowCheckedModeBanner: false,
                home: Scaffold(body: Center(child: RotatingDotsIndicator())),
              );
            }

            if (!snapshot.hasData) {
              return 
                MaterialApp(
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

                // Default User creation logic
                if (data == null) {
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
                    // WRAPPER AJOUTÉ ICI
                    home:   MaterialApp(
  home: CallListenerWrapper(
    navigatorKey: navigatorKey,
    child: MainUsersScreen(),
  ),
)
                  );
                }

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
                  // WRAPPER AJOUTÉ ICI (Le plus important)
                  builder: (context, child) {
                    return child ?? const SizedBox();
                    
                  },
                  home: role == 'user' ?              CallListenerWrapper(
                    navigatorKey: GlobalKey<NavigatorState>(),
                    child: CallListenerWrapper(
    navigatorKey: navigatorKey,
    child: MainUsersScreen(),
  ),
)
 : const SignInScreen(),
                );
              },
            );
          },
        );
      },
    );
  }
}