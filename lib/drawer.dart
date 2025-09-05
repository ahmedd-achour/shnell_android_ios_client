import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:shnell/Account/privacyPolicy.dart';
import 'package:shnell/mainUsers.dart';
import 'package:shnell/dots.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:shnell/trackDriverPerPhone.dart';


class ShnellDrawer extends StatefulWidget {
  final int? initialIndex; // Optional index to initialize MainUsersScreen

  const ShnellDrawer({Key? key, this.initialIndex}) : super(key: key);

  @override
  State<ShnellDrawer> createState() => _ShnellDrawerState();
}

class _ShnellDrawerState extends State<ShnellDrawer> {
  final fb_auth.User? currentUser = fb_auth.FirebaseAuth.instance.currentUser;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Helper function to navigate to a specific index in MainUsersScreen
  void _navigateToMainUsersScreen(BuildContext context, int index) {
   
      Navigator.pop(context);
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => MainUsersScreen(initialIndex: index),
        ),
      );
    
  }

  // Helper widget for Drawer tiles
  Widget _buildDrawerTile({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: Colors.amber),
      title: Text(
        title,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (currentUser == null) {
      return Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: const BoxDecoration(color: Colors.amber),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const CircleAvatar(
                    radius: 30,
                    backgroundImage: NetworkImage(
                      'https://firebasestorage.googleapis.com/v0/b/shnell-393a6.appspot.com/o/default.jpeg?alt=media&token=b4fed130-bb4b-4a7f-b5fe-3fba23b8f035',
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    l10n.drawerGuest,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            _buildDrawerTile(
              icon: Icons.dashboard,
              title: l10n.drawerUpdateApp,
              onTap: () => _navigateToMainUsersScreen(context, 0),
            ),
            _buildDrawerTile(
              icon: Icons.help_outline,
              title: l10n.drawerHelpAndSupport,
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen()),
                );
              },
            ),
          ],
        ),
      );
    }

    return Drawer(
      child: StreamBuilder<DocumentSnapshot>(
        stream: _firestore.collection('users').doc(currentUser!.uid).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: RotatingDotsIndicator(color: Colors.amber));
          }
          if (snapshot.hasError) {
            return Center(child: Text(l10n.drawerErrorLoadingUser));
          }
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return Center(child: Text(l10n.drawerUserDataNotFound));
          }

          final userData = snapshot.data!.data() as Map<String, dynamic>;
          final userName = userData['name'] ?? l10n.drawerUser;
          final profileImage = 
              'https://firebasestorage.googleapis.com/v0/b/shnell-393a6.appspot.com/o/default.jpeg?alt=media&token=b4fed130-bb4b-4a7f-b5fe-3fba23b8f035';

          return ListView(
            padding: EdgeInsets.zero,
            children: [
              DrawerHeader(
                decoration: const BoxDecoration(color: Colors.amber),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundImage: NetworkImage(profileImage),
                      backgroundColor: Colors.grey[200],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      userName,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              _buildDrawerTile(
                icon: Icons.dashboard,
                title: l10n.drawerUpdateApp,
                onTap: () => _navigateToMainUsersScreen(context, 0),
              ),
              _buildDrawerTile(
                icon: Icons.settings,
                title: l10n.drawerAccountSettings,
                onTap: () => _navigateToMainUsersScreen(context, 2),
              ),
              _buildDrawerTile(
                icon: Icons.fire_truck,
                title: l10n.drawerMyServices,
                onTap: () => _navigateToMainUsersScreen(context, 1),
              ),
               _buildDrawerTile(
                icon: Icons.search,
                title: l10n.drawerSearchingCouriers,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (context)=>SearchCourierByPhoneNumber())),
              ),
             
             
              const Divider(color: Colors.amber),
              _buildDrawerTile(
                icon: Icons.help_outline,
                title: l10n.drawerHelpAndSupport,
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen()),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}
