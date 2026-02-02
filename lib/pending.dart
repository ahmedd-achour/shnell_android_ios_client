import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shnell/customMapStyle.dart';
import 'package:shnell/dots.dart';           // ← keep if you have it
import 'package:shnell/model/oredrs.dart';   // note: probably typo → orders.dart ?

class PendingOrderWidget extends StatefulWidget {
  final String orderId;
  const PendingOrderWidget({super.key, required this.orderId});

  @override
  State<PendingOrderWidget> createState() => _PendingOrderWidgetState();
}

class _PendingOrderWidgetState extends State<PendingOrderWidget> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  final ValueNotifier<String> mapStyleNotifier = ValueNotifier<String>('');

  
  Timer? _statusTimer;
  final Completer<GoogleMapController> _mapController = Completer();

  // You should load these from assets or constants file

  Future<void> _loadMapStyle(GoogleMapController controller,) async {
      final brightness = Theme.of(context).brightness;
  final style = brightness == Brightness.dark ? darkMapStyle : lightMapStyle;
  
  controller.setMapStyle(style).catchError((e) {
    // Silently handle if style is invalid (optional)
    print('Map style error: $e');
  });
  }

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();

    // Optional: status rotation still here (you can remove if not needed)
    _statusTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) setState(() {});
    });

    // Apply style once map is ready
    _mapController.future.then((controller) => _loadMapStyle(controller));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _mapController.future.then((controller) => _loadMapStyle(controller)); // re-apply when theme changes
  }

  @override
  void dispose() {
    _animationController.dispose();
    _statusTimer?.cancel();
    _mapController.future.then((c) => c.dispose());
    super.dispose();
  }

  String _formatPrice(double value) => value.toStringAsFixed(0); // cleaner look

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('orders').doc(widget.orderId).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(child: RotatingDotsIndicator());
          }

          final order = Orders.fromFirestore(snapshot.data!);

          return Stack(
            children: [
              // 1. Background map (now more responsive)
              GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: LatLng(order.pickUpLocation.latitude, order.pickUpLocation.longitude),
                  zoom: 15.5,
                ),
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
                mapToolbarEnabled: false,
                liteModeEnabled: false,
                onMapCreated: (controller) {
                  if (!_mapController.isCompleted) {
                    _mapController.complete(controller);
                    _loadMapStyle(controller);
                  }
                },
              ),

              // 2. Gradient overlay – stronger at bottom
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: const [0.0, 0.5, 0.82, 1.0],
                      colors: [
                        cs.surface.withOpacity(0.35),
                        cs.surface.withOpacity(0.15),
                        cs.surface.withOpacity(0.88),
                        cs.surface.withOpacity(0.97),
                      ],
                    ),
                  ),
                ),
              ),

              // 3. Center sonar + car icon
              Center(
                child: IgnorePointer(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      AnimatedBuilder(
                        animation: _animationController,
                        builder: (_, __) => CustomPaint(
                          size: const Size(double.infinity, double.infinity),
                          painter: _SonarPainter(_animationController.value, cs.primary),
                        ),
                      ),
                      _buildVehicleIcon(order.vehicleType, cs),
                    ],
                  ),
                ),
              ),

              // 4. Bottom sheet
           Align(
  alignment: Alignment.bottomCenter,
  child: SafeArea(
    child: Container(
      // ── tighter margins ──
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24), // reduced padding
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.09),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Scheduled time ── smaller but still stands out
          Text(
            order.scheduleAt != null
                ? _formatScheduledTime(order.scheduleAt!.toDate())
                : l10n.schedule, // ← update string if needed
            style: TextStyle(
              fontSize: 26,               // ← was 32
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
              height: 1.05,
              color: cs.onSurface,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),     // ← was 6

          Text(
            l10n.schedule,
            style: TextStyle(
              fontSize: 13,               // ← was 15
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),

          const SizedBox(height: 16),     // ← was 24

          // ── Price + category + distance in ONE compact line ──
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              Text(
                "${_formatPrice(order.price)} DT",
                style: TextStyle(
                  fontSize: 20,            // ← was 22
                  fontWeight: FontWeight.w700,
                  color: cs.primary,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: cs.primaryContainer.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  order.category.toUpperCase(),
                  style: TextStyle(
                    fontSize: 12,          // ← was 13
                    fontWeight: FontWeight.w600,
                    color: cs.onPrimaryContainer,
                  ),
                ),
              ),
              Text(
                "• ${order.distance.toStringAsFixed(1)} km",
                style: TextStyle(
                  fontSize: 14,            // ← was 15
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),     // ← was 28 + 32 = 60, now much less

          // Cancel button ── more compact
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _cancelOrder(),
              icon: Icon(Icons.close_rounded, size: 18, color: cs.error),
              label: Text(
                l10n.cancelSearch,
                style: TextStyle(
                  fontSize: 15,           // ← was 16
                  fontWeight: FontWeight.w600,
                  color: cs.error,
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: cs.error,
                side: BorderSide(color: cs.error.withOpacity(0.45)),
                padding: const EdgeInsets.symmetric(vertical: 12), // ← was 14
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap, // smaller hit area
              ),
            ),
          ),
        ],
      ),
    ),
  ),
),],
          );
        },
      ),
    );
  }

  Widget _buildVehicleIcon(String type, ColorScheme cs) {
    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        color: cs.surface,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: cs.primary.withOpacity(0.3), blurRadius: 24, spreadRadius: 4),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Image.asset(
          'assets/$type.png',
          errorBuilder: (_, __, ___) => Icon(Icons.local_taxi, color: cs.primary, size: 38),
        ),
      ),
    );
  }

  String _formatScheduledTime(DateTime dt) {
    // Customize format as needed – example:
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    final day = dt.day;
    final month = dt.month;
    return "$hour:$minute  –  $day/${month.toString().padLeft(2, '0')}";
  }

  Future<void> _cancelOrder() async {
    // ← your existing cancel logic (kept same)
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.cancelOrder),
        content: Text(l10n.cancelOrderMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.keepOrder),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.yesCancel),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    // your delete logic...
    try {
      final orderDoc = await FirebaseFirestore.instance.collection('orders').doc(widget.orderId).get();
      if (orderDoc.exists) {
        final order = Orders.fromFirestore(orderDoc);
        for (final stopId in order.stops) {
          await FirebaseFirestore.instance.collection('stops').doc(stopId).delete();
        }
      }
      await FirebaseFirestore.instance.collection('orders').doc(widget.orderId).delete();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      debugPrint("Cancel error: $e");
    }
  }
}

// Keep your existing _SonarPainter (unchanged)
class _SonarPainter extends CustomPainter {
  final double animationValue;
  final Color baseColor;

  _SonarPainter(this.animationValue, this.baseColor);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width * 0.9;

    for (int i = 0; i < 3; i++) {
      final progress = (animationValue + i * 0.33) % 1.0;
      final radius = maxRadius * progress;
      final opacity = (1.0 - progress) * 0.16;

      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = baseColor.withOpacity(opacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.0 * (1.0 - progress),
      );

      canvas.drawCircle(
        center,
        radius,
        Paint()..color = baseColor.withOpacity(opacity * 0.15),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}