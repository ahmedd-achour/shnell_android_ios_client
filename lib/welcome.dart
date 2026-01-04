import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shnell/SignInScreen.dart';

class ShnellWelcomeScreen extends StatelessWidget {
  const ShnellWelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Uses the native theme background
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          // 1. Background Image Asset
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: MediaQuery.of(context).size.height * 0.65,
            child: Image.asset(
              'assets/shnellWelcome.png', // Your generated asset
              fit: BoxFit.cover,
            ),
          ),

          // 2. Rounded Interaction Panel
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              height: MediaQuery.of(context).size.height * 0.42,
              width: double.infinity,
              decoration: BoxDecoration(
                // Native surface color from your main theme
                color: Theme.of(context).colorScheme.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28.0), // The "Slightly Rounded" edge
                ),
                boxShadow: [
                  BoxShadow(
                    blurRadius: 10,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
              child: Column(
                children: [
                  // Branding Section
                  Text(
                    'SHNELL',
                    
                    style: GoogleFonts.montserrat(
                                fontSize: 48,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 4,
                                color: Theme.of(context).colorScheme.primary
                              ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'L\'excellence en mouvement',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const Spacer(),

                  // Buttons with slightly rounded corners
                  _buildActionBtn(
                    context,
                    label: 'Sign in',
                    isPrimary: true,
                  ),
                  const SizedBox(height: 12),
                  _buildActionBtn(
                    context,
                    label: 'Register',
                    isPrimary: false,

                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionBtn(BuildContext context, {required String label, required bool isPrimary }) {
    final colors = Theme.of(context).colorScheme;

    return SizedBox(
      width: double.infinity,
      height: 58,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: isPrimary ? colors.primary : colors.secondaryContainer,
          foregroundColor: isPrimary ? colors.onPrimary : colors.onSecondaryContainer,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14.0), // Consistent rounding
          ),
        ),
        onPressed: () {
          Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (context)=>UnifiedAuthScreen()));
        },
        child: Text(
          label,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}