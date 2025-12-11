import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  // Helper method to determine if the locale is RTL
  bool _isRtl(String localeName) {
    const rtlLanguages = []; // Extend as needed
    return rtlLanguages.contains(localeName);
  }

  @override
  Widget build(BuildContext context) {
    // Access localization
    final l10n = AppLocalizations.of(context);

    // Fallback if localization is not available
    if (l10n == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Privacy Policy'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: const Center(child: Text('Localization not available')),
      );
    }

    // Define sections using localized strings
    final List<_PolicySectionData> sections = [
      _PolicySectionData(
        heading: l10n.introHeading,
        body: l10n.introBody,
      ),
      _PolicySectionData(
        heading: l10n.infoCollectionHeading,
        body: l10n.infoCollectionBody,
      ),
      _PolicySectionData(
        heading: l10n.infoUsageHeading,
        body: l10n.infoUsageBody,
      ),
      _PolicySectionData(
        heading: l10n.infoSharingHeading,
        body: l10n.infoSharingBody,
      ),
      _PolicySectionData(
        heading: l10n.dataSecurityHeading,
        body: l10n.dataSecurityBody,
      ),
      _PolicySectionData(
        heading: l10n.dataRetentionHeading,
        body: l10n.dataRetentionBody,
      ),
      _PolicySectionData(
        heading: l10n.dataRightsHeading,
        body: l10n.dataRightsBody,
      ),
      _PolicySectionData(
        heading: l10n.thirdPartyHeading,
        body: l10n.thirdPartyBody,
      ),
      _PolicySectionData(
        heading: l10n.childrenPrivacyHeading,
        body: l10n.childrenPrivacyBody,
      ),
      _PolicySectionData(
        heading: l10n.commissionHeading,
        body: l10n.commissionBody,
      ),
      _PolicySectionData(
        heading: l10n.cancellationHeading,
        body: l10n.cancellationBody,
      ),
      _PolicySectionData(
        heading: l10n.suspensionHeading,
        body: l10n.suspensionBody,
      ),
      _PolicySectionData(
        heading: l10n.driverPerformanceHeading,
        body: l10n.driverPerformanceBody,
      ),
    ];

    final isRtl = _isRtl(l10n.localeName);
    final dateFormat = DateFormat.yMMMd(l10n.localeName);
    final lastUpdated = DateTime(2025, 8, 22); // Consider fetching dynamically

    return Scaffold(
      appBar: AppBar(
        elevation: 1, // Subtle elevation for better visibility
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: Text(
          l10n.privacyPolicyTitle,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
        ),
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back,
            color: Theme.of(context).colorScheme.primary,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.symmetric(
          horizontal: MediaQuery.of(context).size.width * 0.05, // Responsive padding
          vertical: 16.0,
        ),
        child: Column(
          crossAxisAlignment: isRtl ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(
              l10n.privacyPolicyUpdated(dateFormat.format(lastUpdated)),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontStyle: FontStyle.italic,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 14,
                  ),
              textAlign: isRtl ? TextAlign.end : TextAlign.start,
            ),
            const SizedBox(height: 20),
            if (sections.isEmpty)
              Center(
                child: Text(
                  l10n.localeName == 'ar' ? 'لا توجد أقسام متاحة' : 'No sections available',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              )
            else
              ...sections.map((section) => _buildSection(context, section)).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(BuildContext context, _PolicySectionData section) {
    final isRtl = _isRtl(AppLocalizations.of(context)?.localeName ?? 'en');
    return Padding(
      padding: const EdgeInsets.only(bottom: 24.0),
      child: Column(
        crossAxisAlignment: isRtl ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Text(
            section.heading.isNotEmpty ? section.heading : (isRtl ? 'قسم بدون عنوان' : 'Untitled Section'),
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
            textAlign: isRtl ? TextAlign.end : TextAlign.start,
          ),
          const SizedBox(height: 10),
          Text(
            section.body.isNotEmpty ? section.body : (isRtl ? 'لا يوجد محتوى' : 'No content available'),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontSize: 16,
                  height: 1.5,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
            textAlign: isRtl ? TextAlign.end : TextAlign.start,
          ),
        ],
      ),
    );
  }
}

class _PolicySectionData {
  final String heading;
  final String body;

  const _PolicySectionData({
    required this.heading,
    required this.body,
  });
}