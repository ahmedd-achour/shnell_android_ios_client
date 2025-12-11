import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';

class UpdateAppScreen extends StatelessWidget {
  const UpdateAppScreen({super.key});

  // 1. Logic to open the link
  Future<void> _launchUpdateUrl(BuildContext context, String urlString) async {
    final Uri url = Uri.parse(urlString);
    
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not launch store link')),
        );
      }
    } catch (e) {
      debugPrint("Error launching URL: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    // 2. PopScope prevents the user from using the "Back" button
    return Scaffold(
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('settings')
            .doc('config')
            .snapshots(),
        builder: (context, snapshot) {
          // Loading State
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
    
          // Error State
          if (snapshot.hasError || !snapshot.hasData || !snapshot.data!.exists) {
            return const Center(child: Text("Error loading configuration"));
          }
    
          // 3. Get the link from Firestore
          final data = snapshot.data!.data() as Map<String, dynamic>?;
          final String? updateLink = data?['update_link_customer_app'];
    
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24.0),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Icon or Image
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.system_update_alt_rounded,
                    size: 60,
                    color: Theme.of(context).colorScheme.surface,
                  ),
                ),
                const SizedBox(height: 32),
    
                // Title
                Text(
                  "Mise à jour requise", // "Update Required"
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
    
                // Description
                Text(
                  "Une nouvelle version est disponible. Veuillez mettre à jour l'application pour continuer à l'utiliser.",
                  // "A new version is available. Please update the app to continue using it."
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 40),
    
                // 4. The Action Button
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton.icon(
                    onPressed: (updateLink != null && updateLink.isNotEmpty)
                        ? () => _launchUpdateUrl(context, updateLink)
                        : null, // Disable if link is missing
                    icon: const Icon(Icons.download_rounded),
                    label: const Text(
                      "Mettre à jour maintenant", // "Update Now"
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}