import 'dart:async';
import 'dart:math' as math; // Import math for animation logic
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:shnell/model/oredrs.dart';
import 'package:shnell/dots.dart'; // Assuming this is your custom loading indicator

class PendingOrderWidget extends StatefulWidget {
  final String orderId;

  const PendingOrderWidget({
    super.key,
    required this.orderId,
  });

  @override
  State<PendingOrderWidget> createState() => _PendingOrderWidgetState();
}

class _PendingOrderWidgetState extends State<PendingOrderWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _rippleController;

  @override
  void initState() {
    super.initState();
    // Looping controller for the ripple effect
    _rippleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
  }

  @override
  void dispose() {
    _rippleController.dispose();
    super.dispose();
  }

  // --- FIRESTORE ACTIONS ---
  Future<void> _cancelOrder() async {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context).colorScheme;

    // 1. Confirm Dialog
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: theme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: theme.error),
            const SizedBox(width: 10),
            Text(l10n.cancelOrder, style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(l10n.cancelOrderMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.keepOrder),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: theme.error),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.yesCancel),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    // 2. Atomic Deletion Logic
    try {
      final firestore = FirebaseFirestore.instance;
      final orderRef = firestore.collection('orders').doc(widget.orderId);

      // Start a Batch
      final batch = firestore.batch();

      final orderDoc = await orderRef.get();
      if (orderDoc.exists) {
        final order = Orders.fromFirestore(orderDoc);
        
        // Add stop deletions to batch
        for (final stopId in order.stops) {
          final stopRef = firestore.collection('stops').doc(stopId);
          batch.delete(stopRef);
        }
      }
      
      // Add order deletion to batch
      batch.delete(orderRef);

      // Commit all changes at once
      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.orderCanceledSuccess),
            backgroundColor: theme.primary,
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.of(context).pop(); 
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.orderCancelFailed(e.toString())),
            backgroundColor: theme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // --- UI ---
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('orders').doc(widget.orderId).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: RotatingDotsIndicator());
          }

          if (!snapshot.hasData || !snapshot.data!.exists) {
            return Center(
              child: Text(
                l10n.orderNotFound, 
                style: TextStyle(fontSize: 18, color: scheme.onSurfaceVariant)
              ),
            );
          }

          return Stack(
            fit: StackFit.expand,
            children: [
              // 1. Ripple Animation Background
              Positioned.fill(
                child: CustomPaint(
                  painter: _RipplePainter(
                    _rippleController,
                    color: scheme.primary,
                  ),
                ),
              ),

              // 2. Central Icon (Visual anchor for the radar)
         

              // 3. Foreground Content (Text & Buttons)
              SafeArea(
                child: Column(
                  children: [
                    Text(
                      l10n.searchingForDrivers,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: scheme.onSurface,
                        letterSpacing: 0.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    
                    const Spacer(),
                    
                    // Cancel Button
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                      child: SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: scheme.error, width: 1.5),
                            foregroundColor: scheme.error,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)
                            ),
                            backgroundColor: scheme.surface.withOpacity(0.8),
                          ),
                          onPressed: _cancelOrder,
                          icon: const Icon(Icons.close_rounded),
                          label: Text(
                            l10n.cancelSearch,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// --- IMPROVED PAINTER ---
class _RipplePainter extends CustomPainter {
  final Animation<double> animation;
  final Color color;

  _RipplePainter(this.animation, {required this.color}) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2); // Center of screen
    final maxRadius = math.min(size.width, size.height) * 0.8;

    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    // Draw 3 expanding circles based on the animation value
    // We offset the phase of each circle so they ripple out continuously
    for (int i = 0; i < 3; i++) {
      final double phaseShift = i * 0.33; // 0.0, 0.33, 0.66
      double progress = (animation.value + phaseShift) % 1.0;
      
      // Calculate radius and opacity based on progress
      final double radius = progress * maxRadius;
      final double opacity = 1.0 - progress; // Fade out as it expands

      paint.color = color.withOpacity(opacity * 0.5); // Max opacity 0.5
      
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}