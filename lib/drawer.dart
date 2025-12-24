import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:shnell/Account/privacyPolicy.dart';
import 'package:shnell/AuthHandler.dart';
import 'package:shnell/SignInScreen.dart';
import 'package:shnell/mainUsers.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:shnell/us.dart'; // ContactUsWidget

class ShnellDrawer extends StatefulWidget {
  const ShnellDrawer({Key? key}) : super(key: key);

  @override
  State<ShnellDrawer> createState() => _ShnellDrawerState();
}

class _ShnellDrawerState extends State<ShnellDrawer> {
  final fb_auth.User? currentUser = fb_auth.FirebaseAuth.instance.currentUser;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Widget _buildDrawerTile({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    Widget? trailing,
    Color? iconColor,
    Color? textColor,
  }) {
    return ListTile(
      leading: Icon(icon, color: iconColor ?? Theme.of(context).colorScheme.primary),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
      trailing: trailing,
      onTap: onTap,
    );
  }

  Future<void> _logoutAction() async {
    await AuthMethods().logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const SignInScreen()),
      (_) => false,
    );
  }

@override
Widget build(BuildContext context) {
  final l10n = AppLocalizations.of(context)!;
  final colorScheme = Theme.of(context).colorScheme;

  if (currentUser == null) {
    return const Drawer(child: SizedBox.shrink());
  }

  return Drawer(
    child: StreamBuilder<DocumentSnapshot>(
      stream: _firestore.collection('users').doc(currentUser!.uid).snapshots(),
      builder: (context, snapshot) {
        String userName = l10n.drawerUser;
        if (snapshot.hasData && snapshot.data!.exists) {
          final data = snapshot.data!.data() as Map<String, dynamic>;
          userName = data['name'] ?? userName;
        }

        // Use a Column instead of a ListView to allow bottom alignment
        return Column(
          children: [
            // 1. Scrollable Top Section
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    // Drawer Header
                    _buildHeader(colorScheme, userName),

                    _buildDrawerTile(
                      icon: Icons.person_outline,
                      title: l10n.account,
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const MainUsersScreen(initialIndex: 2),
                          ),
                        );
                      },
                    ),

                    _buildDrawerTile(
                      icon: Icons.help_outline,
                      title: l10n.aboutUsAndPolicy,
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen()),
                        );
                      },
                    ),

                    _buildDrawerTile(
                      icon: Icons.contact_page,
                      title: l10n.drawerHelpAndSupport,
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const ContactUsWidget()),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),

            // 2. Fixed Bottom Section
            const Divider(), // Optional visual separator
            _buildDrawerTile(
              icon: Icons.logout,
              title: l10n.logout,
              iconColor: Colors.red,
              textColor: Colors.red,
              onTap: () async => _showLogoutDialog(context, l10n, colorScheme),
            ),
            const SizedBox(height: 12), // Padding from the bottom of the screen
          ],
        );
      },
    ),
  );
}

// Helper for the Header to keep the build method clean
Widget _buildHeader(ColorScheme colorScheme, String userName) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.only(top: 60, left: 16, bottom: 20),
    decoration: BoxDecoration(color: colorScheme.primary),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 32,
          backgroundImage: const AssetImage("assets/shnell.jpeg"),
          backgroundColor: Colors.grey[200],
        ),
        const SizedBox(height: 12),
        Text(
          userName,
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: colorScheme.onPrimary),
        ),
        const SizedBox(height: 4),
        Text(
          currentUser!.email ?? '',
          style: TextStyle(fontSize: 14, color: colorScheme.onPrimary.withOpacity(0.8)),
        ),
      ],
    ),
  );
}

// Helper for the Logout Dialog
Future<void> _showLogoutDialog(BuildContext context, AppLocalizations l10n, ColorScheme colorScheme) async {
  final confirm = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.logout),
      content: Text(l10n.logout), // You might want a "Are you sure?" string here
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.cancel)),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(l10n.logout, style: TextStyle(color: colorScheme.error)),
        ),
      ],
    ),
  );
  if (confirm == true) {
    await _logoutAction();
  }
}}