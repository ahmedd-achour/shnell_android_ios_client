import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shnell/model/users.dart';

class AuthMethods {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Get Current User
  User? getCurrentUser() {
    return _auth.currentUser;
  }

  // Sign Up with Email and Password
  Future<String?> signUp({
    required String email,
    required String password,
    required String name,
    required String phone,
  }) async {
    try {
      // Validate inputs
      if (phone.isNotEmpty && !RegExp(r'^\+?[0-9]{7,15}$').hasMatch(phone) && phone.length != 8) {
        return 'Invalid phone number format';
      }

      // Check if email already exists in Firestore
      final existingEmail = await _firestore.collection('users').where('email', isEqualTo: email).get();
      if (existingEmail.docs.isNotEmpty) {
        return 'Email already registered';
      }

      // Create user with email and password
      final userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (userCredential.user != null) {
        // Save user data to Firestore
        final user = shnellUsers(
          email: email,
          name: name,
          phone: phone.isEmpty ? '' : phone,
          role: 'user',
        );
        await _firestore.collection('users').doc(userCredential.user!.uid).set(user.toJson());
        debugPrint('User signed up and saved to Firestore: ${userCredential.user!.uid}');
        return 'success';
      } else {
        return 'Failed to create user';
      }
    } on FirebaseAuthException catch (e) {
      debugPrint('Sign Up Error: ${e.message}');
      return _mapAuthError(e.code);
    } catch (e) {
      debugPrint('Sign Up General Error: $e');
      return 'An unexpected error occurred: $e';
    }
  }

  // Sign In with Email and Password
  Future<String?> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    try {
      // Sign in with email and password
      final userCredential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      if (userCredential.user != null) {
        debugPrint('Sign-in successful for user: ${userCredential.user!.uid}');
        return 'success';
      } else {
        return 'Failed to sign in';
      }
    } on FirebaseAuthException catch (e) {
      debugPrint('Sign In Error: ${e.message}');
      return _mapAuthError(e.code);
    } catch (e) {
      debugPrint('Sign In General Error: $e');
      return 'An unexpected error occurred: $e';
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

  // Get User Data
  Future<shnellUsers?> getUserData(String userId) async {
    try {
      final doc = await _firestore.collection('users').doc(userId).get();
      if (doc.exists) {
        return shnellUsers.fromJson(doc.data() as Map<String, dynamic>);
      } else {
        debugPrint('User not found in Firestore: $userId');
        return null;
      }
    } catch (e) {
      debugPrint('Error fetching user data: $e');
      return null;
    }
  }

  // Map Firebase Auth Errors to User-Friendly Messages
  String _mapAuthError(String code) {
    switch (code) {
      case 'email-already-in-use':
        return 'This email is already registered';
      case 'invalid-email':
        return 'Invalid email format';
      case 'weak-password':
        return 'Password is too weak (minimum 6 characters)';
      case 'user-not-found':
        return 'No user found with this email';
      case 'wrong-password':
        return 'Incorrect password';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later';
      case 'network-request-failed':
        return 'Network error. Please check your connection';
      case 'user-disabled':
        return 'This user account has been disabled';
      default:
        return 'Authentication error: $code';
    }
  }
}