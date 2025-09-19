import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// 1. Add localization imports
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:shnell/SignInScreen.dart';
import 'package:shnell/SignUpScreen.dart';
import 'package:shnell/dots.dart';
import 'package:shnell/firebase_options.dart';
import 'package:shnell/mainUsers.dart' show MainUsersScreen;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final Connectivity _connectivity = Connectivity();
  late StreamSubscription<List<ConnectivityResult>> _connectivitySubscription;
  List<ConnectivityResult> _connectionStatus = [ConnectivityResult.mobile];

  @override
  void initState() {
    super.initState();
    initConnectivity();
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(_updateConnectionStatus);
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
      debugPrint('Couldn\'t check connectivity status, error: $e');
      return;
    }

    if (!mounted) {
      return Future.value(null);
    }
    return _updateConnectionStatus(result);
  }

  Future<void> _updateConnectionStatus(List<ConnectivityResult> result) async {
    setState(() {
      _connectionStatus = result;
    });
    debugPrint('Connectivity changed: $_connectionStatus');
  }

  ThemeData getLightTheme() => ThemeData(
            fontFamily: GoogleFonts.inter().fontFamily,
    colorScheme: ColorScheme.fromSeed(
      seedColor: Colors.amber, // 🌟 set amber as seed
      brightness: Brightness.light, // or Brightness.dark if you want dark mode
    ),
        // ... (your light theme code)
            primaryColor: const Color.fromARGB(255, 255, 193, 7),

        scaffoldBackgroundColor: const Color.fromARGB(255, 255, 255, 255),
        brightness: Brightness.light,
        // ...
      );

  ThemeData getDarkTheme() => ThemeData(
            fontFamily: GoogleFonts.inter().fontFamily,
    colorScheme: ColorScheme.fromSeed(
      seedColor: Colors.amber, // 🌟 set amber as seed
      brightness: Brightness.dark, // or Brightness.dark if you want dark mode
    ),
    primaryColor: const Color.fromARGB(255, 255, 193, 7),
        // ... (your dark theme code)
        scaffoldBackgroundColor: const Color.fromARGB(255, 0, 0, 0),
        brightness: Brightness.dark,
        // ...
      );

  @override
  Widget build(BuildContext context) {
    if (_connectionStatus.contains(ConnectivityResult.none)) {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Center(child: RotatingDotsIndicator()),
      );
    }

    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Center(child: RotatingDotsIndicator()),
          );
        }

        // Case: No user logged in
        if (!snapshot.hasData) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            // Use default locale and delegates for unauthenticated users
            locale: const Locale('fr'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            theme: getDarkTheme(),
            darkTheme: getDarkTheme(),
            themeMode: ThemeMode.dark,
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
                home: Center(child: RotatingDotsIndicator()),
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
                
                // Use default locale and delegates while data is being set
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
              // Set the locale based on the Firebase value
              locale: Locale(languageCode),
              // Use the generated delegates and supported locales
              supportedLocales: AppLocalizations.supportedLocales,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              theme: getLightTheme(),
              darkTheme: getDarkTheme(),
              themeMode: darkMode ? ThemeMode.dark : ThemeMode.light,
              home: role == 'user' ? const MainUsersScreen() : const SignupScreen(),
            );
          },
        );
      },
    );
  }
}