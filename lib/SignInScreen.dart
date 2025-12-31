import 'dart:async';
import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl_phone_number_input/intl_phone_number_input.dart';

import 'package:shnell/Account/privacyPolicy.dart';
import 'package:shnell/model/users.dart';
import 'package:shnell/passwordReset.dart';

class UnifiedAuthScreen extends StatefulWidget {
  const UnifiedAuthScreen({super.key});

  @override
  State<UnifiedAuthScreen> createState() => _UnifiedAuthScreenState();
}

class _UnifiedAuthScreenState extends State<UnifiedAuthScreen>
    with SingleTickerProviderStateMixin {
  bool _isSignUp = false;
  bool _isLoading = false;

  final TextEditingController nameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  PhoneNumber tunisiaPhone = PhoneNumber(isoCode: 'TN');

  // === SIGN UP ===
  Future<void> _handleSignUp() async {
    HapticFeedback.lightImpact();
    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);

    final email = emailController.text.trim();
    final password = passwordController.text.trim();
    final name = nameController.text.trim();
    final phoneLocal = phoneController.text.trim().replaceAll(' ', '');

    if (!_validatePhone(phoneLocal)) {
      setState(() => _isLoading = false);
      return;
    }

    if (password.length < 7) {
      _showError("Le mot de passe doit contenir au moins 7 caractères.");
      setState(() => _isLoading = false);
      return;
    }

    final phoneFull = '+216$phoneLocal';

    try {
      UserCredential credential =
          await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      User? user = credential.user;

      if (user != null) {
        final shnellUser = shnellUsers(
          email: email,
          name: name,
          phone: phoneFull,
          role: 'user',
          darkMode: true,
        );

        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .set(shnellUser.toJson());

        await user.sendEmailVerification();

        _showSuccess("Compte créé ! Vérifiez votre email pour continuer.");
        
        // NO NAVIGATION HERE
        // Global wrapper will redirect to EmailVerificationScreen
      }
    } on FirebaseAuthException catch (e) {
      _showError(_parseFirebaseError(e));
    } catch (e) {
      _showError("Erreur lors de la création du compte.");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // === LOGIN ===
  Future<void> _handleLogin() async {
    HapticFeedback.lightImpact();
    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );

      _showSuccess("Connexion réussie !");

      // NO MANUAL NAVIGATION
      // The main app wrapper will handle routing based on:
      // - emailVerified
      // - Firestore document existence
      // - role == 'user'

    } on FirebaseAuthException catch (e) {
      _showError(_parseFirebaseError(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  bool _validatePhone(String phone) {
    if (!RegExp(r'^[2-9][0-9]{7}$').hasMatch(phone)) {
      _showError("Numéro invalide (8 chiffres, commençant par 2-9).");
      return false;
    }
    return true;
  }

  String _parseFirebaseError(FirebaseAuthException e) {
    switch (e.code) {
      case 'email-already-in-use':
        return "Cet email est déjà utilisé.";
      case 'weak-password':
        return "Mot de passe trop faible.";
      case 'user-not-found':
        return "Aucun compte trouvé avec cet email.";
      case 'wrong-password':
        return "Mot de passe incorrect.";
      case 'invalid-credential':
        return "Identifiants invalides.";
      case 'too-many-requests':
        return "Trop de tentatives. Réessayez plus tard.";
      default:
        return "Erreur : ${e.message}";
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(child: Text(msg)),
          ],
        ),
        backgroundColor: Colors.red.shade800,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _showSuccess(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(child: Text(msg)),
          ],
        ),
        backgroundColor: Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final size = MediaQuery.of(context).size;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        body: Stack(
          children: [
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      cs.primaryContainer.withOpacity(0.3),
                      cs.surface,
                      cs.surface
                    ],
                  ),
                ),
              ),
            ),
            SafeArea(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: size.width * 0.06),
                child: Column(
                  children: [
                    SizedBox(height: size.height * 0.02),
                    Hero(
                      tag: 'app_logo',
                      child: Material(
                        color: Colors.transparent,
                        child: Column(
                          children: [
                            Text(
                              "SHNELL",
                              style: GoogleFonts.montserrat(
                                fontSize: 48,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 4,
                                color: cs.primary,
                              ),
                            ),
                            Text(
                              "L'excellence en mouvement",
                              style: GoogleFonts.inter(
                                color: cs.onSurfaceVariant,
                                fontSize: 16,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: size.height * 0.05),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(30),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                        child: Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: cs.surface.withOpacity(0.7),
                            borderRadius: BorderRadius.circular(30),
                            border:
                                Border.all(color: cs.outlineVariant.withOpacity(0.3)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.05),
                                blurRadius: 20,
                                spreadRadius: 5,
                              )
                            ],
                          ),
                          child: AnimatedSize(
                            duration: const Duration(milliseconds: 400),
                            curve: Curves.easeInOutBack,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: _AuthTabButton(
                                        title: "Connexion",
                                        isActive: !_isSignUp,
                                        onTap: () => setState(() => _isSignUp = false),
                                      ),
                                    ),
                                    Expanded(
                                      child: _AuthTabButton(
                                        title: "Inscription",
                                        isActive: _isSignUp,
                                        onTap: () => setState(() => _isSignUp = true),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 30),
                                AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 300),
                                  transitionBuilder: (child, animation) =>
                                      FadeTransition(
                                    opacity: animation,
                                    child: SlideTransition(
                                      position: Tween<Offset>(
                                              begin: const Offset(0, 0.05),
                                              end: Offset.zero)
                                          .animate(animation),
                                      child: child,
                                    ),
                                  ),
                                  child: Column(
                                    key: ValueKey<bool>(_isSignUp),
                                    children: [
                                      if (_isSignUp) ...[
                                        _CustomTextField(
                                          controller: nameController,
                                          label: "Nom complet",
                                          icon: Icons.person_outline_rounded,
                                          inputAction: TextInputAction.next,
                                        ),
                                        const SizedBox(height: 16),
                                      ],
                                      _CustomTextField(
                                        controller: emailController,
                                        label: "Email",
                                        icon: Icons.alternate_email_rounded,
                                        inputType: TextInputType.emailAddress,
                                        inputAction: TextInputAction.next,
                                      ),
                                      const SizedBox(height: 16),
                                      if (_isSignUp) ...[
                                        Container(
                                          decoration: BoxDecoration(
                                            color: cs.surfaceVariant.withOpacity(0.3),
                                            borderRadius: BorderRadius.circular(16),
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 4),
                                          child: InternationalPhoneNumberInput(
                                            onInputChanged: (_) {},
                                            selectorConfig: const SelectorConfig(
                                              selectorType:
                                                  PhoneInputSelectorType.BOTTOM_SHEET,
                                              showFlags: true,
                                              useEmoji: true,
                                              trailingSpace: false,
                                            ),
                                            initialValue: tunisiaPhone,
                                            textFieldController: phoneController,
                                            formatInput: false,
                                            cursorColor: cs.primary,
                                            countries: const ['TN'],
                                            inputDecoration: const InputDecoration(
                                              hintText: "29 123 456",
                                              border: InputBorder.none,
                                              contentPadding:
                                                  EdgeInsets.only(bottom: 12),
                                            ),
                                            textStyle: GoogleFonts.inter(
                                                fontSize: 16, color: cs.onSurface),
                                          ),
                                        ),
                                        const SizedBox(height: 16),
                                      ],
                                      _CustomTextField(
                                        controller: passwordController,
                                        label: "Mot de passe",
                                        icon: Icons.lock_outline_rounded,
                                        isPassword: true,
                                        inputAction: TextInputAction.done,
                                      ),
                                    ],
                                  ),
                                ),
                                if (!_isSignUp)
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton(
                                      onPressed: () => Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                              builder: (_) =>
                                                  const PasswordResetScreen())),
                                      child: Text("Mot de passe oublié ?",
                                          style: TextStyle(
                                              color: cs.primary,
                                              fontWeight: FontWeight.w600)),
                                    ),
                                  ),
                                if (_isSignUp) ...[
                                  const SizedBox(height: 16),
                                  GestureDetector(
                                    onTap: () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                            builder: (_) =>
                                                const PrivacyPolicyScreen())),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.check_circle_outline,
                                            size: 16, color: cs.primary),
                                        const SizedBox(width: 8),
                                        Text.rich(
                                          TextSpan(
                                            text: "J'accepte la ",
                                            style: TextStyle(
                                                fontSize: 12,
                                                color: cs.onSurfaceVariant),
                                            children: [
                                              TextSpan(
                                                text: "politique de confidentialité",
                                                style: TextStyle(
                                                    color: cs.primary,
                                                    fontWeight: FontWeight.bold,
                                                    decoration:
                                                        TextDecoration.underline),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 24),
                                SizedBox(
                                  width: double.infinity,
                                  height: 56,
                                  child: FilledButton(
                                    onPressed: _isLoading
                                        ? null
                                        : () => _isSignUp
                                            ? _handleSignUp()
                                            : _handleLogin(),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: cs.primary,
                                      foregroundColor: cs.onPrimary,
                                      shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(16)),
                                      elevation: 2,
                                    ),
                                    child: _isLoading
                                        ? SizedBox(
                                            height: 24,
                                            width: 24,
                                            child: CircularProgressIndicator(
                                                color: cs.onPrimary,
                                                strokeWidth: 2.5))
                                        : Text(
                                            _isSignUp
                                                ? "Créer un compte"
                                                : "Se connecter",
                                            style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold),
                                          ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: size.height * 0.05),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool isPassword;
  final TextInputType? inputType;
  final TextInputAction? inputAction;

  const _CustomTextField({
    required this.controller,
    required this.label,
    required this.icon,
    this.isPassword = false,
    this.inputType,
    this.inputAction,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return TextField(
      controller: controller,
      obscureText: isPassword,
      keyboardType: inputType,
      textInputAction: inputAction,
      style: GoogleFonts.inter(fontSize: 16),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: cs.onSurfaceVariant),
        prefixIcon: Icon(icon, color: cs.primary.withOpacity(0.7), size: 22),
        filled: true,
        fillColor: cs.surfaceVariant.withOpacity(0.3),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: cs.primary, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
      ),
    );
  }
}

class _AuthTabButton extends StatelessWidget {
  final String title;
  final bool isActive;
  final VoidCallback onTap;

  const _AuthTabButton(
      {required this.title, required this.isActive, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isActive ? cs.primary : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
            color: isActive ? cs.primary : cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}