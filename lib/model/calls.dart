import 'package:cloud_firestore/cloud_firestore.dart';

class Call {
  final String callId; // ID unique du document Firestore (doit être le dealId)
  final String dealId;
  final String driverId;
  final String userId;
  final String callerId;
  final String receiverId;
  final String callStatus; // 'dialing', 'connected', 'ended', 'declined'
  final String agoraChannel;
  final String agoraToken;
  final bool hasVideo;
  final DateTime? timestamp;
   String? callerToken = "";      // ← Token for the client
   String? receiverToken = "";


  Call({
    required this.callId,
    required this.dealId,
    required this.driverId,
    required this.userId,
    required this.callerId,
    required this.receiverId,
    required this.callStatus,
    required this.agoraChannel,
    required this.agoraToken,
    this.hasVideo = false,
    this.timestamp,
  });

  factory Call.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Call(
      callId: doc.id,
      dealId: data['dealId'] ?? '',
      driverId: data['driverId'] ?? '',
      userId: data['userId'] ?? '',
      callerId: data['callerId'] ?? '',
      receiverId: data['receiverId'] ?? '',
      callStatus: data['callStatus'] ?? '',
      agoraChannel: data['agoraChannel'] ?? '',
      agoraToken: data['agoraToken'] ?? '',
      hasVideo: data['hasVideo'] ?? false,
      timestamp: (data['timestamp'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'dealId': dealId,
      'driverId': driverId,
      'userId': userId,
      'callerId': callerId,
      'receiverId': receiverId,
      'callStatus': callStatus,
      'agoraChannel': agoraChannel,
      'agoraToken': agoraToken,
      'hasVideo': hasVideo,
      'timestamp': FieldValue.serverTimestamp(),
    };
  }
}