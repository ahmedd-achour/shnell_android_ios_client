import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:shnell/AuthHandler.dart';

// Import your service and home screen
// import 'package:shnell/screens/home_screen.dart'; // Uncomment when you have a home screen

class UnifiedAuthScreen extends StatefulWidget {
  const UnifiedAuthScreen({Key? key}) : super(key: key);

  @override
  State<UnifiedAuthScreen> createState() => _UnifiedAuthScreenState();
}

class _UnifiedAuthScreenState extends State<UnifiedAuthScreen> {
  final _formKey = GlobalKey<FormState>();
  TextEditingController _completePhoneNumber = TextEditingController();
  bool _isLoading = false;

  // Function to handle the sign-in logic
  Future<void> _handleSignIn() async {
    // 1. Validate the phone number form
    if (!_formKey.currentState!.validate()) {
      return;
    }
    _formKey.currentState!.save();

    // 2. Set loading state
    setState(() => _isLoading = true);

    try {

      if (_completePhoneNumber.text.length>7){
      // 3. Call your Google Sign-In Service
      // passing the phone number captured from the form
      UserCredential? userCredential = 
          await GoogleSignInService().signInWithGoogle( _completePhoneNumber.text, context);
            ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("annulée"),
            backgroundColor: Colors.redAccent,
          ),
        );

      if (userCredential != null) {
               //FCMTokenManager().initialize(userCredential.user!);
                            String? token = await FirebaseMessaging.instance.getToken();

               await FirebaseFirestore.instance.collection('users').doc(userCredential.user!.uid).update({
                'phone' : _completePhoneNumber,
                'fcmToken' : token
               });
      }}else{
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("Entrer votre numéro de Tel"),
            backgroundColor: Colors.redAccent,
          ),);
      }
        

          
          // 4. Navigate to Home on success
          // Navigator.of(context).pushReplacement(
          //   MaterialPageRoute(builder: (context) => const HomeScreen()),
          // );
          // OR
          // Navigator.pushReplacementNamed(context, '/home');
      
    } catch (e) {
      // 5. Handle Errors
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Annulée: $e"),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      // 6. Reset loading state
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              // Title
              Text(
                "Shnell.",
                style: GoogleFonts.outfit(
                  fontSize: 48,
                  fontWeight: FontWeight.bold,
                  color: colors.primary,
                ),
              ),
              const SizedBox(height: 8),
              // Subtitle
              Text(
                "Veuillez entrer votre numéro pour continuer.",
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  color: colors.onBackground.withOpacity(0.6),
                ),
              ),
              const SizedBox(height: 40),
              
              // Phone Number Input Form
              Form(
                key: _formKey,
                child: IntlPhoneField(
                  languageCode: "fr",
                  initialCountryCode: 'TN',
                  invalidNumberMessage: "Numéro invalide",
                  controller: _completePhoneNumber,
                  decoration: InputDecoration(
                    labelText: 'Numéro de téléphone',
                    filled: true,
                    
                    fillColor: colors.surfaceVariant.withOpacity(0.3),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              
              // Google Sign-In Button
              SizedBox(
                height: 60,
                child: ElevatedButton(
                  // Calls the _handleSignIn function
                  onPressed: _isLoading ? null : _handleSignIn,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.primary,
                    foregroundColor: colors.onPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 24,
                          width: 24,
                          child: SizedBox.shrink()
                        )   : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const FaIcon(FontAwesomeIcons.google, size: 20),
                            const SizedBox(width: 15),
                            Text(
                              "S'identifier avec Google",
                              style: GoogleFonts.poppins(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
         
         
         
              const Spacer(),
              
              // Footer Text
              Text(
                "En vous inscrivant, vous acceptez notre politique de confidentialité.",
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: colors.onBackground.withOpacity(0.4),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}