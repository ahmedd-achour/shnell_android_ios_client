import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:shnell/model/oredrs.dart';
import 'package:shnell/model/destinationdata.dart';
// import 'package:shnell/dots.dart'; // Assuming this is your custom loading indicator used elsewhere

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
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    // Slightly faster animation for better ripple effect over 3 seconds
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  double truncateTo2Decimals(double value) {
    return (value * 100).floorToDouble() / 100;
  }

  // --- LOGIC ---

  Future<DocumentSnapshot> getStopById(String id) async {
    return await FirebaseFirestore.instance.collection("stops").doc(id).get();
  }

  Future<void> _cancelOrder() async {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: theme.colorScheme.surface,
        title: Text(l10n.cancelOrder),
        content: Text(l10n.cancelOrderMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.keepOrder),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.yesCancel),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    try {
      final orderDoc = await FirebaseFirestore.instance.collection('orders').doc(widget.orderId).get();
      if (orderDoc.exists) {
        final order = Orders.fromFirestore(orderDoc);
        for (final stopId in order.stops) {
          await FirebaseFirestore.instance.collection('stops').doc(stopId).delete();
        }
      }
      await FirebaseFirestore.instance.collection('orders').doc(widget.orderId).delete();
      if (mounted) Navigator.of(context).pop(); // Go back after cancel
    } catch (e) {
      debugPrint("Error canceling: $e");
    }
  }

  // --- UI ---

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('orders').doc(widget.orderId).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData || !snapshot.data!.exists) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            return Center(child: Text(l10n.orderNotFound));
          }

          final order = Orders.fromFirestore(snapshot.data!);

          return Stack(
            children: [
              // 1. TOP SECTION: THE RIPPLE ANIMATION (Prioritized Search)
              Positioned.fill(
                child: Column(
                  children: [
                    Expanded(
                      flex: 6, // 60% of screen for search animation
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // REPLACED RADAR WITH RIPPLE BACKGROUND
                          _buildRippleBackground(cs.primary),
                          _buildPulsingVehicle(order.vehicleType, cs),
                          Positioned(
                            top: MediaQuery.of(context).padding.top + 20,
                            child: _buildStatusPill(l10n.searchingForDrivers, cs),
                          ),
                        ],
                      ),
                    ),
                    const Expanded(flex: 4, child: SizedBox()), // Space holder for bottom sheet
                  ],
                ),
              ),

              // 2. BOTTOM SECTION: COMPACT DETAILS
              Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  height: MediaQuery.of(context).size.height * 0.45,
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 20,
                        offset: const Offset(0, -5),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      // Handle bar for visual cue
                      Container(
                        margin: const EdgeInsets.only(top: 12, bottom: 8),
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: cs.outlineVariant,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // A. Key Metrics (Price & Distance)
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  _buildMetric(
                                    "${truncateTo2Decimals(order.price)} DT",
                                    l10n.estimatedPrice,
                                    cs.primary,
                                    true,
                                  ),
                                  Container(width: 1, height: 40, color: cs.outlineVariant),
                                  _buildMetric(
                                    "${truncateTo2Decimals(order.distance)} km",
                                    l10n.distance,
                                    cs.onSurface,
                                    false,
                                  ),
                                ],
                              ),
                              
                              const SizedBox(height: 24),
                              
                              // B. Compact Timeline Route
                              Text(l10n.details, style: TextStyle(color: cs.outline, fontSize: 12, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 12),
                              _buildTimelineRoute(order, l10n, cs),
                              
                              const SizedBox(height: 30),
                              
                              // C. Cancel Button
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton(
                                  onPressed: _cancelOrder,
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: cs.error,
                                    side: BorderSide(color: cs.error.withOpacity(0.5)),
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                  child: Text(l10n.cancelSearch),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        }
      ),
    );
  }

  // --- WIDGETS ---

  Widget _buildStatusPill(String text, ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8, offset: const Offset(0, 4))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 14, 
            height: 14, 
            child: CircularProgressIndicator(strokeWidth: 2, color: cs.onPrimaryContainer)
          ),
          const SizedBox(width: 10),
          Text(
            text,
            style: TextStyle(
              color: cs.onPrimaryContainer,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetric(String value, String label, Color color, bool isBig) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: TextStyle(
          fontSize: isBig ? 28 : 22, 
          fontWeight: FontWeight.w800, 
          color: color,
          height: 1.0,
        )),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _buildTimelineRoute(Orders order, AppLocalizations l10n, ColorScheme cs) {
    final stopIds = order.stops.where((id) => id.isNotEmpty).toList();

    return Column(
      children: [
        // Pickup
        _buildTimelineTile(
          isFirst: true,
          isLast: false,
          title: l10n.pickupLocation,
          subtitle: order.namePickUp,
          cs: cs,
        ),
        // Stops (Future Builder)
        FutureBuilder<List<DocumentSnapshot>>(
          future: Future.wait(stopIds.map((id) => getStopById(id))),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const SizedBox(height: 20, child: LinearProgressIndicator(minHeight: 2));
            
            final stops = snapshot.data!;
            return Column(
              children: stops.asMap().entries.map((entry) {
                final index = entry.key;
                final data = DropOffData.fromFirestore(entry.value);
                final isLastItem = index == stops.length - 1;
                
                return _buildTimelineTile(
                  isFirst: false,
                  isLast: isLastItem,
                  title: isLastItem ? l10n.finalDropOff : l10n.dropOffNumber(index + 1),
                  subtitle: data.destinationName,
                  cs: cs,
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _buildTimelineTile({
    required bool isFirst,
    required bool isLast,
    required String title,
    required String subtitle,
    required ColorScheme cs,
  }) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline Line & Dot
          SizedBox(
            width: 24,
            child: Column(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: isFirst ? cs.primary : (isLast ? cs.tertiary : cs.surface),
                    border: Border.all(color: isFirst ? cs.primary : (isLast ? cs.tertiary : cs.outline), width: 2),
                    shape: BoxShape.circle,
                  ),
                  child: isFirst || isLast ? null : Center(child: Container(width: 4, height: 4, decoration: BoxDecoration(color: cs.outline, shape: BoxShape.circle))),
                ),
                if (!isLast) 
                  Expanded(
                    child: Container(
                      width: 2, 
                      color: cs.outlineVariant.withOpacity(0.5),
                      margin: const EdgeInsets.symmetric(vertical: 2),
                    )
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Content
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 24.0), // Spacing between items
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 11, color: cs.primary, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(
                    subtitle, 
                    style: TextStyle(fontSize: 14, color: cs.onSurface, fontWeight: FontWeight.w500),
                    maxLines: 1, 
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPulsingVehicle(String vehicleType, ColorScheme scheme) {
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return Stack(
          alignment: Alignment.center,
          children: [
            // Vehicle Icon Background - subtly pulses with the ripples
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: scheme.surface,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: scheme.primary.withOpacity(0.3 * (1-_animationController.value)),
                    blurRadius: 25,
                    spreadRadius: 2,
                  )
                ],
              ),
              padding: const EdgeInsets.all(20),
              child: Image.asset(
                'assets/$vehicleType.png',
                fit: BoxFit.contain,
                errorBuilder: (_,__,___) => Icon(Icons.local_shipping, color: scheme.primary, size: 40),
              ),
            ),
          ],
        );
      },
    );
  }

  // NEW: RIPPLE PAINTER WIDGET
  Widget _buildRippleBackground(Color color) {
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return CustomPaint(
          size: Size.infinite,
          painter: _RipplePainter(_animationController.value, color),
        );
      },
    );
  }
}

// NEW: THE RIPPLE PAINTER CLASS
class _RipplePainter extends CustomPainter {
  final double animationValue;
  final Color baseColor;
  
  _RipplePainter(this.animationValue, this.baseColor);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    // Calculate max radius to cover expanding area
    final maxRadius = size.width * 0.8; 

    // Define how many ripples we want active at once
    const int rippleCount = 3; 
    // Stagger them evenly across the animation timeline (0.0 to 1.0)
    const double stagger = 1.0 / rippleCount;

    for (int i = 0; i < rippleCount; i++) {
      // Calculate progress for this specific ripple
      // The modulo % 1.0 ensures the progress loops back to 0 when it hits 1
      final double progress = (animationValue + (i * stagger)) % 1.0;
      
      // Current size based on progress
      final double currentRadius = maxRadius * progress;

      // Opacity calculation:
      // Starts at 0.25 opacity when small, fades down to 0.0 as it reaches maxRadius
      final double opacity = (1.0 - progress) * 0.25;

      // Line thickness calculation:
      // Starts thick (5.0), gets thinner as it expands
      final double strokeWidth = 5.0 * (1.0 - progress);

      final paint = Paint()
        ..color = baseColor.withOpacity(opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth > 0 ? strokeWidth : 0.1; // ensure it doesn't crash

      if (currentRadius > 0 && opacity > 0) {
        canvas.drawCircle(center, currentRadius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RipplePainter oldDelegate) => true;
}