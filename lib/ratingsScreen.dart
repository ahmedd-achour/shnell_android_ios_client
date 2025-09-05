import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shnell/model/rating.dart';

/// Popup widget for rating a user/driver and storing the rating in Firestore.
class RatingPopupWidget extends StatefulWidget {
  final String userIdToRate;

  const RatingPopupWidget({
    super.key,
    required this.userIdToRate,
  });

  @override
  _RatingPopupWidgetState createState() => _RatingPopupWidgetState();
}

class _RatingPopupWidgetState extends State<RatingPopupWidget> {
  int _currentRating = 0;
  final TextEditingController _infoController = TextEditingController();

  static const Color _amberColor = Color(0xFFFFBF00);
  static const Color _darkBackgroundColor = Color(0xFF1A1A1A);
  static const Color _lightTextColor = Colors.white;
  static const Color _darkTextColor = Color(0xFF1A1A1A);
  static const Color _subtleTextColor = Color(0xFFBDBDBD);
  static const Color _dialogBackgroundColor = Color(0xFF2C2C2C);

  @override
  void dispose() {
    _infoController.dispose();
    super.dispose();
  }

  Future<void> _submitRating() async {
    if (_currentRating == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Veuillez sélectionner au moins une étoile.')),
      );
      return;
    }

    final rating = Rating(
      userId: widget.userIdToRate,
      rating: _currentRating,
      additionalInfos: _infoController.text.trim().isNotEmpty
          ? _infoController.text.trim()
          : null,
    );

    try {
      // Save rating to Firestore
      await FirebaseFirestore.instance.collection('ratings').add(rating.toJson());

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Merci pour votre évaluation!')),
      );

      Navigator.of(context).pop(); // Close the dialog
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur lors de l\'envoi: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: _dialogBackgroundColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24.0),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              "Évaluez votre course",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _lightTextColor,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              "Votre avis nous aide à nous améliorer.",
              textAlign: TextAlign.center,
              style: TextStyle(color: _subtleTextColor, fontSize: 15),
            ),
            const SizedBox(height: 24),
            _buildStarRating(),
            const SizedBox(height: 24),
            _buildAdditionalInfoField(),
            const SizedBox(height: 32),
            _buildSubmitButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildStarRating() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(5, (index) {
        return IconButton(
          onPressed: () => setState(() => _currentRating = index + 1),
          icon: Icon(
            index < _currentRating ? Icons.star_rounded : Icons.star_border_rounded,
            color: _amberColor,
            size: 40,
          ),
        );
      }),
    );
  }

  Widget _buildAdditionalInfoField() {
    return TextField(
      controller: _infoController,
      maxLines: 3,
      style: const TextStyle(color: _lightTextColor),
      decoration: InputDecoration(
        hintText: "Laissez un commentaire (optionnel)...",
        hintStyle: const TextStyle(color: _subtleTextColor),
        filled: true,
        fillColor: _darkBackgroundColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _buildSubmitButton() {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: _amberColor,
        foregroundColor: _darkTextColor,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      onPressed: _submitRating,
      child: const Text(
        "Envoyer l'évaluation",
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
    );
  }
}
