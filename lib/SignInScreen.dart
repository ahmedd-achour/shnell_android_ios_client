import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:shnell/SignUpScreen.dart';
import 'package:shnell/passwordReset.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _UserSignInScreenState();
}

class _UserSignInScreenState extends State<SignInScreen> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  
  bool _isLoading = false;
  bool _isPasswordVisible = false;
  
  // Animations
  late AnimationController _animController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    
    _fadeAnimation = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    // Modified animation to come from bottom up smoothly
    _slideAnimation = Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero)
        .animate(CurvedAnimation(parent: _animController, curve: Curves.easeOutQuart));

    _animController.forward();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _animController.dispose();
    super.dispose();
  }

  // --- AUTH LOGIC (Unchanged) ---
  Future<void> _handleSignIn() async {
    final loc = AppLocalizations.of(context)!;
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    HapticFeedback.selectionClick();

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
    } on FirebaseAuthException catch (e) {
      _showError(_mapAuthErrorMessage(e.code, loc));
    } catch (e) {
      _showError(loc.connectionError);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _mapAuthErrorMessage(String code, AppLocalizations loc) {
    switch (code) {
      case 'user-not-found': return loc.userNotFound;
      case 'wrong-password': return loc.wrongPassword;
      case 'invalid-email': return loc.invalidEmail;
      case 'user-disabled': return loc.userDisabled;
      default: return loc.signInFailed;
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    final theme = Theme.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [Icon(Icons.error_outline, color: theme.colorScheme.onError), const SizedBox(width: 12), Expanded(child: Text(message))]),
        backgroundColor: theme.colorScheme.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // --- UI CONSTRUCTION ---

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final loc = AppLocalizations.of(context)!;

    return Scaffold(
      // IMPORTANT: This allows the UI to slide up when keyboard appears
      resizeToAvoidBottomInset: true, 
      backgroundColor: colorScheme.primary, 
      body: Stack(
        children: [
          // 1. Dynamic Background
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    colorScheme.primary,
                    Color.lerp(colorScheme.primary, colorScheme.surface, 0.2)!, 
                  ],
                ),
              ),
            ),
          ),
          
          // 2. Responsive Layout
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Determine if we need to scroll (keyboard open) or stretch (keyboard closed)
                return SingleChildScrollView(
                  // BouncingScrollPhysics gives a nice native feel
                  physics: const BouncingScrollPhysics(),
                  child: ConstrainedBox(
                    // CRITICAL FIX: Ensures the container is at least as tall as the screen
                    // but can grow (scroll) if the keyboard covers it.
                    constraints: BoxConstraints(
                      minWidth: constraints.maxWidth,
                      minHeight: constraints.maxHeight,
                    ),
                    child: IntrinsicHeight(
                      child: constraints.maxWidth > 600 
                        ? _buildTabletLayout(theme, loc)
                        : _buildMobileLayout(theme, loc),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // --- MOBILE LAYOUT (Refactored for Scrolling) ---
  Widget _buildMobileLayout(ThemeData theme, AppLocalizations loc) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisAlignment: MainAxisAlignment.spaceBetween, // Pushes content to edges
      children: [
        // TOP SECTION: Logo (Will scroll up when typing)
        Padding(
          padding: const EdgeInsets.only(top: 40, bottom: 20),
          child: _buildBrandHeader(theme, isDarkText: false, loc: loc),
        ),

        // BOTTOM SECTION: Form (Will stick to bottom, or slide up)
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(32),
              topRight: Radius.circular(32),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 20,
                offset: const Offset(0, -5),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.only(topLeft: Radius.circular(32), topRight: Radius.circular(32)),
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: SlideTransition(
                position: _slideAnimation,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                  child: _buildFormContent(theme, loc),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // --- TABLET LAYOUT ---
  Widget _buildTabletLayout(ThemeData theme, AppLocalizations loc) {
    return Center(
      child: Container(
        width: 450,
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 40)],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildBrandHeader(theme, isDarkText: true, loc: loc),
            const SizedBox(height: 40),
            _buildFormContent(theme, loc),
          ],
        ),
      ),
    );
  }

  // --- COMPONENTS ---

  Widget _buildBrandHeader(ThemeData theme, {required bool isDarkText, required AppLocalizations loc}) {
    final colorScheme = theme.colorScheme;
    final textColor = isDarkText ? colorScheme.onSurface : colorScheme.onPrimary;
    
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Hero( // Added Hero for smooth transition if you navigate elsewhere
          tag: 'app_logo',
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: CircleAvatar(
              radius: 40,
              backgroundColor: colorScheme.surface,
              backgroundImage: const AssetImage("assets/shnell.jpeg"),
              onBackgroundImageError: (_, __) {},
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          "SHNELL",
          style: GoogleFonts.montserrat(
            fontSize: 28, fontWeight: FontWeight.w900, color: textColor, letterSpacing: 3.0,
          ),
        ),
        Text(
          loc.slogan, 
          style: GoogleFonts.inter(
            fontSize: 14, color: textColor.withOpacity(0.9), fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildFormContent(ThemeData theme, AppLocalizations loc) {
    final colorScheme = theme.colorScheme;

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(loc.hello, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(loc.signInToContinue, style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant)),
          const SizedBox(height: 24),

          _buildTextField(
            controller: _emailController,
            label: loc.emailLabel,
            icon: Icons.email_outlined,
            theme: theme,
            keyboardType: TextInputType.emailAddress,
            validator: (v) => (v == null || !v.contains('@')) ? loc.emailError : null,
          ),
          
          const SizedBox(height: 16),

          _buildTextField(
            controller: _passwordController,
            label: loc.passwordLabel,
            icon: Icons.lock_outline,
            theme: theme,
            obscureText: !_isPasswordVisible,
            validator: (v) => (v == null || v.length < 6) ? loc.passwordError : null,
            isLastField: true, // Handle "Done" action on keyboard
            suffixIcon: IconButton(
              icon: Icon(_isPasswordVisible ? Icons.visibility : Icons.visibility_off),
              onPressed: () => setState(() => _isPasswordVisible = !_isPasswordVisible),
            ),
          ),

          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () {
                Navigator.of(context).push(MaterialPageRoute(builder: (context) => PasswordResetScreen(initialEmail: _emailController.text.trim())));
              },
              child: Text(loc.forgotPassword, style: TextStyle(color: colorScheme.primary, fontWeight: FontWeight.bold)),
            ),
          ),

          const SizedBox(height: 20),

          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: _isLoading ? null : _handleSignIn,
              style: FilledButton.styleFrom(
                backgroundColor: colorScheme.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: _isLoading 
                ? SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: colorScheme.onPrimary, strokeWidth: 2.5))
                : Text(loc.signInButton, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            ),
          ),

          const SizedBox(height: 24), 
          
          // Safer layout for small screens
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(loc.noAccountYet, style: TextStyle(color: colorScheme.onSurfaceVariant)),
              const SizedBox(width: 5),
              GestureDetector(
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (context) => const SignUpScreen())),
                child: Text(
                  loc.createAccount,
                  style: TextStyle(color: colorScheme.primary, fontWeight: FontWeight.bold, decoration: TextDecoration.underline, decorationColor: colorScheme.primary),
                ),
              ),
            ],
          ),
          // Add extra padding at bottom so scrolling feels good
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required ThemeData theme,
    bool obscureText = false,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
    Widget? suffixIcon,
    bool isLastField = false,
  }) {
    final colorScheme = theme.colorScheme;
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      validator: validator,
      // Helps UX: Next moves to next field, Done submits
      textInputAction: isLastField ? TextInputAction.done : TextInputAction.next,
      onFieldSubmitted: isLastField ? (_) => _handleSignIn() : null,
      style: TextStyle(fontWeight: FontWeight.w600, color: colorScheme.onSurface),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: colorScheme.primary),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest.withOpacity(0.5),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: colorScheme.primary, width: 2)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: colorScheme.error, width: 1.5)),
      ),
    );
  }
}