import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shnell/dots.dart';
import 'package:shnell/drawer.dart';
import 'package:shnell/model/destinationdata.dart';
import 'package:shnell/model/oredrs.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

// --- Helper Models ---
class Deal {
  final String id;
  final String idUser;
  final String idDriver;
  final String idOrder;
  final String status;
  final Timestamp time;

  Deal({
    required this.id,
    required this.idUser,
    required this.idDriver,
    required this.idOrder,
    required this.status,
    required this.time,
  });

  factory Deal.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Deal(
      id: doc.id,
      idUser: data['idUser'] ?? '',
      idDriver: data['idDriver'] ?? '',
      idOrder: data['idOrder'] ?? '',
      status: data['status'] ?? 'accepted',
      time: data['time'] ?? Timestamp.now(),
    );
  }
}

class DealHistory {
  final Deal deal;
  final Orders order;

  DealHistory({
    required this.deal,
    required this.order,
  });
}

// --- Custom RotatingDotsIndicator Widget ---

// --- HistoryScreen Widget ---
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  // Helper to fetch stop document by ID
  Future<DocumentSnapshot> getStopsFromFirebasebyId(String id) async {
    if (id.isEmpty) {
      throw Exception('Invalid stop ID: ID cannot be empty');
    }
    return await FirebaseFirestore.instance.collection("stops").doc(id).get();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final l10n = AppLocalizations.of(context)!;
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('Please sign in to view history')),
      );
    }

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          elevation: 0,
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          bottom: const TabBar(
            isScrollable: false,
            indicatorColor: Colors.amber,
            labelColor: Colors.amber,
            unselectedLabelColor: Colors.grey,
            labelStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            tabs: [
              Tab(text: 'All'),
              Tab(text: 'Ongoing'),
              Tab(text: 'Completed'),
              Tab(text: 'Canceled'),
            ],
          ),
          title: Text(
            l10n.history,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          centerTitle: false,
          leading: Builder(
            builder: (context) {
              return IconButton(
                icon: Icon(Icons.menu, color: Theme.of(context).colorScheme.primary, size: 30),
                onPressed: () => Scaffold.of(context).openDrawer(),
              );
            },
          ),
        ),
        drawer: const ShnellDrawer(),
        body: Column(
          children: [
            _buildStatisticsCard(user.uid),
            Expanded(
              child: StreamBuilder<List<DealHistory>>(
                stream: _fetchHistoryStream(user.uid),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: RotatingDotsIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Text(
                          'Error: ${snapshot.error}',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.red.shade400, fontSize: 16),
                        ),
                      ),
                    );
                  }
                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Image.asset("assets/empty.png", height: 200, fit: BoxFit.contain),
                          const SizedBox(height: 24),
                          const Text(
                            'No history items found',
                            style: TextStyle(fontSize: 18, color: Colors.grey),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    );
                  }

                  final allItems = snapshot.data!;
                  final ongoingItems = allItems
                      .where((d) => d.deal.status == 'accepted' || d.deal.status == 'almost')
                      .toList();
                  final finishedItems = allItems.where((d) => d.deal.status == 'terminated').toList();
                  final canceledItems = allItems.where((d) => d.deal.status == 'canceled').toList();

                  return TabBarView(
                    children: [
                      _buildHistoryList(allItems),
                      _buildHistoryList(ongoingItems),
                      _buildHistoryList(finishedItems),
                      _buildHistoryList(canceledItems),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatisticsCard(String userId) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('deals').where('idUser', isEqualTo: userId).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox.shrink();
        }

        final deals = snapshot.data!.docs;
        final totalTrips = deals.length;
        final canceledTrips = deals.where((doc) => doc['status'] == 'canceled').length;
        final completionPercentage = totalTrips > 0 ? ((totalTrips - canceledTrips) / totalTrips) * 100 : 0.0;
        final cancellationPercentage = totalTrips > 0 ? (canceledTrips / totalTrips) * 100 : 0.0;

        return Card(
          elevation: 2,
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem(
                  'Total Trips',
                  totalTrips.toString(),
                  Icons.local_taxi,
                  Colors.amber,
                ),
                _buildStatItem(
                  'Completed',
                  '${completionPercentage.toStringAsFixed(0)}%',
                  Icons.check_circle_outline,
                  Colors.green,
                ),
                _buildStatItem(
                  'Canceled',
                  '${cancellationPercentage.toStringAsFixed(0)}%',
                  Icons.cancel_outlined,
                  Colors.red,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 30),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  Stream<List<DealHistory>> _fetchHistoryStream(String userId) {
    final dealsAsUserStream = FirebaseFirestore.instance
        .collection('deals')
        .where('idUser', isEqualTo: userId)
        .snapshots();

    final dealsAsDriverStream = FirebaseFirestore.instance
        .collection('deals')
        .where('idDriver', isEqualTo: userId)
        .snapshots();

    return dealsAsUserStream.asyncMap((userSnapshot) async {
      final driverSnapshot = await dealsAsDriverStream.first;
      final Map<String, Deal> uniqueDeals = {};

      for (var doc in userSnapshot.docs) {
        uniqueDeals[doc.id] = Deal.fromFirestore(doc);
      }
      for (var doc in driverSnapshot.docs) {
        uniqueDeals[doc.id] = Deal.fromFirestore(doc);
      }

      final List<Future<DealHistory?>> futureHistories = uniqueDeals.values.map((deal) async {
        final orderDoc = await FirebaseFirestore.instance.collection('orders').doc(deal.idOrder).get();
        if (orderDoc.exists) {
          return DealHistory(
            deal: deal,
            order: Orders.fromFirestore(orderDoc),
          );
        }
        return null;
      }).toList();

      final histories = (await Future.wait(futureHistories)).whereType<DealHistory>().toList();

      histories.sort((a, b) => b.deal.time.compareTo(a.deal.time));
      return histories;
    });
  }

  Widget _buildHistoryList(List<DealHistory> items) {
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset("assets/empty.png", height: 200, fit: BoxFit.contain),
            const SizedBox(height: 24),
            const Text(
              'No items found for this category',
              style: TextStyle(fontSize: 18, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final item = items[i];
        return _DealCard(item: item, getStopsFromFirebasebyId: getStopsFromFirebasebyId);
      },
    );
  }
}

// --- DealCard Widget ---
class _DealCard extends StatefulWidget {
  final DealHistory item;
  final Future<DocumentSnapshot> Function(String id) getStopsFromFirebasebyId;

  const _DealCard({required this.item, required this.getStopsFromFirebasebyId});

  @override
  _DealCardState createState() => _DealCardState();
}

class _DealCardState extends State<_DealCard> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final status = widget.item.deal.status;
    final statusInfo = _getStatusInfo(status);
    final timestamp = widget.item.deal.time;
    final date = DateFormat('dd MMM yyyy, HH:mm').format(timestamp.toDate());
    final pickupLocation = widget.item.order.namePickUp;
    final price = widget.item.order.price;
    final isScheduled = !widget.item.order.isInstantDelivery &&
        widget.item.order.additionalInfo?['scheduledTimestamp'] != null;
    final theme = Theme.of(context);

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Package image
                Container(
                  width: 50,
                  height: 50,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Image.asset("assets/box.png"),
                ),
                const SizedBox(width: 16),
                // Main content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Status and Date
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: statusInfo['color']!.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              _getStatusText(status),
                              style: TextStyle(
                                color: statusInfo['color'],
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          Text(
                            date,
                            style: TextStyle(
                              color: theme.textTheme.bodySmall?.color,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Price
                      Text(
                        'TND ${price.toStringAsFixed(2)}',
                        style: TextStyle(
                          color: theme.primaryColor,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      // Trip ID and scheduled info
                      Row(
                        children: [
                          Icon(Icons.trip_origin, size: 16, color: theme.textTheme.bodySmall?.color),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              'ID: ${widget.item.deal.id.substring(0, 8)}...',
                              style: TextStyle(
                                color: theme.textTheme.bodySmall?.color,
                                fontSize: 12,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isScheduled) ...[
                            const SizedBox(width: 8),
                            Icon(Icons.schedule, color: theme.primaryColor, size: 16),
                            const SizedBox(width: 4),
                            Text(
                              'Scheduled',
                              style: TextStyle(
                                color: theme.primaryColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // See Details Button
          TextButton(
            onPressed: () {
              setState(() {
                _isExpanded = !_isExpanded;
              });
            },
            child: Text(
              _isExpanded ? 'Hide Details' : 'See Details',
              style: const TextStyle(
                color: Colors.amber,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          // Timeline section (only shown when expanded)
          if (_isExpanded)
            _buildTimeline(context, pickupLocation, widget.item.order.stops),
        ],
      ),
    );
  }

  Widget _buildTimeline(BuildContext context, String pickup, List<String> stopIds) {
    final ids = stopIds.where((id) => id.isNotEmpty).toList();

    return FutureBuilder<List<DropOffData>>(
      future: Future.wait(ids.map((id) => widget.getStopsFromFirebasebyId(id).then((doc) {
        if (doc.exists) {
          return DropOffData.fromFirestore(doc);
        }
        throw Exception('Stop document $id not found');
      }))),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor.withOpacity(0.5),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
            ),
            child: const Center(child: RotatingDotsIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor.withOpacity(0.5),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
            ),
            child: Center(
              child: Text(
                'Error loading stops: ${snapshot.error}',
                style: const TextStyle(color: Colors.red, fontSize: 14),
              ),
            ),
          );
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor.withOpacity(0.5),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
            ),
            child: const Center(
              child: Text(
                'No stops found',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
            ),
          );
        }

        final dropOffs = snapshot.data!;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor.withOpacity(0.5),
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(16),
              bottomRight: Radius.circular(16),
            ),
          ),
          child: Column(
            children: [
              _TimelineItem(
                icon: Icons.my_location,
                location: pickup,
                isCompleted: true,
                isFirst: true,
                isLast: dropOffs.isEmpty,
                isPickup: true,
              ),
              ...dropOffs.asMap().entries.map((entry) {
                final dropOff = entry.value;
                final isLast = entry.key == dropOffs.length - 1;
                return _TimelineItem(
                  icon: Icons.location_on,
                  location: dropOff.destinationName,
                  isCompleted: dropOff.isDelivered == true,
                  isLast: isLast,
                  isPickup: false,
                );
              }).toList(),
            ],
          ),
        );
      },
    );
  }

  Map<String, dynamic> _getStatusInfo(String status) {
    switch (status) {
      case 'accepted':
      case 'almost':
        return {'color': Colors.orange, 'icon': Icons.fire_truck_rounded};
      case 'terminated':
        return {'color': Colors.green, 'icon': Icons.check_circle};
      case 'canceled':
        return {'color': Colors.red, 'icon': Icons.cancel};
      default:
        return {'color': Colors.grey, 'icon': Icons.help_outline};
    }
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'accepted':
      case 'almost':
        return 'Ongoing';
      case 'terminated':
        return 'Completed';
      case 'canceled':
        return 'Canceled';
      default:
        return 'Unknown';
    }
  }
}

// --- TimelineItem Widget ---
class _TimelineItem extends StatelessWidget {
  const _TimelineItem({
    required this.icon,
    required this.location,
    required this.isCompleted,
    this.isFirst = false,
    this.isLast = false,
    this.isPickup = false,
  });

  final IconData icon;
  final String location;
  final bool isCompleted;
  final bool isFirst;
  final bool isLast;
  final bool isPickup;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = isPickup ? Colors.green : (isCompleted ? Colors.amber : Colors.red);
    final textColor = isCompleted ? theme.textTheme.bodyMedium?.color : theme.textTheme.bodySmall?.color;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            if (!isFirst)
              Container(
                width: 2,
                height: 20,
                color: Colors.grey[400],
              ),
            Icon(icon, color: color, size: 24),
            if (!isLast)
              Container(
                width: 2,
                height: 20,
                color: Colors.grey[400],
              ),
          ],
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(top: isFirst ? 0 : 4, bottom: isLast ? 0 : 4),
            child: Text(
              location,
              style: TextStyle(
                fontSize: 16,
                fontWeight: isCompleted ? FontWeight.bold : FontWeight.normal,
                color: textColor,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
    );
  }
}