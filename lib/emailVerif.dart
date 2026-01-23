

// --- SCREEN: EMAIL VERIFICATION ---
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shnell/SignInScreen.dart';
import 'package:shnell/dots.dart';
import 'package:shnell/mainUsers.dart';

class EmailVerificationScreen extends StatefulWidget {
  const EmailVerificationScreen({super.key});

  @override
  State<EmailVerificationScreen> createState() => _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  Timer? _timer;
  bool _canResend = false;
  int _countdown = 60;

  @override
  void initState() {
    super.initState();
    _startTimer();
    _startPolling();
  }

  void _startTimer() {
    setState(() => _canResend = false);
    Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          if (_countdown > 0) {
            _countdown--;
          } else {
            _canResend = true;
            timer.cancel();
          }
        });
      }
    });
  }

  void _startPolling() {
    _timer = Timer.periodic(const Duration(seconds: 3), (_) async {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await user.reload(); 
        if (user.emailVerified) {
          _timer?.cancel();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Email vérifié avec succès !"), backgroundColor: Colors.green),
            );
            Navigator.of(context).pushAndRemoveUntil(
  MaterialPageRoute(builder: (context) => const MainUsersScreen()),
  (Route<dynamic> route) => false,  // Never keep any old route
);
            // MODIFICATION : Navigation propre vers l'accueil (vide la stack)
            // Ou utilisez: Navigator.of(context).pushAndRemoveUntil(...) vers Home
          }
        }
      }
    });
  }

  Future<void> _resendEmail() async {
    try {
      await FirebaseAuth.instance.currentUser?.sendEmailVerification();
      setState(() => _countdown = 60);
      _startTimer();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Email renvoyé !")));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Erreur d'envoi.")));
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // MODIFICATION 2: PopScope pour empêcher le retour arrière
    return PopScope(
      canPop: false, // Empêche le retour système
      onPopInvoked: (didPop) async {
        if (didPop) return;
        // Si l'utilisateur tente de sortir, on le déconnecte proprement
        await FirebaseAuth.instance.signOut();
        if (context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0, automaticallyImplyLeading: false),
        body: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: cs.primaryContainer.withOpacity(0.3), shape: BoxShape.circle),
                child: Icon(Icons.mark_email_unread_outlined, size: 64, color: cs.primary),
              ),
              const SizedBox(height: 32),
              Text(
                "Vérification Requise",
                style: GoogleFonts.montserrat(fontSize: 24, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                "Veuillez vérifier votre email pour accéder à l'application.\nUn lien a été envoyé à :",
                style: TextStyle(fontSize: 16, color: cs.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                "${FirebaseAuth.instance.currentUser?.email}",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: cs.onSurface),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),
              if(FirebaseAuth.instance.currentUser?.emailVerified == false)
              const RotatingDotsIndicator(),
              if(FirebaseAuth.instance.currentUser?.emailVerified == false)

              const SizedBox(height: 16),
FirebaseAuth.instance.currentUser?.emailVerified == true
    ? SizedBox(
  width: double.infinity,
  child: ElevatedButton(
    style: ButtonStyle(
      padding: MaterialStateProperty.all(
          const EdgeInsets.symmetric(vertical: 16.0)),
      shape: MaterialStateProperty.all(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(30.0),
        ),
      ),
      backgroundColor: MaterialStateProperty.resolveWith((states) {
        if (states.contains(MaterialState.pressed)) {
        }
        return null;
      }),
      elevation: MaterialStateProperty.all(8),
      shadowColor: MaterialStateProperty.all(Colors.black45),
    ),
    onPressed: () {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => MainUsersScreen()),
        (Route<dynamic> route) => false,
      );
    },
    child: const Text(
      "Commencer",
      style: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
      ),
    ),
  ),
)

    : Text("En attente de validation...", style: TextStyle(color: cs.primary)),


              const Spacer(),
              TextButton(
                onPressed: _canResend ? _resendEmail : null,
                child: Text(_canResend ? "Renvoyer l'email" : "Renvoyer dans $_countdown s"),
              ),
              TextButton(
                onPressed: () async {
                  await FirebaseAuth.instance.signOut(); 
                  Navigator.of(context).pushAndRemoveUntil(
  MaterialPageRoute(builder: (context) =>  UnifiedAuthScreen()),
  (Route<dynamic> route) => false,  // Never keep any old route
);      
                },
                child: const Text("Se déconnecter", style: TextStyle(color: Colors.red)),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}