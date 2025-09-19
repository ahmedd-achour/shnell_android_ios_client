import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shnell/dots.dart';
import 'package:shnell/trackDriver.dart';
import 'package:shnell/model/oredrs.dart';
import 'package:shnell/model/destinationdata.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

// Use Orders and DropOffData from Deoaklna context (already provided)
class SearchCourierByPhoneNumber extends StatefulWidget {
  const SearchCourierByPhoneNumber({super.key});

  @override
  State<SearchCourierByPhoneNumber> createState() => _SearchCourierByPhoneNumberState();
}

class _SearchCourierByPhoneNumberState extends State<SearchCourierByPhoneNumber> {
  final TextEditingController _phoneController = TextEditingController();
  String? _errorMessage;
  List<Map<String, dynamic>> _results = [];
  bool _isLoading = false;


  Future<void> _search() async {
    final l10n = AppLocalizations.of(context)!;
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      setState(() {
        _errorMessage = l10n.enterValidPhoneNumber;
        _results = [];
        _isLoading = false;
      });
      return;
    }

    // Dismiss the keyboard
    FocusScope.of(context).unfocus();

    setState(() {
      _errorMessage = null;
      _results = [];
      _isLoading = true;
    });

    try {
      final stopsSnapshot = await FirebaseFirestore.instance
          .collection('stops')
          .where('phoneNumber', isEqualTo: phone)
          .get();
      if (stopsSnapshot.docs.isEmpty) {
        setState(() {
          _errorMessage = l10n.noOrderFoundForPhone;
          _isLoading = false;
        });
        return;
      }

      final stopIds = stopsSnapshot.docs.map((doc) => doc.id).toList();
      final stopDataMap = {
        for (var doc in stopsSnapshot.docs)
          doc.id: DropOffData.fromFirestore(doc)
      };

      final matchingOrders = <Map<String, dynamic>>[];
      final ordersSnapshot = await FirebaseFirestore.instance.collection('orders').get();

      for (var doc in ordersSnapshot.docs) {
        final order = Orders.fromFirestore(doc);
        final matchingStopId = order.stops.firstWhere(
          (stopId) => stopIds.contains(stopId),
          orElse: () => '',
        );
        if (matchingStopId.isNotEmpty) {
          matchingOrders.add({
            'orderId': doc.id,
            'order': order,
            'matchingStopId': matchingStopId,
            'matchingDropOff': stopDataMap[matchingStopId],
          });
        }
      }

      if (matchingOrders.isEmpty) {
        setState(() {
          _errorMessage = l10n.noOrderFoundForPhone;
          _isLoading = false;
        });
        return;
      }

      final results = <Map<String, dynamic>>[];
      for (var orderData in matchingOrders) {
        final orderId = orderData['orderId'] as String;
        final order = orderData['order'] as Orders;
        final matchingDropOff = orderData['matchingDropOff'] as DropOffData;

        final dealsSnapshot = await FirebaseFirestore.instance
            .collection('deals')
            .where('idOrder', isEqualTo: orderId)
            .get();

        for (var dealDoc in dealsSnapshot.docs) {
          final dealData = dealDoc.data();
          final timestamp = dealData['timestamp'] as Timestamp?;
          final status = dealData['status'] as String? ?? 'unknown';
          final isWithin240Days = timestamp != null
              ? DateTime.now().difference(timestamp.toDate()).inHours < 72
              : false;
          final isDeliveryOngoing = matchingDropOff.isDelivered == null;
          final isTrackable = (status.toLowerCase() == 'accepted' || status.toLowerCase() == 'almost') && isWithin240Days && isDeliveryOngoing;

          results.add({
            'dealId': dealDoc.id,
            'status': status,
            'isTrackable': isTrackable,
            'order': order,
            'dropOff': matchingDropOff,
          });
        }
      }

      if (results.isEmpty) {
        setState(() {
          _errorMessage = l10n.noActiveDealsFound;
          _isLoading = false;
        });
        return;
      }

      setState(() {
        _results = results;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = l10n.errorSearchingOrder(e.toString());
        _isLoading = false;
      });
    }
  }

  String _getDeliveryStatus(bool? isDelivered) {
    final l10n = AppLocalizations.of(context)!;

    if (isDelivered == null) return l10n.onTheWay;
    if (isDelivered == false) return l10n.returned;
    return l10n.deliveredSuccessfully;
  }

  Color _getStatusColor(bool? isDelivered, BuildContext context) {
    if (isDelivered == null) return Colors.amber.shade700;
    if (isDelivered == false) return Colors.red.shade600;
    return Colors.green.shade600;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 600;

    return Scaffold(
      backgroundColor: colorScheme.surfaceVariant.withOpacity(0.3),
      appBar: AppBar(
        title: Text(
          l10n.trackYourCourier,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurface,
          ),
        ),
        elevation: 0,
        backgroundColor: Colors.transparent,
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: isSmallScreen ? 16.0 : 40.0, vertical: 24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildSearchCard(l10n, isSmallScreen),
                SizedBox(height: isSmallScreen ? 16 : 24),
                if (_errorMessage != null) _buildErrorMessage(l10n),
                _buildResultsList(l10n, isSmallScreen),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchCard(AppLocalizations l10n, bool isSmallScreen) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
      child: Padding(
        padding: EdgeInsets.all(isSmallScreen ? 20.0 : 32.0),
        child: Column(
          children: [
            Image.asset(
              "assets/box.png",
              fit: BoxFit.contain,
              width: isSmallScreen ? 100 : 150,
              height: isSmallScreen ? 100 : 150,
            ),
            SizedBox(height: isSmallScreen ? 12 : 20),
            Text(
              l10n.yourCourierAwaits,
              style: Theme.of(context).textTheme.headlineSmall!.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: isSmallScreen ? 16 : 24),
            TextField(
              controller: _phoneController,
              decoration: InputDecoration(
                labelText: l10n.enterCustomerPhoneNumber,
                labelStyle: TextStyle(color: colorScheme.primary),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide(color: colorScheme.primary.withOpacity(0.5)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide(color: colorScheme.primary.withOpacity(0.5)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide(color: colorScheme.primary, width: 2),
                ),
                prefixIcon: Icon(Icons.phone, color: colorScheme.primary),
              ),
              keyboardType: TextInputType.phone,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            SizedBox(height: isSmallScreen ? 16 : 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _search,
                style: ElevatedButton.styleFrom(
                  backgroundColor: colorScheme.primary,
                  padding: EdgeInsets.symmetric(vertical: isSmallScreen ? 16 : 20),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  elevation: 5,
                ),
                child: _isLoading
                    ? Center(child: const RotatingDotsIndicator(color: Colors.white))
                    : Text(
                        l10n.search,
                        style: Theme.of(context).textTheme.labelLarge!.copyWith(
                              fontSize: isSmallScreen ? 18 : 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              letterSpacing: 1.5,
                            ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorMessage(AppLocalizations l10n) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.error.withOpacity(0.1),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: colorScheme.error),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: colorScheme.error),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _errorMessage!,
              style: Theme.of(context).textTheme.bodyLarge!.copyWith(
                    color: colorScheme.error,
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsList(AppLocalizations l10n, bool isSmallScreen) {
    if (_isLoading) {
      return Center(child: RotatingDotsIndicator(color: Theme.of(context).colorScheme.primary));
    } else if (_results.isEmpty && _errorMessage == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.only(top: 50.0),
          child: Text(
            l10n.noResultsFound,
            style: Theme.of(context).textTheme.bodyLarge!.copyWith(
                  fontSize: isSmallScreen ? 16 : 18,
                  color: Colors.grey[600],
                ),
          ),
        ),
      );
    } else {
      return ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _results.length,
        itemBuilder: (context, index) {
          final result = _results[index];
          final dropOff = result['dropOff'] as DropOffData;
          final isTrackable = result['isTrackable'] as bool;
          final dealId = result['dealId'] as String;
          final deliveryStatus = _getDeliveryStatus(dropOff.isDelivered);
          final statusColor = _getStatusColor(dropOff.isDelivered, context);

          return Card(
            elevation: 5,
            margin: EdgeInsets.symmetric(vertical: isSmallScreen ? 8 : 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Padding(
              padding: EdgeInsets.all(isSmallScreen ? 16.0 : 20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildInfoRow(
                    Icons.location_on,
                    '${l10n.destination}:',
                    dropOff.destinationName,
                    Theme.of(context).colorScheme.onSurface,
                  ),
                  SizedBox(height: isSmallScreen ? 8 : 12),
                  _buildInfoRow(
                    Icons.local_shipping,
                    '${l10n.status}:',
                    deliveryStatus,
                    statusColor,
                  ),
                  SizedBox(height: isSmallScreen ? 12 : 20),
                  if (isTrackable)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.map, color: Colors.white),
                        label: Text(
                          l10n.viewCourierOnLiveMap,
                          style: Theme.of(context).textTheme.labelLarge!.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => Deoaklna(dealId: dealId , watcher: false,),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.primary,
                          padding: EdgeInsets.symmetric(vertical: isSmallScreen ? 14 : 18),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                          elevation: 5,
                        ),
                      ),
                    ),
                  if (!isTrackable)
                    Container(
                      padding: EdgeInsets.symmetric(vertical: isSmallScreen ? 10 : 12, horizontal: 8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceVariant,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.visibility_off, color: Colors.grey[600]),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              l10n.trackingNotAvailable,
                              style: Theme.of(context).textTheme.bodySmall!.copyWith(
                                    color: Colors.grey[600],
                                    fontStyle: FontStyle.italic,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      );
    }
  }

  Widget _buildInfoRow(IconData icon, String label, String value, Color color) {
    return Row(
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 12),
        Text(
          label,
          style: TextStyle(fontSize: 16, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }
}