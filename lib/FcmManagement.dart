import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

class FCMTokenManager {
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  void initialize() {
    // 1. Mise à jour au changement de user (Login/Logout)
    _auth.authStateChanges().listen((User? user) {
      if (user != null) {
        _updateTokenForUser(user);
      }
    });

    // 2. Mise à jour si Google rafraîchit le token
    _fcm.onTokenRefresh.listen((newToken) {
      final currentUser = _auth.currentUser;
      if (currentUser != null) {
        _saveTokenToFirestore(currentUser.uid, newToken);
      }
    });
  }

  Future<void> _updateTokenForUser(User user) async {
    try {
      String? token = await _fcm.getToken();
      if (token != null) {
        await _saveTokenToFirestore(user.uid, token);
      }
    } catch (e) {
      debugPrint("❌ Erreur récupération FCM Token: $e");
    }
  }

  /// Sauvegarde respectueuse du modèle shnellUsers
  Future<void> _saveTokenToFirestore(String userId, String token) async {
    try {
      // UTILISATION DE SetOptions(merge: true)
      // C'est crucial : cela met à jour le champ 'fcmToken' sans toucher 
      // au 'balance', 'role', 'vehicleType', etc.
      
      final Map<String, dynamic> updateData = {
        'fcmToken': token, // Correspond exactement à votre modèle shnellUsers
        
      };

      await _firestore.collection('users').doc(userId).set(
        updateData, 
        SetOptions(merge: true) // <-- La protection des données existantes est ici
      );
      
      debugPrint("✅ FCM Token synchronisé pour $userId");
    } catch (e) {
      debugPrint("❌ Erreur sauvegarde Firestore: $e");
    }
  }
  
  /// Nettoyage lors de la déconnexion
  Future<void> deleteTokenOnLogout() async {
    final user = _auth.currentUser;
    if (user != null) {
      // On met le champ à null, ce qui est autorisé car votre modèle a "String? fcmToken"
      await _firestore.collection('users').doc(user.uid).update({
        'fcmToken': null, 
      });
    }
  }
}