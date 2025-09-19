import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shnell/AuthHandler.dart';
import 'package:shnell/dots.dart';

class LanguageSelectionWidget extends StatefulWidget {
  const LanguageSelectionWidget({super.key});

  @override
  State<LanguageSelectionWidget> createState() => _LanguageSelectionWidgetState();
}

class _LanguageSelectionWidgetState extends State<LanguageSelectionWidget> {
  final AuthMethods _authMethods = AuthMethods();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  fb_auth.User? currentUser;

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
    currentUser = _authMethods.getCurrentUser();
    _fetchCurrentUserLanguage();
  }

  Future<void> _fetchCurrentUserLanguage() async {
    if (currentUser != null) {
      try {
        final docSnapshot = await _firestore.collection('users').doc(currentUser!.uid).get();
        if (docSnapshot.exists) {
          final userData = docSnapshot.data() as Map<String, dynamic>;
          setState(() {
            _selectedLanguage = userData['language'] ?? 'en';
          });
        }
      } catch (e) {
        debugPrint("Error fetching current user language: $e");
      }
    }
  }

  Future<void> _updateLanguage(String newLanguage) async {
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in to change language.')),
      );
      return;
    }
    setState(() {
      _selectedLanguage = newLanguage;
    });
    try {
      await _firestore.collection('users').doc(currentUser!.uid).update({
        'language': newLanguage,
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Language updated to ${newLanguage.toUpperCase()}')),
      );
    } catch (e) {
      debugPrint("Error updating language: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update language: $e')),
      );
      _fetchCurrentUserLanguage();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool darkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: darkMode ? Colors.grey[900] : Colors.white,
        elevation: 0,
        iconTheme: IconThemeData(
          color: darkMode ? Colors.amber[300] : Colors.amber[800],
        ),
      ),
      body: currentUser == null
          ? const Center(child: RotatingDotsIndicator())
          : Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
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
                          darkMode: darkMode,
                          onTap: () => _updateLanguage(language['code']!),
                        );
                      },
                    ),
                  ),
                ],
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
    required bool darkMode,
    required VoidCallback onTap,
  }) {
    final Color selectedColor = darkMode ? Colors.amber[300]! : Colors.amber;
    final Color textColor = darkMode ? Colors.grey[200]! : Colors.grey[800]!;
    final Color backgroundColor = darkMode ? Colors.grey[800]! : Colors.grey[100]!;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        margin: const EdgeInsets.only(bottom: 15),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        decoration: BoxDecoration(
          color: isSelected ? selectedColor.withOpacity(0.15) : backgroundColor,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: isSelected ? selectedColor : Colors.transparent,
            width: 2,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: selectedColor.withOpacity(0.25),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [],
        ),
        child: Row(
          children: [
            Text(flagEmoji, style: const TextStyle(fontSize: 35)),
            const SizedBox(width: 20),
            Expanded(
              child: Text(
                languageName,
                style: TextStyle(
                  color: isSelected ? selectedColor : textColor,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  fontSize: 18,
                ),
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle_rounded, color: selectedColor, size: 28),
          ],
        ),
      ),
    );
  }
}
