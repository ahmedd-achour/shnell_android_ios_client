import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shnell/Home.dart'; // Your map/create screen
import 'package:shnell/pending.dart'; // Waiting screen
import 'package:shnell/trackDriver.dart'; // Tracking screen
import 'package:shnell/dots.dart';
import 'package:shnell/drawer.dart';

class SingleBookingScreen extends StatelessWidget {
  const SingleBookingScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const ShnellMAp(); // or login screen
    }


    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        automaticallyImplyLeading: false, // ← THIS IS THE KEY FIX
        backgroundColor: Colors.transparent,
      
        flexibleSpace: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                Builder(
                  builder: (context) => ClipOval(
                    child: Material(
                      child: InkWell(
                        onTap: () => Scaffold.of(context).openDrawer(),
                        child:  SizedBox(
                          width: 50,
                          height: 50,
                          child: Icon(Icons.menu, size: 28 ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      drawer: const ShnellDrawer(),

      body: StreamBuilder<QuerySnapshot>(
        // First: Check for any ACTIVE (accepted/almost) deal
        stream: FirebaseFirestore.instance
            .collection('deals')
            .where('idUser', isEqualTo: user.uid)
            .where('status', whereIn: ['accepted', 'almost'])
            .limit(1)
            .snapshots(),
        builder: (context, activeDealSnapshot) {
          if (activeDealSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: RotatingDotsIndicator());
          }

          if (activeDealSnapshot.hasData && activeDealSnapshot.data!.docs.isNotEmpty) {
            final dealDoc = activeDealSnapshot.data!.docs.first;
            return Deoaklna(dealId: dealDoc.id); // Track Driver Screen
          }

          // No active deal → check for pending orders
          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('orders')
                .where('userID', isEqualTo: user.uid)
                .where('isAcepted', isEqualTo: false)
                .limit(1)
                .snapshots(),
            builder: (context, pendingOrderSnapshot) {
              if (pendingOrderSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: RotatingDotsIndicator());
              }

              if (pendingOrderSnapshot.hasData && pendingOrderSnapshot.data!.docs.isNotEmpty) {
                final orderDoc = pendingOrderSnapshot.data!.docs.first;
                return PendingOrderWidget(orderId: orderDoc.id); // Waiting screen
              }

              // No pending order and no active deal → allow creating new
              return const ShnellMAp(); // Create booking map screen
            },
          );
        },
      ),
    );
  }
}