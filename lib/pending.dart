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

  // Helper to fetch stop document by ID
  Future<DocumentSnapshot> getStopsFromFirebasebyId(String id) async {
    if (id.isEmpty) {
      throw Exception('Invalid stop ID: ID cannot be empty');
    }
    return await FirebaseFirestore.instance.collection("stops").doc(id).get();
  }

  // Cancel Order Method
  Future<void> _cancelOrder() async {
    final l10n = AppLocalizations.of(context)!;
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.warning, color: Colors.redAccent, size: 28),
            const SizedBox(width: 8),
            Text(
              l10n.cancelOrder,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
            ),
          ],
        ),
        content: Text(
          l10n.cancelOrderMessage,
          style: const TextStyle(fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              l10n.keepOrder,
              style: const TextStyle( fontSize: 16),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              l10n.yesCancel,
              style: const TextStyle( fontSize: 16),
            ),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    try {
      // Delete order and associated stops
      final orderDoc = await FirebaseFirestore.instance.collection('orders').doc(widget.orderId).get();
      if (orderDoc.exists && orderDoc.data() != null) {
        final order = Orders.fromFirestore(orderDoc);
        for (final stopId in order.stops) {
          await FirebaseFirestore.instance.collection('stops').doc(stopId).delete();
        }
      }
      await FirebaseFirestore.instance.collection('orders').doc(widget.orderId).delete();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.orderCanceledSuccess),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.orderCancelFailed(e.toString())),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    // Get screen dimensions for responsive design
    final mediaQuery = MediaQuery.of(context);
    final isTablet = mediaQuery.size.width > 600;
    final horizontalPadding = isTablet ? mediaQuery.size.width * 0.1 : 24.0;
    final titleFontSize = isTablet ? 24.0 : 20.0;
    final priceFontSize = isTablet ? 50.0 : 40.0;
    final locationNameFontSize = isTablet ? 20.0 : 18.0;

    return Theme(
      data: theme.copyWith(
        textTheme: theme.textTheme.apply(),
      ),
      child: Scaffold(
        body: Stack(
          children: [
            _buildRadarBackground(),
            SafeArea(
              child: _buildContentStream(l10n, horizontalPadding, titleFontSize, priceFontSize, locationNameFontSize),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRadarBackground() {
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return CustomPaint(
          size: Size.infinite,
          painter: _RadarPainter(_animationController.value),
        );
      },
    );
  }

Widget _buildContentStream(
    AppLocalizations l10n,
    double horizontalPadding,
    double titleFontSize,
    double priceFontSize,
    double locationNameFontSize,
  ) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('orders').doc(widget.orderId).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: _buildSearchingIndicator(l10n.connecting, titleFontSize),
          );
        }
        if (snapshot.hasError) {
          return Center(
            child: Text(
              l10n.error(snapshot.error.toString()),
              style: const TextStyle(color: Colors.red),
            ),
          );
        }
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.check_circle_outline, color: Colors.green, size: 80),
                const SizedBox(height: 20),
                Text(
                  l10n.orderNotFound,
                  style: TextStyle(fontSize: titleFontSize, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          );
        }

        final order = Orders.fromFirestore(snapshot.data!);

       // Corrected code
