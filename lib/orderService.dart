import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';
import 'package:shnell/model/oredrs.dart';

class OrderService {
  final CollectionReference _ordersCollection =
      FirebaseFirestore.instance.collection('orders');

  /// Upload a new order
  Future<String> addOrder(Orders order) async {
    try {
      DocumentReference docRef = await _ordersCollection.add(order.toJson());
      _ordersCollection.doc(docRef.id).update({'id': docRef.id});// update the document with its own ID
      return docRef.id; // return generated document ID
    } catch (e) {
      throw Exception('Failed to add order: $e');
    }
  }

  /// Update an existing order by document ID
  Future<void> updateOrder(String orderId, Orders updatedOrder) async {
    try {
      await _ordersCollection.doc(orderId).update(updatedOrder.toJson());
    } catch (e) {
      throw Exception('Failed to update order: $e');
    }
  }

  /// Delete an order by document ID
  Future<void> deleteOrder(String orderId) async {
    try {
      await _ordersCollection.doc(orderId).delete();
    } catch (e) {
      throw Exception('Failed to delete order: $e');
    }
  }

  /// Fetch an order by ID
  Future<Orders?> getOrderById(String orderId) async {
    try {
      DocumentSnapshot doc = await _ordersCollection.doc(orderId).get();
      if (doc.exists) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;

        // Parse pickup location
        Map<String, dynamic> pickUpData = data['pickUpLocation'];
        LatLng pickUpLoc = LatLng(
          pickUpData['coordinates'][1],
          pickUpData['coordinates'][0],
        );

        // Parse drop-off locations


        return Orders(
          userId: data['userID'],
          price: (data['price'] as num).toDouble(),
          distance: (data['distance'] as num).toDouble(),
          namePickUp: data['namePickUp'],
          pickUpLocation: pickUpLoc,
          stops: data['stops'],
          vehicleType: data['vehicleType'],
          isAcepted: data['isAcepted'] ?? false,
          additionalInfo: data['additionalInfo'],
          id: data['id'],
        );
      }
      return null;
    } catch (e) {
      throw Exception('Failed to fetch order: $e');
    }
  }
}