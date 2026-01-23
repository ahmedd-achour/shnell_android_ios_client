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

// This keeps the index alive even if the widget is destroyed and recreated
final ValueNotifier<int> persistentTabController = ValueNotifier<int>(0);


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
          
          // 2. Init Agora (Instance A)
          await AgoraService().init(
            token: extra['agoraToken'], 
            channel: dealId, 
            uid: extra["receiverUid"]
          );
          
          // 3. Update Firestore
          await FirebaseFirestore.instance.collection('calls').doc(dealId).update({
            'callStatus': 'connected'
          });
          await FlutterCallkitIncoming.setCallConnected(dealId);

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
  FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
  final User? user = FirebaseAuth.instance.currentUser;
  
  if (user != null && user.email != null) {
    // This is the background "Call Saver"
    // It updates the token in Firestore without the user doing anything
    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.email)
        .update({
          'fcmToken': newToken,
        });
  }
});

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
  static const String _currentAppVersion = "20.20.20";
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
    // 1. MASTER STREAM: Authentication
    //    We check this first. If they aren't logged in, nothing else matters.
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnapshot) {
        
        // --- State A: Loading Auth ---
        if (authSnapshot.connectionState == ConnectionState.waiting) {
          return _buildLoaderApp();
        }

        final User? user = authSnapshot.data;

        // --- State B: Guest / Not Logged In ---
        if (user == null) {
          return _buildMaterialApp(
            darkMode: false, // Force light mode for guests (or your preference)
            locale: _locale ?? const Locale('fr'),
            home: const ShnellWelcomeScreen(),
          );
        }

        // --- State C: Logged In (Fetch User Preferences) ---
        //    We fetch this NOW so that "No Internet" or "Update" screens 
        //    are still correctly themed in the user's language.
        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .snapshots(),
          builder: (context, userSnapshot) {
            
            // Wait for user data (cached or fresh)
            if (userSnapshot.connectionState == ConnectionState.waiting) {
              return _buildLoaderApp();
            }

            final userData = userSnapshot.data?.data() as Map<String, dynamic>?;

            // SECURITY: If doc is missing but auth exists -> Force Logout
               // SECURITY: If doc is missing but auth exists -> Force Logout
            if (!userSnapshot.hasData || !userSnapshot.data!.exists) {
  // Just show the loader and WAIT. 
  // The stream will rebuild automatically when the doc is created.
  return _buildLoaderApp(); 
}
            // Extract User Settings
            final bool darkMode = userData!['darkMode'] ?? true;
            final String languageCode = userData['language'] ?? 'fr';

            // Sync Map Style (Optimization: AddPostFrameCallback prevents render errors)
            WidgetsBinding.instance.addPostFrameCallback((_) {
              mapStyleNotifier.value = darkMode ? darkMapStyle : lightMapStyle;

            });
            // Add this near your mapStyleNotifier

            // --- State D: Render The Full App ---
            return _buildMaterialApp(
              darkMode: darkMode,
              
              locale: Locale(languageCode),
              // We pass the logic to a separate widget to keep 'build' clean
              home: _MainContentSwitcher(
                connectionStatus: _connectionStatus,
                configStream: _configStream,
                currentAppVersion: _currentAppVersion,
                // The ultimate success screen:
                child: CallOverlayWrapper(
                  
                  child: MainUsersScreen()
                  )
              ),
            );
          },
        );
      },
    );
  }

  // --- HELPER 1: The Unified MaterialApp ---
  //    Defined once here to avoid duplicating it 5 times in your code.
  Widget _buildMaterialApp({
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
      theme: getLightTheme(),
      darkTheme: getDarkTheme(),
      themeMode: darkMode ? ThemeMode.dark : ThemeMode.light,
      home: home,
    );
  }

  // --- HELPER 2: Simple Loading Screen ---
  Widget _buildLoaderApp() {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(body: Center(child: RotatingDotsIndicator())),
    );
  }
}

// --- LOGIC WIDGET: Decides which screen to show ---
//    This separates the "Business Logic" from the "UI/Theme Logic"
class _MainContentSwitcher extends StatelessWidget {
  final List<ConnectivityResult> connectionStatus;
  final Stream<DocumentSnapshot> configStream;
  final String currentAppVersion;
  final Widget child;

  const _MainContentSwitcher({
    Key? key,
    required this.connectionStatus,
    required this.configStream,
    required this.currentAppVersion,
    required this.child,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // 1. PRIORITY: Check Internet
    if (connectionStatus.contains(ConnectivityResult.none)) {
      return const VerifyInternetScreen();
    }

    // 2. PRIORITY: Check App Version
    return StreamBuilder<DocumentSnapshot>(
      stream: configStream,
      builder: (context, configSnapshot) {
        
        // If we are waiting for config, show loader or safe fallback
        if (configSnapshot.connectionState == ConnectionState.waiting) {
           return const Scaffold(body: Center(child: RotatingDotsIndicator()));
        }

        // If config fails, we usually let the user pass to avoid blocking them 
        // entirely due to a server glitch, unless strict versioning is required.
        if (configSnapshot.hasError || !configSnapshot.hasData || !configSnapshot.data!.exists) {
           // Option A: Let them in (Safe Fallback)
           return child; 
           // Option B: Show Error (Strict)
           // return const Scaffold(body: Center(child: Text("Config Error")));
        }

        final data = configSnapshot.data!.data() as Map<String, dynamic>;
        final String requiredVersion = data['version_customer_app'] ?? '';

        // If versions don't match -> Block with Update Screen
        if (requiredVersion.isNotEmpty && requiredVersion != currentAppVersion) {
          return const UpdateAppScreen();
        }

        // 3. PRIORITY: Success -> Show Main App
        return child;
      },
    );
  }
  }



