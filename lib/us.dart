import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class ContactUsWidget extends StatelessWidget {
  const ContactUsWidget({super.key});

  // Centralized URL launcher with error logging
  Future<void> _launchUrl(String urlString) async {
    final uri = Uri.parse(urlString);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        debugPrint('Could not launch $urlString');
      }
    } catch (e) {
      debugPrint('Error launching URL: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Coordinates for the specific location in Boumhal
    const double lat = 36.7214;
    const double lng = 10.3015;
    final String googleMapsUrl = 'https://www.google.com/maps/search/?api=1&query=$lat,$lng';

    return Scaffold(
        appBar: AppBar(
        elevation: 0,

        title: Text(
          l10n.drawerHelpAndSupport,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        child: Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: colorScheme.outlineVariant),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: colorScheme.primaryContainer,
                  child: Icon(Icons.contact_support, size: 32, color: colorScheme.primary),
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.contactUs,
                  style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 24),
        
                _buildContactTile(
                  icon: Icons.phone_rounded,
                  title: '+216 28 29 20 24',
                  subtitle: l10n.emergencyAndSupport,
                  onTap: () => _launchUrl('tel:+21628292024'),
                  colorScheme: colorScheme,
                ),
                _buildContactTile(
                  icon: Icons.email_rounded,
                  title: 'xschnell.service@gmail.com',
                  subtitle: l10n.sendUsAnEmail,
                  onTap: () => _launchUrl('mailto:Xschnell.service@gmail.com?subject=Support%20Request'),
                  colorScheme: colorScheme,
                ),
        
                const Divider(height: 32),
        
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    l10n.ourLocation,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 12),
        
                // Map Section
                GestureDetector(
                  onTap: () => _launchUrl(googleMapsUrl),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Image.asset(
                          'assets/embed.png',
                          height: 200,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (context, _, __) => Container(
                            height: 200,
                            color: colorScheme.surfaceVariant,
                            child: const Icon(Icons.map_outlined, size: 48),
                          ),
                        ),
                        // Floating "Open in Maps" label
                        Positioned(
                          bottom: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              l10n.openInMaps,
                              style: const TextStyle(color: Colors.white, fontSize: 10),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
        
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.location_on, color: colorScheme.primary),
                  title: Text(l10n.addressLine1),
                  subtitle: Text(l10n.addressLine2),
                  onTap: () => _launchUrl(googleMapsUrl),
                ),
        
    
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContactTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required ColorScheme colorScheme,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: colorScheme.surfaceVariant,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: colorScheme.primary),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: Text(subtitle),
      onTap: onTap,
    );
  }
}