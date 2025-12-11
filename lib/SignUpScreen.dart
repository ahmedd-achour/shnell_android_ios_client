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

// IMPORT DU PACKAGE OTP
import 'package:email_otp/email_otp.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _UserSignUpScreenState();
}

class _UserSignUpScreenState extends State<SignUpScreen> with TickerProviderStateMixin {
  // --- CLÉS & OUTILS ---
  final _formKeyStep1 = GlobalKey<FormState>();
  final _formKeyStep2 = GlobalKey<FormState>(); 
  final PageController _pageController = PageController();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // --- CONTROLLERS ---
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _otpController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  String _completePhoneNumber = "";

  // --- ÉTATS ---
  int _currentStep = 0;
  bool _isLoading = false;      
  bool _isSendingCode = false;  
  bool _isEmailVerified = false; 
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

    // --- CONFIGURATION OTP (STATIQUE) ---
    // On configure le package ici au démarrage de l'écran
    EmailOTP.config(
      appName: 'Shnell Logistics',
      otpType: OTPType.numeric,
      
      emailTheme: EmailTheme.v3, // v3 est souvent plus joli, ou v1 selon votre goût
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _otpController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _pageController.dispose();
    _bgAnimController.dispose();
    _fadeAnimController.dispose();
    super.dispose();
  }

  // ===========================================================================
  // ÉTAPE 1 : ENVOI DU CODE (Méthode Statique)
  // ===========================================================================

