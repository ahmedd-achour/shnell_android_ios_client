import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shnell/Home.dart';
import 'package:shnell/dots.dart'; // Assuming this is your custom loading indicator
import 'package:shnell/drawer.dart';
import 'package:shnell/pending.dart';
import 'package:shnell/trackDriver.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class MultipleTrackingScreen extends StatefulWidget {
  const MultipleTrackingScreen({Key? key}) : super(key: key);

  @override
  _MultipleTrackingScreenState createState() => _MultipleTrackingScreenState();
}

class _MultipleTrackingScreenState extends State<MultipleTrackingScreen>
    with TickerProviderStateMixin {
  TabController? _tabController;
  final List<Tab> _tabs = [];
  final List<Widget> _tabViews = [];

  // Data to hold from the streams
  List<DocumentSnapshot>? _deals;
  List<DocumentSnapshot>? _orders;

  @override
  void initState() {
    super.initState();
    // No ne
    //ed to initialize TabController here
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  // A helper method to build the main content once data is loaded
  Widget _buildContent() {
    _tabs.clear();
    _tabViews.clear();
    final l10n = AppLocalizations.of(context)!;

    _tabs.add(Tab(
      icon: const Icon(Icons.add_circle_outline),
      text: l10n.create,
    ));
    _tabViews.add(const ShnellMAp());

    for (var deal in _deals!) {
      _tabs.add(Tab(
        icon: const Icon(Icons.local_shipping),
        text: l10n.delivery,
      ));
      _tabViews.add(Deoaklna(dealId: deal.id));
    }

    for (var order in _orders!) {
      _tabs.add(Tab(
        icon: const Icon(Icons.hourglass_empty),
        text: l10n.pending,
      ));
      _tabViews.add(PendingOrderWidget(orderId: order.id));
    }

    // Dispose the old controller before creating a new one
    _tabController?.dispose();
    _tabController = TabController(length: _tabs.length, vsync: this);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        toolbarHeight: 80,
        leading: const SizedBox(),
        leadingWidth: 0,
        flexibleSpace: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Builder(
                  builder: (context) {
                    return ClipOval(
                      child: Material(
                        child: InkWell(
                          onTap: () => Scaffold.of(context).openDrawer(),
                          child:  SizedBox(
                            width: 50,
                            height: 50,
                            child: Icon(Icons.menu, color:Theme.of(context).colorScheme.primary, size: 28),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 16),
                if(_tabs.length>1)
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5.0),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(30),
                      color: Theme.of(context).colorScheme.surface
                    ),
                    child: TabBar(
                      controller: _tabController,
                      isScrollable: true,
                      labelColor: Theme.of(context).colorScheme.primary,
                      labelPadding: const EdgeInsets.symmetric(horizontal: 10.0),
                      indicator:  UnderlineTabIndicator(
                        borderSide: BorderSide(
                          color: Theme.of(context).colorScheme.primary,
                          width: 3.0,
                        ),
                        insets: EdgeInsets.only(bottom: 4),
                      ),
                      tabs: _tabs,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      drawer: const ShnellDrawer(),
      body: TabBarView(
        controller: _tabController,
        physics: const NeverScrollableScrollPhysics(),
        children: _tabViews,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const ShnellMAp();
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('deals')
          .where('idUser', isEqualTo: user.uid)
          .where('status', whereIn: ['accepted', 'almost'])
          .snapshots(),
      builder: (context, dealsSnapshot) {
        if (dealsSnapshot.connectionState == ConnectionState.waiting) {
          // Show the loading indicator only while waiting for the initial data
          return const Scaffold(body: Center(child: RotatingDotsIndicator()));
        }

        if (dealsSnapshot.hasError) {
          return Center(child: Text('Error loading deals: ${dealsSnapshot.error}'));
        }

        // Store the deals data
        _deals = dealsSnapshot.data!.docs;

        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('orders')
              .where('userID', isEqualTo: user.uid)
              .where('isAcepted', isEqualTo: false)
              .snapshots(),
          builder: (context, ordersSnapshot) {
            if (ordersSnapshot.connectionState == ConnectionState.waiting) {
              // Show the loading indicator only while waiting for the initial data
              return const Scaffold(body: Center(child: RotatingDotsIndicator()));
            }

            if (ordersSnapshot.hasError) {
              return Center(child: Text('Error loading orders: ${ordersSnapshot.error}'));
            }

            // Store the orders data
            _orders = ordersSnapshot.data!.docs;

            // Now that both streams have loaded, build the content
            return _buildContent();
          },
        );
      },
    );
  }
}