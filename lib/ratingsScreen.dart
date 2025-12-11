import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shnell/model/rating.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

/// Popup widget for rating a user/driver and storing the rating in Firestore.
class RatingPopupWidget extends StatefulWidget {
  final String userIdToRate;
  final String driverRated;

  const RatingPopupWidget({
    super.key,
    required this.userIdToRate,
    required this.driverRated,
  });

  @override
  _RatingPopupWidgetState createState() => _RatingPopupWidgetState();
}

class _RatingPopupWidgetState extends State<RatingPopupWidget> {
  int _currentRating = 0;

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _submitRating() async {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    if (_currentRating == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.selectStarError),
          backgroundColor: theme.colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final rating = Rating(
      userId: widget.userIdToRate,
      rating: _currentRating,
      driverRated: widget.driverRated,
    );

    try {
      await FirebaseFirestore.instance.collection('ratings').add(rating.toJson());

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.ratingSuccess),
            backgroundColor: theme.colorScheme.primary,
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${l10n.error(e.toString())}'),
            backgroundColor: theme.colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    // RESPONSIVE CALCULATIONS
    final size = MediaQuery.of(context).size;
    final isTablet = size.width > 600;
    
    // Dynamic dimensions
    final double contentPadding = isTablet ? 32.0 : 20.0;
    final double starSize = isTablet ? 48.0 : 40.0;
    final double titleSize = isTablet ? 26.0 : 22.0;

    return Dialog(
      backgroundColor: colorScheme.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24.0),
      ),
      child: ConstrainedBox(
        // RESPONSIVE: Limit max width for tablets/web
        constraints: const BoxConstraints(maxWidth: 450),
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: Padding(
            padding: EdgeInsets.all(contentPadding),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.rateRide,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontSize: titleSize,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.ratingHelper,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 24),
                
                // RESPONSIVE: Star Rating
                _buildStarRating(colorScheme, starSize),
                
                const SizedBox(height: 24),
                
                // Input Field
                
                
                // Submit Button
                _buildSubmitButton(colorScheme, l10n),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStarRating(ColorScheme colorScheme, double starSize) {
    // RESPONSIVE: FittedBox ensures stars shrink if the screen is extremely narrow
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(5, (index) {
          final starIndex = index + 1;
          return IconButton(
            // Reduce splash radius to fit tighter spaces if needed
            splashRadius: starSize * 0.6, 
            padding: const EdgeInsets.symmetric(horizontal: 4),
            constraints: const BoxConstraints(), // Removes default minimum padding
            onPressed: () => setState(() => _currentRating = starIndex),
            icon: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
              child: Icon(
                starIndex <= _currentRating ? Icons.star_rounded : Icons.star_border_rounded,
                key: ValueKey<bool>(starIndex <= _currentRating),
                color: starIndex <= _currentRating ? colorScheme.primary : colorScheme.outline,
                size: starSize,
              ),
            ),
          );
        }),
      ),
    );
  }


  Widget _buildSubmitButton(ColorScheme colorScheme, AppLocalizations l10n) {
    return FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 0,
      ),
      onPressed: _submitRating,
      child: Text(
        l10n.submitRating,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
    );
  }
}