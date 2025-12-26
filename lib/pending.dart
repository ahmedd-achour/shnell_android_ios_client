import 'dart:async';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:shnell/dots.dart';
import 'package:shnell/model/oredrs.dart'; // Your custom loader if needed

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
    _rippleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat();
  }

  @override
  void dispose() {
    _rippleController.dispose();
    super.dispose();
  }

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


  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('orders')
            .doc(widget.orderId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: RotatingDotsIndicator());
          }

          if (!snapshot.hasData || !snapshot.data!.exists) {
            return Center(
              child: Text(
                l10n.orderNotFound,
                style: TextStyle(fontSize: 18, color: scheme.onSurfaceVariant),
              ),
            );
          }

          final orderDoc = snapshot.data!;
          final order = Orders.fromFirestore(orderDoc);

          return Stack(
            children: [
              // Subtle ripple background
              Positioned.fill(
                child: CustomPaint(
                  painter: _RipplePainter(
                    _rippleController,
                    color: scheme.primary.withOpacity(0.3),
                  ),
                ),
              ),

              // Main content
              SafeArea(
                child: Column(
                  children: [
                    const SizedBox(height: 60),

                    // Title
                    Text(
                      l10n.searchingForDrivers,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: scheme.onSurface,
                      ),
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 20),

                    // Subtitle
                    Text(
                      l10n.searchingForDrivers ,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: scheme.onSurface.withOpacity(0.7),
                      ),
                      textAlign: TextAlign.center,
                    ),

                    const Spacer(),

                    // Central animated icon (car with radar feel)
                    AnimatedBuilder(
                      animation: _rippleController,
                      builder: (_, __) {
                        return Image.asset( 
                          'assets/${order.vehicleType}.png',
                          width: 150 + (_rippleController.value * 20),
                          height: 150 + (_rippleController.value * 20),
                        );
                      },
                    ),

                    const Spacer(),

                    // Order summary card at bottom
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      child: Card(
                        elevation: 8,
                        shadowColor: scheme.primary.withOpacity(0.2),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        color: scheme.surface.withOpacity(0.85), // Translucent feel
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Pickup → Dropoff
                              _buildTripRow(Icons.social_distance_rounded, order.distance),
                              const Divider(height: 32),

                              // Price & Payment
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    l10n.priceLabel,
                                    style: theme.textTheme.titleMedium,
                                  ),
                                  Text(
                                     '${l10n.tndPrice(order.price)}',
                                    style: theme.textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: scheme.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Cancel button
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      child: SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: scheme.error, width: 2),
                            foregroundColor: scheme.error,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          onPressed: _cancelOrder,
                          icon: const Icon(Icons.close_rounded),
                          label: Text(
                            l10n.cancelSearch,
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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

  Widget _buildTripRow(IconData icon1, double text1) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Icon(icon1, color: scheme.primary, size: 28),
        Text(
          l10n.distanceKm(text1),
          style: const TextStyle(fontWeight: FontWeight.w600),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

// Updated Ripple Painter – softer, more ripples, slower fade
class _RipplePainter extends CustomPainter {
  final Animation<double> animation;
  final Color color;

  _RipplePainter(this.animation, {required this.color}) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = math.sqrt(size.width * size.width + size.height * size.height) / 2;

    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    for (int i = 0; i < 4; i++) {
      final double phase = i * 0.25;
      double progress = (animation.value + phase) % 1.0;

      final double radius = progress * maxRadius;
      final double opacity = (1.0 - progress).clamp(0.0, 1.0);

      paint.color = color.withOpacity(opacity * 0.4);

      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}












