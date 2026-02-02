import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shnell/FcmManagement.dart';
import 'package:shnell/model/users.dart';

class GoogleSignInService {
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final GoogleSignIn _googleSignIn = GoogleSignIn.instance;

  static bool _isInitialized = false;

  static const String _serverClientId =
      '217120837439-2reugbpp9l30hs3snmcukhvnnsmksg9u.apps.googleusercontent.com';

  static Future<void> initSignIn() async {
    if (_isInitialized) return;
    await _googleSignIn.initialize(serverClientId: _serverClientId);
    _isInitialized = true;
  }

 /* void _snack(BuildContext context, String msg,
      {Color color = Colors.black, bool clear = true}) {
    if (!context.mounted) return;
    final m = ScaffoldMessenger.of(context);
    if (clear) m.clearSnackBars();
    m.showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: color,
        duration: const Duration(seconds: 4),
      ),
    );
  }*/

  Future<UserCredential?> signInWithGoogle(String phone, BuildContext context) async {
   // void s(String msg, {Color color = Colors.blueGrey}) =>
      //  _snack(context, '[$step] $msg', color: color);

    try {
     // s("init google_sign_in…", color: Colors.deepPurple);
      await initSignIn();

     // s("disconnect (reset session)…", color: Colors.deepPurple);
      await _googleSignIn.disconnect().catchError((_) {});

    //  s("authenticate()… (account picker)", color: Colors.orange);

      GoogleSignInAccount? account;
      try {
        account = await _googleSignIn.authenticate();
        
      } on PlatformException catch (e) {
       /* s("PlatformException: ${e.code} | ${e.message ?? ''}",
            color: Colors.redAccent);*/
      //  debugPrint("[GSI] PlatformException code=${e.code} message=${e.message} details=${e.details}");
        return null;
      } catch (e) {
        //s("authenticate threw: $e", color: Colors.redAccent);
        //debugPrint("[GSI] authenticate error: $e\n$st");
        return null;
      }

      if (account == null) {
       // s("cancelled by user (account == null)", color: Colors.orange);
        return null;
      }

      //s("picked: ${account.email}", color: const Color.fromARGB(255, 71, 114, 2));

      //s("get authentication tokens…", color: Colors.blue);

      final auth = await account.authentication;

      final String? idToken = auth.idToken;

      // We intentionally ignore accessToken completely.
     // debugPrint("[GSI] idTokenNull=${idToken == null} accessTokenPresent=${auth != null}");

      if (idToken == null) {
        //s("idToken is NULL → config/signing issue", color: Colors.redAccent);
        return null;
      }

     // s("build Firebase credential (ID TOKEN ONLY)…", color: Colors.blue);

      final credential = GoogleAuthProvider.credential(
        idToken: idToken,
        // accessToken omitted on purpose
      );

     // s("FirebaseAuth.signInWithCredential…", color: Colors.blue);

      final userCredential = await _auth.signInWithCredential(credential);

      final user = userCredential.user;
      if (user == null) {
       // s("Firebase user == null (unexpected)", color: Colors.redAccent);
        return userCredential;
      }

    //  s("signed in uid=${user.uid}", color: const Color.fromARGB(255, 71, 114, 2));

    //  s("check/create Firestore user doc…", color: Colors.teal);

      final ref = FirebaseFirestore.instance.collection('users').doc(user.uid);


      final snap = await ref.get();

      if (!snap.exists) {
       // s("creating user doc…", color: Colors.teal);
             String? token = await FirebaseMessaging.instance.getToken();

        await ref.set(
          shnellUsers(
            email: user.email ?? "",
            name: user.displayName ?? "",
            phone: phone,
            role: 'user',
            fcmToken: token
          ).toJson(),
        );
      } else {
              final token = await FirebaseMessaging.instance.getToken();

await ref.set({
  "phone": phone,
  "fcmToken": token,
  'role':"user",
  "email": user.email ?? "",
  "name": user.displayName ?? "",
}, SetOptions(merge: true));
       // s("user doc exists", color: Colors.teal);
      }

    //  s("init FCM token…", color: Colors.teal);
      // FCMTokenManager().initialize(user);

     // s("DONE ✅", color: const Color.fromARGB(255, 71, 114, 2));
      return userCredential;

    } on FirebaseAuthException catch (e) {
     // _snack(context, "FirebaseAuthException: ${e.code} ${e.message ?? ''}",
        //  color: Colors.redAccent);
     // debugPrint("[AUTH] FirebaseAuthException ${e.code}: ${e.message}\n$st");
      rethrow;
    } catch (e) {
    //  _snack(context, "Unexpected error: $e", color: Colors.redAccent);
    //  debugPrint("[AUTH] Unexpected error: $e\n$st");
      rethrow;
    }
  }

  Future<void> signOut() async {
  /*  void s(String msg, {Color color = Colors.blueGrey}) =>
        _snack(context, msg, color: color);*/

    try {
     // s("Signing out…", color: Colors.orange);

      await Future.wait([
        FCMTokenManager().deleteTokenOnLogout().catchError((e) {
         // debugPrint("[FCM] deleteTokenOnLogout error: $e");
        }),
        _auth.signOut().catchError((e) {
         // debugPrint("[AUTH] signOut error: $e");
        }),
        _googleSignIn.signOut().catchError((e) {
        //  debugPrint("[GSI] signOut error: $e");
        }),
      ]);

     // s("Signed out ✅", color: const Color.fromARGB(255, 71, 114, 2));
    } catch (e) {
     // s("Sign out error: $e", color: Colors.redAccent);
     // debugPrint("[SIGNOUT] error: $e\n$st");
      await _auth.signOut().catchError((_) {});
    }
  }

  static User? getCurrentUser() => _auth.currentUser;
}
