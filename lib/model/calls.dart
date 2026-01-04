import 'package:cloud_firestore/cloud_firestore.dart';

class CallModel {
  final String dealId;
  final String callStatus;
  final String callerName;
  final String agoraChannel;
  final int callerUid;
  final int receiverUid;
  final String callerFirebaseUid;
  final String receiverFirebaseUid;
  final DateTime? createdAt;
  final String callerToken;
  final String receiverToken;
  final String callerFCMToken;
  final String receiverFCMToken;

  CallModel({
    required this.dealId,
    required this.callStatus,
    required this.callerName,
    required this.agoraChannel,
    required this.callerUid,
    required this.receiverUid,
    required this.callerFirebaseUid,
    required this.receiverFirebaseUid,
    this.createdAt,
    required this.callerToken,
    required this.receiverToken,
    required this.callerFCMToken,
    required this.receiverFCMToken,
  });

  // Convert a Map (from Firestore or Cloud Function) into a CallModel object
  factory CallModel.fromMap(Map<String, dynamic> map) {
    return CallModel(
      dealId: map['dealId'] ?? '',
      callStatus: map['callStatus'] ?? 'ringing',
      callerName: map['callerName'] ?? 'Shnell',
      agoraChannel: map['agoraChannel'] ?? '',
      callerUid: map['callerUid'] is int ? map['callerUid'] : int.parse(map['callerUid'].toString()),
      receiverUid: map['receiverUid'] is int ? map['receiverUid'] : int.parse(map['receiverUid'].toString()),
      callerFirebaseUid: map['callerFirebaseUid'] ?? '',
      receiverFirebaseUid: map['receiverFirebaseUid'] ?? '',
      createdAt: (map['createdAt'] as Timestamp?)?.toDate(),
      callerToken: map['callerToken'] ?? '',
      receiverToken: map['receiverToken'] ?? '',
      callerFCMToken: map['callerFCMToken'] ?? '',
      receiverFCMToken: map['receiverFCMToken'] ?? '',
    );
  }

  // Convert the CallModel object into a Map for Firestore
  Map<String, dynamic> toMap() {
    return {
      'dealId': dealId,
      'callStatus': callStatus,
      'callerName': callerName,
      'agoraChannel': agoraChannel,
      'callerUid': callerUid,
      'receiverUid': receiverUid,
      'callerFirebaseUid': callerFirebaseUid,
      'receiverFirebaseUid': receiverFirebaseUid,
      'createdAt': createdAt ?? FieldValue.serverTimestamp(),
      'callerToken': callerToken,
      'receiverToken': receiverToken,
      'callerFCMToken': callerFCMToken,
      'receiverFCMToken': receiverFCMToken,
    };
  }
}