return Padding(
  padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _buildSearchingIndicator(l10n.searchingForDrivers, titleFontSize),
      const SizedBox(height: 48),
      
      Expanded(
        child: SingleChildScrollView(
          child: _buildJourneyDetails(order, l10n, priceFontSize, locationNameFontSize),
        ),
      ),
      
      _buildCancelButton(l10n),
    ],
  ),
);
      },
    );
  }
  Widget _buildJourneyDetails(
    Orders order,
    AppLocalizations l10n,
    double priceFontSize,
    double locationNameFontSize,
  ) {
    final stopIds = order.stops.where((id) => id.isNotEmpty).toList();

    return FutureBuilder<List<DropOffData>>(
      future: Future.wait(stopIds.map((id) => getStopsFromFirebasebyId(id).then((doc) {
        if (doc.exists) {
          return DropOffData.fromFirestore(doc);
        }
        throw Exception('Stop document $id not found');
      }))),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: RotatingDotsIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Text(
              l10n.error(snapshot.error.toString()),
              style: const TextStyle(color: Colors.red),
            ),
          );
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return Center(
            child: Text(
              "noStopsFound",
              style: const TextStyle(fontSize: 18),
            ),
          );
        }

        final stopData = snapshot.data!;
        final isTablet = MediaQuery.of(context).size.width > 600;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.tndPrice(truncateTo2Decimals(order.price)),
                        style: TextStyle(
                          fontSize: priceFontSize,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.straighten, color: Colors.amber, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            l10n.distanceKm(order.distance),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
            _buildLocationRow(
              Icons.my_location,
              order.namePickUp,
              l10n.pickupLocation,
              locationNameFontSize,
            ),
            _buildJourneyLine(),
            ...stopData.asMap().entries.map((entry) {
              final index = entry.key;
              final dropOff = entry.value;
              final isLast = index == stopData.length - 1;
              return Column(
                children: [
                  _buildLocationRow(
                    isLast ? Icons.location_on : Icons.arrow_downward,
                    dropOff.destinationName,
                    isLast ? l10n.finalDropOff : l10n.dropOffNumber(index + 1),
                    locationNameFontSize,
                    customerName: dropOff.customerName,
                    customerPhoneNumber: dropOff.customerPhoneNumber,
                  ),
                  if (!isLast) _buildJourneyLine(),
                ],
              );
            }).toList(),
            if (isTablet) const SizedBox(height: 48), // Add more space for larger screens
          ],
        );
      },
    );
  }

  Widget _buildCancelButton(AppLocalizations l10n) {
    final mediaQuery = MediaQuery.of(context);
    final buttonHeight = mediaQuery.size.height > 800 ? 56.0 : 48.0;

    return Center(
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          label: Text(
            l10n.cancelSearch,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.redAccent),
          ),
          onPressed: _cancelOrder,
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: Colors.redAccent.withOpacity(0.5), width: 1.5),
            padding: EdgeInsets.symmetric(vertical: buttonHeight / 2),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchingIndicator(String text, double titleFontSize) {
    return Column(
      children: [
        Text(
          text,
          style: TextStyle(
            color: Colors.amber,
            fontSize: titleFontSize,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 16),
        const Center(child: RotatingDotsIndicator()),
      ],
    );
  }

  Widget _buildJourneyLine() {
    return Padding(
      padding: const EdgeInsets.only(left: 12.0, top: 4, bottom: 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          height: 40,
          width: 2,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.amber.withOpacity(0.2),
                Colors.amber.withOpacity(0.0),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLocationRow(
    IconData icon,
    String location,
    String label,
    double locationNameFontSize, {
    String? customerName,
    String? customerPhoneNumber,
  }) {
    final mediaQuery = MediaQuery.of(context);
    final textScaleFactor = mediaQuery.textScaleFactor;
    final isTablet = mediaQuery.size.width > 600;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: Colors.amber, size: isTablet ? 32 : 24),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 14 * textScaleFactor,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                location,
                style: TextStyle(
                  fontSize: locationNameFontSize * textScaleFactor,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (customerName != null || customerPhoneNumber != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      width: 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (customerName != null)
                        Row(
                          children: [
                            Icon(
                              Icons.person,
                              size: 16 * textScaleFactor,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              customerName,
                              style: TextStyle(
                                fontSize: 14 * textScaleFactor,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      if (customerName != null && customerPhoneNumber != null)
                        const SizedBox(height: 6),
                      if (customerPhoneNumber != null)
                        Row(
                          children: [
                            Icon(
                              Icons.phone,
                              size: 16 * textScaleFactor,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              customerPhoneNumber,
                              style: TextStyle(
                                fontSize: 14 * textScaleFactor,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _RadarPainter extends CustomPainter {
  final double animationValue;
  _RadarPainter(this.animationValue);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = (size.width < size.height ? size.width : size.height) * 0.5;

    final circlePaint = Paint()
      ..color = Colors.amber.withOpacity(0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    for (int i = 1; i <= 3; i++) {
      canvas.drawCircle(center, maxRadius * (i / 3), circlePaint);
    }

    final sweepAngle = 2 * 3.14159 * animationValue;
    final sweepPaint = Paint()
      ..shader = SweepGradient(
        colors: [Colors.transparent, Colors.amber.withOpacity(0.25)],
        stops: const [0.7, 1.0],
        startAngle: sweepAngle - (3.14159 / 2.5),
        endAngle: sweepAngle + (3.14159 / 2.5),
      ).createShader(Rect.fromCircle(center: center, radius: maxRadius));

    canvas.drawCircle(center, maxRadius, sweepPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}