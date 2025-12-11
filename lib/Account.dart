import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shnell/Account/changeLanguage.dart';
import 'package:shnell/Account/personalDetails.dart';
import 'package:shnell/Account/privacyPolicy.dart';
import 'package:shnell/AuthHandler.dart';
import 'package:shnell/SignInScreen.dart';
import 'package:shnell/dots.dart';
import 'package:shnell/drawer.dart';
import 'package:shnell/splashScreen.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final fb_auth.User? _currentUser = fb_auth.FirebaseAuth.instance.currentUser;
  bool _isProcessing = false;

  Future<void> _logoutAction() async {
    setState(() => _isProcessing = true);
    await AuthMethods().logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const SignInScreen()),
      (_) => false,
    );
  }

  Future<void> _toggleDarkMode(bool newValue) async {
    final l10n = AppLocalizations.of(context)!;
    if (_currentUser == null) return;
    setState(() => _isProcessing = true);
    try {
      await _firestore
          .collection('users')
          .doc(_currentUser.uid)
          .update({'darkMode': newValue});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.failedToUpdate(e.toString()))),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (_currentUser == null) {
      return Scaffold(body: Center(child: Text(l10n.userNotLoggedIn)));
    }

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        title: Text(
          l10n.accountTitle,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        leading: Builder(
          builder: (context) {
            return IconButton(
              icon: Icon(Icons.menu, color: Theme.of(context).colorScheme.primary, size: 30),
              onPressed: () => Scaffold.of(context).openDrawer(),
            );
          },
        ),
      ),
      drawer: const ShnellDrawer(),
      body: Stack(
        children: [
          StreamBuilder<DocumentSnapshot>(
            stream: _firestore.collection('users').doc(_currentUser.uid).snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: RotatingDotsIndicator(color: Colors.amber));
              }
              if (snapshot.hasError) {
                return Center(child: Text(l10n.errorText(snapshot.error.toString())));
              }
              
              final userData = snapshot.data!.data() as Map<String, dynamic>? ?? {};
              final isDarkMode = userData['darkMode'] ?? false;

              return SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSectionTitle(context, l10n.generalSettings),
                      _buildSettingsCard(
                        children: [
                          _buildSettingsTile(
                            Icons.person_outline,
                            l10n.personalInfo,
                            () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PersonalInfoPage())),
                          ),
                          _buildSeparator(),
                          _buildSwitchTile(
                            Icons.dark_mode_outlined,
                            l10n.darkMode,
                            isDarkMode,
                            _toggleDarkMode,
                          ),
                          _buildSeparator(),
                          _buildSettingsTile(
                            Icons.language,
                            l10n.changeLanguage,
                            () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LanguageSelectionWidget())),
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: 32),
                      
                      _buildSectionTitle(context, l10n.information),
                      _buildSettingsCard(
                        children: [
                          _buildSettingsTile(
                            Icons.info_outline,
                            l10n.aboutUsAndPolicy,
                            () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen())),
                          ),
                        ],
                      ),

                      const SizedBox(height: 32),

                      _buildSectionTitle(context, l10n.accountActions),
                      _buildSettingsCard(
                        children: [
                          _buildSettingsTile(
                            Icons.logout,
                            l10n.logout,
                            _logoutAction,
                          ),
                          _buildSeparator(),
                  
                        ],
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              );
            },
          ),
          
          if (_isProcessing) const Waiting(),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 8.0, bottom: 12.0),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8),
            ),
      ),
    );
  }

  Widget _buildSettingsCard({required List<Widget> children}) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: children,
      ),
    );
  }

  Widget _buildSeparator() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.0),
      child: Divider(height: 1, thickness: 1, color: Color(0xFFE0E0E0)),
    );
  }

  Widget _buildSettingsTile(IconData icon, String title, VoidCallback onTap, {bool isDestructive = false}) {
    final theme = Theme.of(context);
    final color = isDestructive ? Colors.red.shade600 : theme.colorScheme.primary;
    final textColor = isDestructive ? Colors.red.shade600 : theme.textTheme.titleMedium?.color;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Row(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: 16,
                  color: textColor,
                ),
              ),
            ),
            if (!isDestructive) Icon(Icons.arrow_forward_ios, size: 16, color: theme.colorScheme.onSurface.withOpacity(0.5)),
          ],
        ),
      ),
    );
  }

  Widget _buildSwitchTile(IconData icon, String title, bool value, ValueChanged<bool> onChanged) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.primary;
    return AbsorbPointer(
      absorbing: _isProcessing,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: Row(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: 16,
                  color: theme.textTheme.titleMedium?.color,
                ),
              ),
            ),
            Switch(
              value: value,
              onChanged: onChanged,
              activeColor: theme.colorScheme.primary,
            ),
          ],
        ),
      ),
    );
  }
}
