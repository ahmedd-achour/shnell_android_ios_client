import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:cloud_firestore/cloud_firestore.dart';
// Assuming you have this set up based on previous context

class LanguageSelectionWidget extends StatefulWidget {
  const LanguageSelectionWidget({super.key});

  @override
  State<LanguageSelectionWidget> createState() => _LanguageSelectionWidgetState();
}

class _LanguageSelectionWidgetState extends State<LanguageSelectionWidget> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final currentUser = fb_auth.FirebaseAuth.instance.currentUser;

  String? _selectedLanguage;

  final List<Map<String, String>> _languages = [
    {'code': 'en', 'name': 'English', 'flag': '🇬🇧'},
    {'code': 'fr', 'name': 'Français', 'flag': '🇫🇷'},
    {'code': 'es', 'name': 'Español', 'flag': '🇪🇸'},
    {'code': 'de', 'name': 'Deutsch', 'flag': '🇩🇪'},
    {'code': 'ar', 'name': 'العربية', 'flag': '🇸🇦'},
    {'code': 'zh', 'name': '中文', 'flag': '🇨🇳'},
    {'code': 'ja', 'name': '日本語', 'flag': '🇯🇵'},
    {'code': 'ru', 'name': 'Русский', 'flag': '🇷🇺'},
    {'code': 'pt', 'name': 'Português', 'flag': '🇧🇷'},
    {'code': 'it', 'name': 'Italiano', 'flag': '🇮🇹'},
  ];

  @override
  void initState() {
    super.initState();
    _fetchCurrentUserLanguage();
  }

  Future<void> _fetchCurrentUserLanguage() async {
    if (currentUser != null) {
      try {
        final docSnapshot = await _firestore.collection('users').doc(currentUser!.uid).get();
        if (docSnapshot.exists) {
          final userData = docSnapshot.data() as Map<String, dynamic>;
          if (mounted) {
            setState(() {
              _selectedLanguage = userData['language'] ?? 'en';
            });
          }
        }
      } catch (e) {
        debugPrint("Error fetching current user language: $e");
      }
    }
  }

  Future<void> _updateLanguage(String newLanguage) async {
    final theme = Theme.of(context);
    
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please log in to change language.'),
          backgroundColor: theme.colorScheme.error,
        ),
      );
      return;
    }

    // Optimistic UI update
    setState(() {
      _selectedLanguage = newLanguage;
    });


    try {
      Navigator.of(context).pop(); // Close the language selection screen

      await _firestore.collection('users').doc(currentUser!.uid).update({
        'language': newLanguage,
      });

      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Language updated to ${newLanguage.toUpperCase()}'),
            backgroundColor: theme.colorScheme.primary,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint("Error updating language: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update language: $e'),
            backgroundColor: theme.colorScheme.error,
          ),
        );
      }
      // Revert if failed
      _fetchCurrentUserLanguage();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    // Optional: Access localization if you want the title "Select Language" translated
    // final l10n = AppLocalizations.of(context); 

    return Scaffold(
       appBar: AppBar(
        elevation: 0,
      ),
      backgroundColor: colorScheme.surface,
     body: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
              child: ListView.builder(
                physics: const BouncingScrollPhysics(),
                itemCount: _languages.length,
                itemBuilder: (context, index) {
                  final language = _languages[index];
                  final isSelected = _selectedLanguage == language['code'];
                  
                  return _buildLanguageOption(
                    context,
                    languageCode: language['code']!,
                    languageName: language['name']!,
                    flagEmoji: language['flag']!,
                    isSelected: isSelected,
                    colorScheme: colorScheme,
                    onTap: () => _updateLanguage(language['code']!),
                  );
                },
              ),
            ),
    );
  }

  Widget _buildLanguageOption(
    BuildContext context, {
    required String languageCode,
    required String languageName,
    required String flagEmoji,
    required bool isSelected,
    required ColorScheme colorScheme,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        margin: const EdgeInsets.only(bottom: 15),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          // Logic: Use Primary Container if selected, otherwise a subtle surface container
          color: isSelected 
              ? colorScheme.primaryContainer 
              : colorScheme.surfaceContainerHighest, 
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? colorScheme.primary : Colors.transparent,
            width: 2,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: colorScheme.shadow.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [],
        ),
        child: Row(
          children: [
            Text(flagEmoji, style: const TextStyle(fontSize: 32)),
            const SizedBox(width: 20),
            Expanded(
              child: Text(
                languageName,
                style: TextStyle(
                  color: isSelected ? colorScheme.onPrimaryContainer : colorScheme.onSurface,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 16,
                ),
              ),
            ),
            if (isSelected)
              Icon(
                Icons.check_circle_rounded, 
                color: colorScheme.primary, 
                size: 24
              ),
          ],
        ),
      ),
    );
  }
}