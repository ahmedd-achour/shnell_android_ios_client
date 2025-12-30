import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:shnell/model/oredrs.dart';
import 'package:shnell/model/destinationdata.dart';
import 'package:shnell/dots.dart'; 

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

  // --- FIRESTORE ACTIONS ---

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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: theme.colorScheme.error, size: 28),
            const SizedBox(width: 8),
            Text(l10n.cancelOrder, style: TextStyle(color: theme.colorScheme.onSurface)),
          ],
        ),
        content: Text(l10n.cancelOrderMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.keepOrder, style: TextStyle(color: theme.colorScheme.primary)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
              foregroundColor: theme.colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.yesCancel),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    try {
      final orderDoc = await FirebaseFirestore.instance.collection('orders').doc(widget.orderId).get();
      if (orderDoc.exists && orderDoc.data() != null) {
        final order = Orders.fromFirestore(orderDoc);
        for (final stopId in order.stops) {
          await FirebaseFirestore.instance.collection('stops').doc(stopId).delete();
        }
      }
      await FirebaseFirestore.instance.collection('orders').doc(widget.orderId).delete();
      if(mounted) _showSnack(l10n.orderCanceledSuccess, false);
    } catch (e) {
      if(mounted) _showSnack(l10n.orderCancelFailed(e.toString()), true);
    }
  }

  void _showSnack(String msg, bool isError) {
    final scheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: TextStyle(color: isError ? scheme.onError : scheme.onPrimary)),
      backgroundColor: isError ? scheme.error : scheme.primary,
      behavior: SnackBarBehavior.floating,
    ));
  }

  // --- UI BUILDING ---

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('orders').doc(widget.orderId).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: _buildHeaderStatus(l10n.connecting, colorScheme));
          }
          
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return Center(child: Text(l10n.orderNotFound));
          }

          final order = Orders.fromFirestore(snapshot.data!);

          return Stack(
            children: [
              // 1. Radar Animation Background
              Positioned.fill(
                child: _buildRadarBackground(colorScheme.primary),
              ),

              // 2. Center Vehicle Icon (Fancy Visual Hint)
              Positioned(
                top: MediaQuery.of(context).size.height * 0.25,
                left: 0,
                right: 0,
                child: Center(
                  child: _buildPulsingVehicle(order.vehicleType, colorScheme),
                ),
              ),
              
              // 3. Main Content
              SafeArea(
                child: Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Column(
                          children: [
                            const SizedBox(height: 20),
                            _buildHeaderStatus(l10n.searchingForDrivers, colorScheme),
                            const SizedBox(height: 180), // Space for the vehicle icon above

                            // Price Card
                            _buildPriceCard(order, l10n, colorScheme),
                            const SizedBox(height: 16),
                            
                            // Route Card (Read Only)
                            _buildRouteCard(order, l10n, colorScheme),
                            const SizedBox(height: 100), 
                          ],
                        ),
                      ),
                    ),
                    
                    // Bottom Action
                    _buildBottomActions(l10n, colorScheme),
                  ],
                ),
              ),
            ],
          );
        }
      ),
    );
  }

  // --- FANCY VEHICLE ICON ---
  Widget _buildPulsingVehicle(String vehicleType, ColorScheme scheme) {
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return Stack(
          alignment: Alignment.center,
          children: [
            // Pulsing Ring
            Container(
              width: 100 + (20 * _animationController.value),
              height: 100 + (20 * _animationController.value),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: scheme.primary.withOpacity(1 - _animationController.value),
                  width: 2,
                ),
              ),
            ),
            // Background Circle
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                color: scheme.surface,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: scheme.primary.withOpacity(0.1),
                    blurRadius: 10,
                    spreadRadius: 5,
                  )
                ],
              ),
              padding: const EdgeInsets.all(15),
              child: Image.asset(
                'assets/$vehicleType.png', // Dynamic vehicle asset
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => 
                  Icon(Icons.local_shipping, color: scheme.primary, size: 40),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildRadarBackground(Color color) {
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return CustomPaint(
          size: Size.infinite,
          painter: _RadarPainter(_animationController.value, color),
        );
      },
    );
  }

  Widget _buildHeaderStatus(String text, ColorScheme scheme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        RotatingDotsIndicator(),
        const SizedBox(height: 16),
        Text(
          text,
          style: TextStyle(
            color: scheme.primary,
            fontSize: 20,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildPriceCard(Orders order, AppLocalizations l10n, ColorScheme scheme) {
    return Card(
      elevation: 0,
      color: scheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.estimatedPrice,
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant, fontWeight: FontWeight.bold),
                ),
                Text(
                  "${truncateTo2Decimals(order.price)} DT",
                  style: TextStyle(fontSize: 32, color: scheme.primary, fontWeight: FontWeight.w900),
                ),
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.route, size: 16, color: scheme.onSurface),
                  const SizedBox(width: 4),
                  Text(
                    "${truncateTo2Decimals(order.distance)} km",
                    style: TextStyle(fontWeight: FontWeight.bold, color: scheme.onSurface),
                  ),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildRouteCard(Orders order, AppLocalizations l10n, ColorScheme scheme) {
    final stopIds = order.stops.where((id) => id.isNotEmpty).toList();

    return Card(
      elevation: 4,
      shadowColor: Colors.black12,
      color: scheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildLocationRow(
              isStart: true,
              icon: Icons.my_location,
              title: l10n.pickupLocation,
              address: order.namePickUp,
              scheme: scheme,
            ),
            _buildConnectorLine(scheme),
            FutureBuilder<List<Map<String, dynamic>>>(
              future: Future.wait(stopIds.map((id) async {
                final doc = await getStopById(id);
                if (doc.exists) {
                  final data = DropOffData.fromFirestore(doc);
                  return {'id': id, 'data': data};
                }
                return null;
              })).then((list) => list.whereType<Map<String, dynamic>>().toList()),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const LinearProgressIndicator();
                final stops = snapshot.data!;
                return Column(
                  children: stops.asMap().entries.map((entry) {
                    final index = entry.key;
                    final dropOffData = entry.value['data'] as DropOffData;
                    final isLast = index == stops.length - 1;
                    return Column(
                      children: [
                        _buildLocationRow(
                          isStart: false,
                          icon: isLast ? Icons.flag_rounded : Icons.stop_circle_outlined,
                          title: isLast ? l10n.finalDropOff : l10n.dropOffNumber(index + 1),
                          address: dropOffData.destinationName,
                          scheme: scheme,
                        ),
                        if (!isLast) _buildConnectorLine(scheme),
                      ],
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationRow({
    required bool isStart,
    required IconData icon,
    required String title,
    required String address,
    required ColorScheme scheme,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: isStart ? scheme.primary : scheme.secondary, size: 24),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(
                  address, 
                  style: TextStyle(fontSize: 16, color: scheme.onSurface, fontWeight: FontWeight.w600),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectorLine(ColorScheme scheme) {
    return Container(
      margin: const EdgeInsets.only(left: 11),
      alignment: Alignment.centerLeft,
      height: 24,
      child: VerticalDivider(color: scheme.outlineVariant, thickness: 1.5, width: 1.5),
    );
  }

  Widget _buildBottomActions(AppLocalizations l10n, ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: scheme.surface,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -5))],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: scheme.error, width: 1.5),
              foregroundColor: scheme.error,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            onPressed: _cancelOrder,
            icon: const Icon(Icons.close),
            label: Text(l10n.cancelSearch, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ),
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  final double animationValue;
  final Color baseColor;
  _RadarPainter(this.animationValue, this.baseColor);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.3); // Adjust center to match icon position
    final maxRadius = size.width * 0.5;

    final circlePaint = Paint()
      ..color = baseColor.withOpacity(0.1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    for (int i = 1; i <= 3; i++) {
      canvas.drawCircle(center, maxRadius * (i / 3), circlePaint);
    }

    final sweepAngle = 2 * 3.14159 * animationValue;
    final sweepPaint = Paint()
      ..shader = SweepGradient(
        colors: [Colors.transparent, baseColor.withOpacity(0.3)],
        stops: const [0.75, 1.0],
        startAngle: sweepAngle - (3.14159 / 2),
        endAngle: sweepAngle + (3.14159 / 2),
        transform: GradientRotation(sweepAngle) 
      ).createShader(Rect.fromCircle(center: center, radius: maxRadius));

    canvas.drawCircle(center, maxRadius, sweepPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}