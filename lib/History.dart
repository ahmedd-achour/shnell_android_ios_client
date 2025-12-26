import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:shnell/dots.dart';
import 'package:shnell/drawer.dart';

// Internal Imports
import 'package:shnell/model/deals.dart'; // Ensure this has the timestamp & fromFirestore updates
import 'package:shnell/model/oredrs.dart';

// Helper class for the Join
class HistoryItem {
  final Deals deal;
  final Orders order;
  HistoryItem(this.deal, this.order);
}

class UserActivityDashboard extends StatefulWidget {
  const UserActivityDashboard({super.key});

  @override
  State<UserActivityDashboard> createState() => _UserActivityDashboardState();
}

class _UserActivityDashboardState extends State<UserActivityDashboard> {
  final String? _uid = FirebaseAuth.instance.currentUser?.uid;

  Stream<List<HistoryItem>> get _historyStream {
    if (_uid == null) return const Stream.empty();

    return FirebaseFirestore.instance
        .collection('deals')
        .where('idUser', isEqualTo: _uid)
        .orderBy('timestamp', descending: true) // Requires Index
        .snapshots()
        .asyncMap((dealSnapshot) async {
          List<HistoryItem> items = [];
          for (var doc in dealSnapshot.docs) {
            try {
              final deal = Deals.fromFirestore(doc);
              // Fetch Order for details
              final orderDoc = await FirebaseFirestore.instance
                  .collection('orders')
                  .doc(deal.idOrder)
                  .get();

              if (orderDoc.exists) {
                final order = Orders.fromFirestore(orderDoc);
                items.add(HistoryItem(deal, order));
              }
            } catch (e) {
              debugPrint("Error parsing item: $e");
            }
          }
          return items;
        });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);

    // Fallback if l10n is missing context
    if (l10n == null) return const SizedBox();

    return Scaffold(
      backgroundColor: colorScheme.surface,

       appBar: AppBar(
        elevation: 0,
        title: Text(
          l10n.myActivity,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
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

 
      body: StreamBuilder<List<HistoryItem>>(
        stream: _historyStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: RotatingDotsIndicator());
          }
          
          if (snapshot.hasError) {
            return Center(child: Text(l10n.errorLoadingData));
          }

          final history = snapshot.data ?? [];

          if (history.isEmpty) {
            return _buildEmptyState(l10n, colorScheme);
          }

          return Column(
            children: [
              // 1. SUBTLE SUMMARY ROW (Spending is just a stat here)
              _buildSummaryRow(history, theme, l10n),
              
              const Divider(height: 1),

              // 2. LIST HEADER
      
              // 3. HISTORY LIST
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: history.length,
                  itemBuilder: (context, index) {
                    return Column(
                      children: [
                            
                        _buildHistoryCard(history[index], theme, l10n),
                      ],
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // --- STATS / SUMMARY ---

  Widget _buildSummaryRow(List<HistoryItem> data, ThemeData theme, AppLocalizations l10n) {
    double totalSpent = 0.0;
    int completedCount = 0;

    for (var item in data) {
      if (item.deal.status == 'terminated') {
        totalSpent += item.order.price;
        completedCount++;
      }
    }

    return Container(
      padding: const EdgeInsets.all(16),
      color: theme.colorScheme.surface,
      child: Row(
        children: [
          // Completed
          Expanded(
            child: _buildInfoChip(
              theme,
              label: l10n.completed ,
              value: "$completedCount",
              icon: Icons.check_circle_outline,
              iconColor: Colors.green,
            ),
          ),
          const SizedBox(width: 12),
          // Spending (Small and blended in)
          Expanded(
            child: _buildInfoChip(
              theme,
              label: l10n.totalSpent,
              value: "${totalSpent.toStringAsFixed(0)}", // Removed currency symbol for cleanliness, or add small suffix
              icon: Icons.account_balance_wallet_outlined,
              iconColor: theme.colorScheme.primary,
            ),
          ),

        ],
      ),
    );
  }

  Widget _buildInfoChip(ThemeData theme, {
    required String label, 
    required String value, 
    required IconData icon, 
    required Color iconColor,
    String suffix = ""
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant.withOpacity(0.3))
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: iconColor),
              const SizedBox(width: 6),
              RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: value,
                      style: TextStyle(
                        fontSize: 16, 
                        fontWeight: FontWeight.bold, 
                        color: theme.colorScheme.onSurface
                      )
                    ),
                    if (suffix.isNotEmpty)
                      TextSpan(
                        text: suffix,
                        style: TextStyle(
                          fontSize: 10, 
                          color: theme.colorScheme.onSurfaceVariant
                        )
                      ),
                  ]
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            label, 
            style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // --- HISTORY CARD ---

  Widget _buildHistoryCard(HistoryItem item, ThemeData theme, AppLocalizations l10n) {
    final colors = theme.colorScheme;
    final statusInfo = _getStatusInfo(item.deal.status, colors, l10n);
    final dateStr = DateFormat('MMM dd, HH:mm').format(item.deal.timestamp ?? DateTime.now());

    

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colors.outlineVariant.withOpacity(0.5))
      ),
      color: colors.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Row 1: Header
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    shape: BoxShape.circle,
                    border: Border.all(color: colors.outlineVariant)
                  ),
                  child: Icon(_getVehicleIcon(item.order.vehicleType), color: colors.primary, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: statusInfo.color.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: statusInfo.color.withOpacity(0.3))
                            ),
                            child: Text(
                              statusInfo.text.toUpperCase(),
                              style: TextStyle(color: statusInfo.color, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                          Text(
                            "${item.order.price.toStringAsFixed(0)} TND",
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: colors.onSurface),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(dateStr, style: TextStyle(color: colors.outline, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
            
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12.0),
              child: Divider(height: 1, thickness: 0.5),
            ),

            // Row 2: Addresses
            Row(
              children: [
                Column(
                  children: [
                    Icon(Icons.circle, size: 8, color: colors.primary),
                    Container(height: 20, width: 1, color: colors.outlineVariant),
                    Icon(Icons.square, size: 8, color: colors.secondary),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.order.namePickUp,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: colors.onSurface, fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        // Just showing destination count or first destination for brevity
                        "${item.order.stops.length} ${l10n.destinations}", 
                        style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant),
                      ),
                    ],
                  ),
                )
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(AppLocalizations l10n, ColorScheme colors) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history_toggle_off, size: 60, color: colors.outlineVariant),
          const SizedBox(height: 16),
          Text(l10n.noActivityYet , style: TextStyle(color: colors.outline)),
        ],
      ),
    );
  }

  // --- HELPERS ---

  _StatusInfo _getStatusInfo(String status, ColorScheme colors, AppLocalizations l10n) {
    switch (status) {
      case 'terminated': 
        return _StatusInfo(Colors.green, l10n.completed);
      case 'canceled': 
        return _StatusInfo(colors.error, l10n.canceled );
      case 'accepted': 
        return _StatusInfo(colors.primary, l10n.ongoing );
      case 'almost': 
        return _StatusInfo(colors.tertiary, l10n.enRoute);
      default: 
        return _StatusInfo(colors.outline, status);
    }
  }

  IconData _getVehicleIcon(String type) {
    if (type.contains("moto")) return Icons.two_wheeler;
    if (type.contains("heavy")) return Icons.local_shipping;
    return Icons.directions_car;
  }
}

class _StatusInfo {
  final Color color;
  final String text;
  _StatusInfo(this.color, this.text);
}