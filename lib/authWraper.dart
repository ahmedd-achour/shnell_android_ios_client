import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shnell/SignInScreen.dart';
import 'package:shnell/dots.dart';
import 'package:shnell/mainUsers.dart';

class AuthWrapper extends StatelessWidget {
  final AsyncSnapshot<User?> authSnapshot;

  const AuthWrapper({Key? key, required this.authSnapshot}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Still waiting for auth state
    if (authSnapshot.connectionState == ConnectionState.waiting) {
      return const Scaffold(body: Center(child: RotatingDotsIndicator()));
    }

    final user = authSnapshot.data;

    // Not logged in → Sign In
    if (user == null) {
      return const SignInScreen();
    }

    // Logged in → Load user profile to get role, theme, language
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots(),
      builder: (context, userSnapshot) {
        // Loading user data
        if (userSnapshot.connectionState == ConnectionState.waiting ||
            !userSnapshot.hasData ||
            !userSnapshot.data!.exists) {
          return const Scaffold(body: Center(child: RotatingDotsIndicator()));
        }

        final data = userSnapshot.data!.data() as Map<String, dynamic>;
        //final bool darkMode = data['darkMode'] ?? false;
        final String role = data['role'] ?? 'user';

        // Update locale and theme dynamically
        WidgetsBinding.instance.addPostFrameCallback((_) {
         // context.setLocale(Locale(languageCode));
          // If using Provider or similar for theme, update it here
          // Otherwise, we rely on rebuilding MaterialApp with correct themeMode
        });

        // Final routing
        if (role != 'user') {
          return const SignInScreen(); // Or a blocked screen
        }

        return const MainUsersScreen();
      },
    );
  }
}