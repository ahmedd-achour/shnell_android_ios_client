import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shnell/model/users.dart';

class AuthMethods {
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Get Current User
  User? getCurrentUser() {
    return _auth.currentUser;
  }

  void _requestPermissions() {
    Permission.location.request();
    Permission.audio.request();
  }

  // --- SIGN UP (STRICT FLOW) ---
  // 1. Create User
  // 2. Write to Firestore immediately
  // 3. Send Verification Email
  Future<String?> signUp({
    required String email,
    required String password,
    required String name,
    required String phone,
  }) async {
    try {
      // Validate inputs
      if (phone.isNotEmpty && !RegExp(r'^\+?[0-9]{7,15}$').hasMatch(phone) && phone.length != 8) {
        return 'Format de téléphone invalide';
      }

      // Create user with email and password
      final userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      User? user = userCredential.user;

      if (user != null) {
        // Update Display Name
        await user.updateDisplayName(name);

        // Save user data to Firestore IMMEDIATELY
        final shnellUser = shnellUsers(
          email: email,
          name: name,
          phone: phone.isEmpty ? '' : phone,
          role: 'user',
          isActive: true, // Active, but needs verification to login
          darkMode: false,
        );

        // Using set(..., SetOptions(merge: true)) is safer
        await _firestore.collection('users').doc(user.uid).set(
              shnellUser.toJson(),
              SetOptions(merge: true),
            );
        
        // CRITICAL: Send Verification Email
        await user.sendEmailVerification();

        debugPrint('User signed up, saved, and verification sent: ${user.uid}');
        return 'success'; 
      } else {
        return 'Échec de la création de l\'utilisateur';
      }
    } on FirebaseAuthException catch (e) {
      debugPrint('Sign Up Error: ${e.message}');
      return _mapAuthError(e.code);
    } catch (e) {
      debugPrint('Sign Up General Error: $e');
      return 'Une erreur inattendue est survenue: $e';
    }
  }

  // --- SIGN IN (STRICT FLOW) ---
  // 1. Check Credentials
  // 2. Check Email Verification
  Future<String?> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    try {
      // Attempt Sign In
      final userCredential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      User? user = userCredential.user;

      if (user != null) {
        // CRITICAL: Check Verification Status
        if (!user.emailVerified) {
          // If not verified, we DO NOT request permissions or proceed.
          // We sign them out immediately to prevent access.
          await _auth.signOut();
          return 'email-not-verified'; // Special code for UI to handle
        }

        // Success Path
        debugPrint('Sign-in successful for verified user: ${user.uid}');
        _requestPermissions();
        return 'success';
      } else {
        return 'Échec de la connexion';
      }
    } on FirebaseAuthException catch (e) {
      debugPrint('Sign In Error: ${e.message}');
      return _mapAuthError(e.code);
    } catch (e) {
      debugPrint('Sign In General Error: $e');
      return 'Une erreur inattendue est survenue: $e';
    }
  }

  // Logout
  Future<void> logout() async {
    try {
      await _auth.signOut();
      debugPrint('User logged out successfully');
    } catch (e) {
      debugPrint('Error logging out: $e');
      rethrow;
    }
  }

  // Resend Verification Email (Helper)
  Future<String?> resendVerificationEmail() async {
    try {
      final user = _auth.currentUser;
      if (user != null && !user.emailVerified) {
        await user.sendEmailVerification();
        return 'success';
      }
      return 'User not found or already verified';
    } catch (e) {
      return e.toString();
    }
  }

  // Get User Data
  Future<shnellUsers?> getUserData(String userId) async {
    try {
      final doc = await _firestore.collection('users').doc(userId).get();
      if (doc.exists) {
        // Ensure your ShnellUser.fromJson handles the parsing correctly
        return shnellUsers.fromJson(doc.data() as Map<String, dynamic> );
      } else {
        debugPrint('User not found in Firestore: $userId');
        return null;
      }
    } catch (e) {
      debugPrint('Error fetching user data: $e');
      return null;
    }
  }

  // Map Firebase Auth Errors to French Messages
  String _mapAuthError(String code) {
    switch (code) {
      case 'email-already-in-use':
        return 'Cet email est déjà enregistré';
      case 'invalid-email':
        return 'Format d\'email invalide';
      case 'weak-password':
        return 'Le mot de passe est trop faible (min 6 caractères)';
      case 'user-not-found':
        return 'Aucun utilisateur trouvé avec cet email';
      case 'wrong-password':
        return 'Mot de passe incorrect';
      case 'too-many-requests':
        return 'Trop de tentatives. Veuillez réessayer plus tard';
      case 'network-request-failed':
        return 'Erreur réseau. Vérifiez votre connexion';
      case 'user-disabled':
        return 'Ce compte utilisateur a été désactivé';
      case 'credential-already-in-use':
        return 'Ces identifiants sont déjà associés à un autre compte';
      default:
        return 'Erreur d\'authentification: $code';
    }
  }

  // -------------------------------
  // 🔐 OTP HANDLING (Unchanged)
  // -------------------------------
  static final Map<String, _OtpData> _pendingOtps = {};

  static Future<void> updateEmailWithOtp(String newEmail) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception("User not logged in");
    final otp = _generateOtp();
    _pendingOtps[uid] = _OtpData(
      otp: otp,
      expiry: DateTime.now().add(const Duration(seconds: 90)),
      field: "email",
      newValue: newEmail,
    );
    print("DEBUG OTP for email update: $otp");
  }

  static Future<void> verifyOtpAndApply(String otp) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception("User not logged in");
    final data = _pendingOtps[uid];
    if (data == null) throw Exception("No pending OTP request");
    if (DateTime.now().isAfter(data.expiry)) {
      _pendingOtps.remove(uid);
      throw Exception("OTP expired");
    }
    if (otp != data.otp) throw Exception("Invalid OTP");
    if (data.field == "email") {
      await _auth.currentUser?.verifyBeforeUpdateEmail(data.newValue);
      await _firestore.collection("users").doc(uid).update({"email": data.newValue});
    }
    _pendingOtps.remove(uid);
  }

  static Future<void> updatePhoneWithOtp(String newPhone) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception("User not logged in");
    final otp = _generateOtp();
    _pendingOtps[uid] = _OtpData(
      otp: otp,
      expiry: DateTime.now().add(const Duration(seconds: 90)),
      field: "phone",
      newValue: newPhone,
    );
    print("DEBUG OTP for phone update: $otp");
  }

  static String _generateOtp() {
    final random = Random();
    return (100000 + random.nextInt(900000)).toString();
  }
}

class _OtpData {
  final String otp;
  final DateTime expiry;
  final String field; 
  final String newValue;

  _OtpData({
    required this.otp,
    required this.expiry,
    required this.field,
    required this.newValue,
  });
}