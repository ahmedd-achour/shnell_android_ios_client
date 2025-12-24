import 'dart:async';
import 'dart:ui'; // Pour l'effet de flou (Glassmorphism)
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shnell/model/users.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'dart:math' as math;
import 'package:intl_phone_field/intl_phone_field.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> with TickerProviderStateMixin {
  // --- CLÉS & OUTILS ---
  final _formKey = GlobalKey<FormState>();
  final PageController _pageController = PageController();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // --- CONTROLLERS ---
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  String _completePhoneNumber = "";

  // --- ÉTATS ---
  bool _isLoading = false;
  bool _isPasswordVisible = false;
  bool _isConfirmVisible = false;

  // --- ANIMATIONS ---
  late AnimationController _bgAnimController;
  late AnimationController _fadeAnimController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    // Animations
    _bgAnimController = AnimationController(vsync: this, duration: const Duration(seconds: 10))..repeat(reverse: true);
    _fadeAnimController = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _fadeAnimation = CurvedAnimation(parent: _fadeAnimController, curve: Curves.easeOut);
    _fadeAnimController.forward();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _pageController.dispose();
    _bgAnimController.dispose();
    _fadeAnimController.dispose();
    super.dispose();
  }

  // ===========================================================================
  // CRÉATION DU COMPTE + ENVOI VÉRIFICATION EMAIL FIREBASE
  // ===========================================================================

  Future<void> _createAccount() async {
    final loc = AppLocalizations.of(context)!;

    if (!_formKey.currentState!.validate()) return;
    if (_completePhoneNumber.length < 8) {
      _showError(loc.invalidPhone);
      return;
    }
    if (_passwordController.text != _confirmPasswordController.text) {
      _showError("Les mots de passe ne correspondent pas");
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 1. Création du compte Firebase
      final userCredential = await _auth.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      final user = userCredential.user;
      if (user == null) throw Exception("Erreur lors de la création du compte");

      // 2. Envoi de l'email de vérification (automatique via Firebase)
      await user.sendEmailVerification();

      // 3. Mise à jour du nom d'affichage
      await user.updateDisplayName(_nameController.text.trim());

      // 4. Sauvegarde dans Firestore
      final newUser = shnellUsers(
        email: _emailController.text.trim(),
        name: _nameController.text.trim(),
        phone: _completePhoneNumber,
        role: 'user',
        balance: 0.0,
        isActive: true,
        darkMode: false,
        vehicleType: null,
        vehicleId: null,
        matVehicle: null,
        fcmToken: null,
      );

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set(newUser.toJson());

      // 5. Message de succès
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Compte créé ! Vérifiez votre email pour activer votre compte (vérifiez aussi le dossier spam)."),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 6),
          ),
        );

        // Optionnel : Rediriger vers un écran "Vérifiez votre email"
        Navigator.of(context).pop();
      }
    } on FirebaseAuthException catch (e) {
      String errorMsg = e.message ?? "Erreur Firebase";
      if (e.code == 'email-already-in-use') {
        errorMsg = "Cet email est déjà utilisé";
      } else if (e.code == 'weak-password') {
        errorMsg = "Mot de passe trop faible (minimum 6 caractères)";
      }
      _showError(errorMsg);
    } catch (e) {
      _showError("Erreur : $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ===========================================================================
  // INTERFACE UTILISATEUR (UI simplifiée : une seule page)
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;

    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // Fond animé
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _bgAnimController,
              builder: (ctx, child) => CustomPaint(
                painter: _BackgroundPainter(color: theme.colorScheme.primary, animationValue: _bgAnimController.value),
              ),
            ),
          ),

          // Contenu
          SafeArea(
            child: Column(
              children: [
                _buildHeader(loc),
                Expanded(
                  child: FadeTransition(
                    opacity: _fadeAnimation,
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 15, spreadRadius: 5)],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(24),
                            child: Form(
                              key: _formKey,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text("Bienvenue !", style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 5),
                                  Text("Créez votre compte en quelques étapes.", style: TextStyle(color: theme.colorScheme.outline)),
                                  const SizedBox(height: 30),

                                  // Nom
                                  _buildInput(_nameController, loc.fullNameLabel, Icons.person_outline, theme, loc),
                                  const SizedBox(height: 15),

                                  // Email
                                  _buildInput(_emailController, loc.emailLabel, Icons.email_outlined, theme, loc, type: TextInputType.emailAddress),
                                  const SizedBox(height: 15),

                                  // Téléphone
                                  IntlPhoneField(
                                    decoration: InputDecoration(
                                      labelText: loc.mobilePhoneLabel,
                                      filled: true,
                                      fillColor: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                                      counterText: "",
                                    ),
                                    initialCountryCode: 'TN',
                                    onChanged: (phone) => _completePhoneNumber = phone.completeNumber,
                                    languageCode: Localizations.localeOf(context).languageCode,
                                  ),
                                  const SizedBox(height: 15),

                                  // Mot de passe
                                  _buildPasswordInput(_passwordController, loc.createPasswordLabel, theme, loc, _isPasswordVisible, () => setState(() => _isPasswordVisible = !_isPasswordVisible)),
                                  const SizedBox(height: 15),

                                  // Confirmation mot de passe
                                  _buildPasswordInput(_confirmPasswordController, loc.confirmPasswordLabel, theme, loc, _isConfirmVisible, () => setState(() => _isConfirmVisible = !_isConfirmVisible)),
                                  const SizedBox(height: 40),

                                  // Bouton Créer
                                  FilledButton(
                                    onPressed: _isLoading ? null : _createAccount,
                                    style: FilledButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(vertical: 16),
                                      backgroundColor: theme.colorScheme.primary,
                                    ),
                                    child: _isLoading
                                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                        : Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [Text("Créer mon compte"), const SizedBox(width: 8), const Icon(Icons.arrow_forward)],
                                          ),
                                  ),

                                  const SizedBox(height: 20),
                                  Text("En cliquant sur 'Créer mon compte', vous acceptez nos conditions d'utilisation.", style: TextStyle(fontSize: 12, color: Colors.grey), textAlign: TextAlign.center),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(AppLocalizations loc) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: Colors.white24,
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(loc.newAccountTitle, style: GoogleFonts.montserrat(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
              const Text("Étape unique : Inscription", style: TextStyle(color: Colors.white70)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInput(TextEditingController ctrl, String label, IconData icon, ThemeData theme, AppLocalizations loc, {TextInputType type = TextInputType.text}) {
    return TextFormField(
      controller: ctrl,
      keyboardType: type,
      validator: (v) {
        if (v == null || v.isEmpty) return loc.fieldRequired;
        if (type == TextInputType.emailAddress && !v.contains('@')) return 'Email invalide';
        return null;
      },
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: theme.colorScheme.primary),
        filled: true,
        fillColor: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      ),
    );
  }

  Widget _buildPasswordInput(TextEditingController ctrl, String label, ThemeData theme, AppLocalizations loc, bool visible, VoidCallback toggle) {
    return TextFormField(
      controller: ctrl,
      obscureText: !visible,
      validator: (v) => (v == null || v.length < 6) ? loc.passwordError : null,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(Icons.lock_outline, color: theme.colorScheme.primary),
        suffixIcon: IconButton(icon: Icon(visible ? Icons.visibility : Icons.visibility_off), onPressed: toggle),
        filled: true,
        fillColor: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      ),
    );
  }
}

class _BackgroundPainter extends CustomPainter {
  final Color color;
  final double animationValue;
  _BackgroundPainter({required this.color, required this.animationValue});
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
    final wavePaint = Paint()..color = Colors.white.withOpacity(0.1);
    final pathWave = Path();
    double y = size.height * 0.15;
    pathWave.moveTo(0, y);
    for (double x = 0; x <= size.width; x++) {
      pathWave.lineTo(x, y + 20 * math.sin((x / size.width * 2 * math.pi) + (animationValue * 2 * math.pi)));
    }
    pathWave.lineTo(size.width, 0);
    pathWave.lineTo(0, 0);
    pathWave.close();
    canvas.drawPath(pathWave, wavePaint);
  }
  @override
  bool shouldRepaint(covariant _BackgroundPainter oldDelegate) => oldDelegate.animationValue != animationValue;
}