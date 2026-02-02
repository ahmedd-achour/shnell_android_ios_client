import 'dart:async';
import 'dart:convert';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';

// MUST BE DEFINED IN main.dart AND PASSED TO MaterialApp
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  final String appId = "392d2910e2f34b4a885212cd49edcffa";
  final String cloudFunctionUrl =
      "https://us-central1-shnell-393a6.cloudfunctions.net";


class AgoraService {
   static final AgoraService _instance = AgoraService._internal();
  factory AgoraService() => _instance;
  AgoraService._internal();
  final ValueNotifier<bool> isRemoteVideoActive = ValueNotifier<bool>(false);
  final ValueNotifier<bool> isLocalVideoActive = ValueNotifier<bool>(false);

  RtcEngine? engine; // Keep this accessible


Future<void> toggleLocalVideo() async {
    if (engine == null) return;
    
    bool nextState = !isLocalVideoActive.value;
    
    if (nextState) {
      await engine!.enableVideo();
      await engine!.startPreview();
      await engine!.muteLocalVideoStream(false);
      await engine!.updateChannelMediaOptions(
        const ChannelMediaOptions(publishCameraTrack: true),
      );
    } else {
      await engine!.muteLocalVideoStream(true);
      await engine!.stopPreview();
      await engine!.updateChannelMediaOptions(
        const ChannelMediaOptions(publishCameraTrack: false),
      );
    }
    isLocalVideoActive.value = nextState;
  }
  Future<bool> init({
    required String token,
    required String channel,
    required int uid,
  }) async {

          bool permissions = await requestCallPermissions();
  if(permissions ==false){
    return false;
  }
    engine = createAgoraRtcEngine();

    await engine!.initialize(
      RtcEngineContext(appId: appId),
    );
    // everyone is seen here , any join will be visible to agora forcing it to connect if not , its a miss config on cloud
    engine!.registerEventHandler(

      RtcEngineEventHandler(
        onUserMuteVideo: (connection, remoteUid, muted) {
          isRemoteVideoActive.value = !muted;
        print("Remote user $remoteUid changed video state: $muted");
        // This will allow your UI to react when the other person starts video
      },
        onJoinChannelSuccess: (RtcConnection connection, int elapsed) {
          print("Joined channel");
        },
        onUserJoined: (_, uid, __) {
          isRemoteVideoActive.value = false;
          print("Remote joined: $uid");
        },
        onUserOffline: (_, uid, __) {
          isRemoteVideoActive.value = false;
          print("Remote left: $uid");
        },
      ),
    );

    try{
    await engine!.enableVideo();
      
    }catch(e){
      return false;

    } try{
    await engine!.startPreview();
    }catch(e){
      return false;

    }

    try{
await engine!.joinChannel(
  token: token,
  channelId: channel,
  uid: uid,
  options: ChannelMediaOptions(
    clientRoleType: ClientRoleType.clientRoleBroadcaster,
    publishCameraTrack: false,       // Publish video by default (for video calls)
    publishMicrophoneTrack: true,   // Always publish audio
    autoSubscribeAudio: true,       // Automatically subscribe to remote audio
    autoSubscribeVideo: true,       // Automatically subscribe to remote video
  ),
);
return true;
    }catch(e){
return false;
    }
  
  }

  Future<void> leave() async {
    try{
    await engine?.leaveChannel();

    }catch(e){
      // no chanel to leave
    }
    try{
    await engine?.release();

    }catch(e){
      // engine released
    }
    engine = null;
  }

  Future<bool> requestCallPermissions() async {
  // 1. Request multiple permissions correctly (OS handles the sequence)
  Map<Permission, PermissionStatus> statuses = await [
    Permission.microphone,
    Permission.camera,
  ].request();

  // 2. Map results (request() returns a Map, not a List)
  final micStatus = statuses[Permission.microphone];
  final camStatus = statuses[Permission.camera];

  // 3. Robust check: Ensure BOTH are granted
  if (micStatus?.isGranted == true && camStatus?.isGranted == true) {
    return true; 
  }

  // 4. Handle Permanent Denial (The User clicked "Never ask again")
  if (micStatus?.isPermanentlyDenied == true || camStatus?.isPermanentlyDenied == true) {
    // If you return null here, the user is stuck forever. 
    // Usually, you'd show a dialog or open settings.
    await openAppSettings();
  }

  return false;
}

  Future<Map<String, dynamic>?> initiateCall({
    required String receiverId,
    required String receiverFCMToken,
    required String sessionId,
    required String callerName,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception("User not authenticated");
    }

    final myId = user.uid;

    try {
          bool permissions = await requestCallPermissions();
  if(permissions ==false){
    return null;
  }

final results = await Future.wait([
  user.getIdToken(),
  FirebaseMessaging.instance.getToken(),
]);

final String idToken = results[0] as String;
final String? myFCMToken = results[1];

      final response = await http.post(
        Uri.parse("$cloudFunctionUrl/initiateCall"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          'receiverFCMToken': receiverFCMToken,
          'dealId': sessionId,
          'callerName': callerName,
          'callerFirebaseUid': myId,
          'receiverFirebaseUid': receiverId,
          'idToken': idToken,
          'callerFCMToken': myFCMToken,
        }),
      );

      if (response.statusCode != 200) {
        return null;
      }

      final data = jsonDecode(response.body);
      if (!data['success']) {
        return null;
      }
      final String token = data['callerToken'] ?? data['agoraToken'];
      final String channel = data['agoraChannel'];
      final int callerUid = data['callerUid'];
      // before any ui updates we will make init of our own resources on agora , backend before front end for now , we will try to inhase perforrmance later 
      // now caller is garanteed to be joined , all cleaned up
      await init(token: token, channel: channel, uid: callerUid);
      // data are registred by the function on the cloud
     /* await FirebaseFirestore.instance.collection('calls').doc(sessionId).set({
        'callerId': myId,
        'receiverId': receiverId,
        'callStatus': 'ringing',
        'sessionId': sessionId,
        'agoraChannel': channel,
        'agoraToken': token,
        'callerUid': callerUid,
        'receiverUid': data['receiverUid'],
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));*/
      return {
        'token': token,
        'channel': channel,
        'uid': callerUid,
        'receiverUid': data['receiverUid'],
      };
    } catch (e) {
      rethrow;
    }
  }


  Future<void> endCall({required String callId, required String callerFCMToken , required String receiverFCMToken}) async {
    try{
      await FlutterCallkitIncoming.endAllCalls(); // get rid of any callkit just in case

    }catch(e){

    }
   /*   final currentcalldoc = await FirebaseFirestore.instance.collection('calls').doc(callId).get();
      final currentCallStatus = currentcalldoc['callStatus'];
      if(currentCallStatus=='ended'){
        // if call is ended we dont apply a cloud call , if its semi endd its a ended_will 
        return;
      } */
      await leave();

     /* unawaited(
        http.post(
              Uri.parse("$cloudFunctionUrl/terminateCall"),
              headers: {"Content-Type": "application/json"},
              body: jsonEncode({
                "dealId": callId,
                "receiverFCMToken": receiverFCMToken,
                "callerFCMToken" : callerFCMToken
              }),
            )); */// this code will be hard asigned , becose on ending call we dont wanna enter a infinite loop
    }
  }


