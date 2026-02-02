import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shnell/SignInScreen.dart'; // ← adjust path if needed

class ShnellWelcomeScreen extends StatelessWidget {
  const ShnellWelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background image with subtle overlay
          Positioned.fill(
            child: Image.asset(
              'assets/shnellWelcome.png',
              fit: BoxFit.cover,
              alignment: Alignment.center,
            ),
          ),

          // Dark gradient overlay → improves text readability
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.15),
                    Colors.black.withOpacity(0.45),
                    Colors.black.withOpacity(0.75),
                  ],
                  stops: const [0.0, 0.55, 1.0],
                ),
              ),
            ),
          ),

          // Main content
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isTall = constraints.maxHeight > 750;

                return Column(
                  children: [
                    // Top spacing / optional logo or empty space
                    const Spacer(flex: 1),

                    // Branding – big & bold
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Text(
                        'SHNELL',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.montserrat(
                          fontSize: isTall ? 64 : 52,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 5,
                          height: 1.05,
                          color: Theme.of(context).colorScheme.primary,
                          shadows: [
                            Shadow(
                              blurRadius: 12,
                              color: Colors.black.withOpacity(0.5),
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Tagline
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 40),
                      child: Text(
                        'L\'excellence en mouvement',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(
                          fontSize: isTall ? 22 : 18,
                          fontWeight: FontWeight.w500,
                          color: Colors.white.withOpacity(0.95),
                          height: 1.3,
                        ),
                      ),
                    ),

                    const Spacer(flex: 5),

                    // Buttons area
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                      child: Column(
                        children: [
                          _buildActionButton(
                            context,
                            label: 'Commencer maintenant',
                            isPrimary: true,
                            onPressed: () {
                              Navigator.pushReplacement(
                                context,
                                MaterialPageRoute(builder: (_) => const UnifiedAuthScreen()),
                              );
                            },
                          ),
                          const SizedBox(height: 16),
                          _buildActionButton(
                            context,
                            label: 'J\'ai déjà un compte',
                            isPrimary: false,
                            onPressed: () {
                              Navigator.pushReplacement(
                                context,
                                MaterialPageRoute(builder: (_) => const UnifiedAuthScreen()), // e.g. login tab
                              );
                            },
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(
    BuildContext context, {
    required String label,
    required bool isPrimary,
    required VoidCallback onPressed,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return SizedBox(
      width: double.infinity,
      height: 56,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: isPrimary ? colors.primary : colors.surface,
          foregroundColor: isPrimary ? colors.onPrimary : colors.onSurface,
          elevation: isPrimary ? 2 : 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          side: isPrimary
              ? null
              : BorderSide(
                  color: colors.outline.withOpacity(0.6),
                  width: 1.5,
                ),
        ),
        child: Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
          ),
        ),
      ),
    );
  }
}