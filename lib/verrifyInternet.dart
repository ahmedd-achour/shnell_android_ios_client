import 'package:flutter/material.dart';

class VerifyInternetScreen extends StatelessWidget {
  const VerifyInternetScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface, // Respects your main app background
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Large offline icon – uses error color for emphasis, falls back to primary
              Icon(
                Icons.wifi_off_rounded,
                size: 120,
                color: colorScheme.error, // Red/orange tint to indicate problem
              ),
              const SizedBox(height: 40),

              // Title
              Text(
                'No Internet Connection',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),

              // Description
              Text(
                'Your device is not connected to the internet. Please check your network settings and try again.',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: colorScheme.onSurface.withOpacity(0.74),
                  height: 1.6,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 50),

              // Retry button – uses primary theme color from your main app
              ElevatedButton.icon(
                onPressed: () {
                  // Add your actual connectivity check logic here
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Checking connection...'),
                      backgroundColor: colorScheme.secondaryContainer,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
                  backgroundColor: colorScheme.primary,
                  foregroundColor: colorScheme.onPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                  elevation: 6,
                  shadowColor: colorScheme.primary.withOpacity(0.3),
                ),
              ),
              const SizedBox(height: 32),

              // Helper tip
              Text(
                'Tip: Try turning airplane mode off and on',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}