  Future<void> _sendOtpAndProceed() async {
    final loc = AppLocalizations.of(context)!;

    if (!_formKeyStep1.currentState!.validate()) return;
    
    if (_completePhoneNumber.length < 8) {
      _showError(loc.invalidPhone);
      return;
    }

    setState(() => _isSendingCode = true);

    try {
      // --- CHANGEMENT ICI : Appel Statique ---
      bool sent = await EmailOTP.sendOTP(email: _emailController.text.trim());
      
      setState(() => _isSendingCode = false);

      if (sent) {
        // SUCCÈS : On passe à l'étape suivante
        _pageController.animateToPage(1, duration: const Duration(milliseconds: 500), curve: Curves.easeInOutQuart);
        setState(() => _currentStep = 1);
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Code envoyé à ${_emailController.text}"), 
            backgroundColor: Colors.green
          )
        );
      } else {
        _showError("Échec de l'envoi. Vérifiez l'email.");
      }
    } catch (e) {
      setState(() => _isSendingCode = false);
      _showError("Erreur : $e");
    }
  }

  // ===========================================================================
  // ÉTAPE 2 : VÉRIFICATION OTP (Méthode Statique)
  // ===========================================================================

  void _verifyOtp() {
    final loc = AppLocalizations.of(context)!;
    
    if (_otpController.text.length < 4) return;

    setState(() => _isLoading = true);

    // --- CHANGEMENT ICI : Appel Statique ---
    // Note: Selon la version exacte, verifyOTP peut être synchrone ou asynchrone (Future).
    // Dans votre exemple, c'est direct, donc on tente comme ça :
    bool isValid = EmailOTP.verifyOTP(otp: _otpController.text);

    setState(() => _isLoading = false);

    if (isValid) {
      setState(() {
        _isEmailVerified = true; // DÉCLENCHE L'AFFICHAGE DU MOT DE PASSE
      });
      HapticFeedback.mediumImpact();
    } else {
      _showError(loc.wrongCode);
    }
  }

  // ===========================================================================
  // FINAL : CRÉATION DU COMPTE FIREBASE
  // ===========================================================================

  Future<void> _finalizeAccount() async {
    if (!_formKeyStep2.currentState!.validate()) return;
    if (_passwordController.text != _confirmPasswordController.text) {
      _showError("Les mots de passe ne correspondent pas");
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 1. CRÉATION AUTH (Connexion auto)
      final userCredential = await _auth.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      final user = userCredential.user;
      if (user == null) throw Exception("Erreur Auth");

      // 2. SAUVEGARDE FIRESTORE
      await user.updateDisplayName(_nameController.text.trim());

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

      // 3. FINI
      if (mounted) {
         Navigator.of(context).pop(); 
      }

    } on FirebaseAuthException catch (e) {
      _showError(e.message ?? "Erreur Firebase");
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg), backgroundColor: Colors.redAccent, behavior: SnackBarBehavior.floating
    ));
  }

  // ===========================================================================
  // INTERFACE UTILISATEUR (UI)
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    
    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // 1. FOND
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _bgAnimController,
              builder: (ctx, child) => CustomPaint(
                painter: _BackgroundPainter(color: theme.colorScheme.primary, animationValue: _bgAnimController.value),
              ),
            ),
          ),
          
          // 2. CONTENU
          SafeArea(
            child: Column(
              children: [
                _buildHeader(loc),
                
                Expanded(
                  child: FadeTransition(
                    opacity: _fadeAnimation,
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      // GLASSMORPHISM
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 15, spreadRadius: 5)],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                          child: PageView(
                            controller: _pageController,
                            physics: const NeverScrollableScrollPhysics(), // Pas de swipe
                            children: [
                              _buildStep1_Contact(theme, loc),
                              _buildStep2_VerifyAndPass(theme, loc),
                            ],
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

  // --- HEADER ---
  Widget _buildHeader(AppLocalizations loc) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: Colors.white24,
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () {
                if (_currentStep == 1) {
                  _pageController.animateToPage(0, duration: const Duration(milliseconds: 400), curve: Curves.easeInOut);
                  setState(() => _currentStep = 0);
                } else {
                  Navigator.pop(context);
                }
              },
            ),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(loc.newAccountTitle, style: GoogleFonts.montserrat(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
              Text(_currentStep == 0 ? "Étape 1 : Infos" : "Étape 2 : Sécurité", style: const TextStyle(color: Colors.white70)),
            ],
          ),
        ],
      ),
    );
  }

  // --- ÉCRAN 1 : INFOS ---
  Widget _buildStep1_Contact(ThemeData theme, AppLocalizations loc) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKeyStep1,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text("Bienvenue !", style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 5),
            Text("Entrez vos détails pour vérifier l'email.", style: TextStyle(color: theme.colorScheme.outline)),
            const SizedBox(height: 30),

            _buildInput(_nameController, loc.fullNameLabel, Icons.person_outline, theme, loc),
            const SizedBox(height: 15),
            _buildInput(_emailController, loc.emailLabel, Icons.email_outlined, theme, loc, type: TextInputType.emailAddress),
            const SizedBox(height: 15),
            
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
            
            const SizedBox(height: 40),
            
            FilledButton(
              onPressed: _isSendingCode ? null : _sendOtpAndProceed,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: theme.colorScheme.primary,
              ),
              child: _isSendingCode 
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [Text("Vérifier Email"), const SizedBox(width: 8), const Icon(Icons.arrow_forward)],
                  ),
            ),
          ],
        ),
      ),
    );
  }

  // --- ÉCRAN 2 : OTP + PASSWORD ---
  Widget _buildStep2_VerifyAndPass(ThemeData theme, AppLocalizations loc) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // INDICATEUR VISUEL
          Row(
            children: [
              Icon(_isEmailVerified ? Icons.check_circle : Icons.mark_email_unread, 
                   color: _isEmailVerified ? Colors.green : theme.colorScheme.primary, size: 30),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _isEmailVerified ? "Email Vérifié !" : "Code envoyé à ${_emailController.text}",
                  style: TextStyle(fontWeight: FontWeight.bold, color: _isEmailVerified ? Colors.green : theme.colorScheme.onSurface),
                ),
              )
            ],
          ),
          const SizedBox(height: 20),

          // ZONE OTP (Se désactive si vérifié)
          AnimatedOpacity(
            opacity: _isEmailVerified ? 0.5 : 1.0,
            duration: const Duration(milliseconds: 300),
            child: Column(
              children: [
                _buildInput(_otpController, loc.verificationCodeLabel, Icons.lock_clock, theme, loc, type: TextInputType.number, isOtp: true),
                if (!_isEmailVerified) ...[
                  const SizedBox(height: 15),
                  FilledButton.tonal(
                    onPressed: _isLoading ? null : _verifyOtp,
                    child: _isLoading 
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text("Valider Code"),
                  ),
                ]
              ],
            ),
          ),

          const Divider(height: 40),

          // ZONE MOT DE PASSE (Apparaît seulement après vérification)
          AnimatedSize(
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeInOutBack,
            child: _isEmailVerified 
              ? Form(
                  key: _formKeyStep2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text("Sécurisez votre compte", style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 15),
                      
                      _buildPasswordInput(_passwordController, loc.createPasswordLabel, theme, loc, _isPasswordVisible, () => setState(() => _isPasswordVisible = !_isPasswordVisible)),
                      const SizedBox(height: 15),
                      _buildPasswordInput(_confirmPasswordController, loc.confirmPasswordLabel, theme, loc, _isConfirmVisible, () => setState(() => _isConfirmVisible = !_isConfirmVisible)),
                      
                      const SizedBox(height: 30),
                      
                      FilledButton(
                        onPressed: _isLoading ? null : _finalizeAccount,
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.green, // Vert pour l'action finale
                          padding: const EdgeInsets.symmetric(vertical: 16)
                        ),
                        child: _isLoading 
                          ? const CircularProgressIndicator(color: Colors.white)
                          : Text("Créer compte & Se connecter", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      ),
                    ],
                  ),
                )
              : const Center(child: Text("Validez l'email pour définir le mot de passe", style: TextStyle(color: Colors.grey))),
          ),
        ],
      ),
    );
  }

  // --- WIDGETS INPUT ---
  Widget _buildInput(TextEditingController ctrl, String label, IconData icon, ThemeData theme, AppLocalizations loc, {TextInputType type = TextInputType.text, bool isOtp = false}) {
    return TextFormField(
      controller: ctrl,
      keyboardType: type,
      enabled: isOtp ? !_isEmailVerified : true,
      textAlign: isOtp ? TextAlign.center : TextAlign.start,
      style: TextStyle(fontWeight: FontWeight.w600, fontSize: isOtp ? 24 : 16, letterSpacing: isOtp ? 10 : 0),
      validator: (v) {
        if (v == null || v.isEmpty) return loc.fieldRequired;
        return null;
      },
      decoration: InputDecoration(
        labelText: isOtp ? null : label,
        hintText: isOtp ? "000000" : null,
        prefixIcon: isOtp ? null : Icon(icon, color: theme.colorScheme.primary),
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
      validator: (v) => (v!.length < 6) ? loc.passwordError : null,
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

// Painter (Fond animé)
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