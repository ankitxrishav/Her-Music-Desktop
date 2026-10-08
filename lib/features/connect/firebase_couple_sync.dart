import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

import 'couple_models.dart';

class FirebaseCoupleSync {
  static const List<String> brokers = [
    'broker.emqx.io',
    'broker.hivemq.com',
    'test.mosquitto.org',
  ];

  static MqttServerClient? _client;
  static bool _connecting = false;
  static int _brokerIndex = 0;

  static final Map<String, CoupleInvite> _invitesCache = {};
  static final Map<String, CoupleLivePlayback> _liveCache = {};
  static final Map<String, CouplePushSong> _pushCache = {};
  static final Map<String, List<CoupleChatMessage>> _chatCache = {};
  static final Map<String, DeviceSyncPayload> _deviceCache = {};

  static final StreamController<CoupleLivePlayback> _liveStream =
      StreamController<CoupleLivePlayback>.broadcast();
  static final StreamController<CouplePushSong> _pushStream =
      StreamController<CouplePushSong>.broadcast();
  static final StreamController<CoupleChatMessage> _chatStream =
      StreamController<CoupleChatMessage>.broadcast();
  static final StreamController<CoupleInvite> _inviteStream =
      StreamController<CoupleInvite>.broadcast();
  static final StreamController<DeviceSyncPayload> _deviceStream =
      StreamController<DeviceSyncPayload>.broadcast();

  static Stream<CoupleLivePlayback> get liveStream => _liveStream.stream;
  static Stream<CouplePushSong> get pushStream => _pushStream.stream;
  static Stream<CoupleChatMessage> get chatStream => _chatStream.stream;
  static Stream<CoupleInvite> get inviteStream => _inviteStream.stream;
  static Stream<DeviceSyncPayload> get deviceStream => _deviceStream.stream;

  static final Set<String> _subscribedTopics = {};

  static String hashEmail(String email) {
    final clean = email.trim().toLowerCase();
    if (clean.isEmpty) return '';
    final bytes = utf8.encode(clean);
    return sha256.convert(bytes).toString().substring(0, 16);
  }

  static String calculateSpaceId(String codeA, String codeB) {
    final a = codeA.trim().toUpperCase();
    final b = codeB.trim().toUpperCase();
    final list = [a, b]..sort();
    return list.join('-');
  }

  static String calculateEmailSpaceId(String emailA, String emailB) {
    final a = hashEmail(emailA);
    final b = hashEmail(emailB);
    if (a.isEmpty || b.isEmpty) return '';
    final list = [a, b]..sort();
    return 'couple_${list.join("_")}';
  }

  static Future<bool> ensureConnected() async {
    if (_client?.connectionStatus?.state == MqttConnectionState.connected) {
      return true;
    }
    if (_connecting) {
      for (var i = 0; i < 20; i++) {
        await Future.delayed(const Duration(milliseconds: 150));
        if (_client?.connectionStatus?.state == MqttConnectionState.connected) {
          return true;
        }
      }
    }
    _connecting = true;
    try {
      final host = brokers[_brokerIndex % brokers.length];
      final clientId = 'her_desktop_${Platform.operatingSystem}_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}';
      final client = MqttServerClient(host, clientId);
      client.port = 1883;
      client.keepAlivePeriod = 30;
      client.autoReconnect = true;
      client.logging(on: false);

      client.onDisconnected = () {
        _subscribedTopics.clear();
      };

      final status = await client.connect();
      if (status?.state == MqttConnectionState.connected) {
        _client = client;
        _listenToUpdates(client);
        _resubscribeAll();
        _connecting = false;
        return true;
      }
    } catch (_) {
      _brokerIndex++;
    }
    _connecting = false;
    return false;
  }

  static void _resubscribeAll() {
    final topics = Set<String>.from(_subscribedTopics);
    _subscribedTopics.clear();
    for (final topic in topics) {
      subscribe(topic);
    }
  }

  static void _listenToUpdates(MqttServerClient client) {
    client.updates?.listen((List<MqttReceivedMessage<MqttMessage>> messages) {
      for (final msg in messages) {
        try {
          final pub = msg.payload as MqttPublishMessage;
          final topic = msg.topic;
          final payload = MqttPublishPayload.bytesToStringAsString(pub.payload.message);
          _handleIncoming(topic, payload);
        } catch (_) {}
      }
    });
  }

  static void _handleIncoming(String topic, String payload) {
    if (payload.trim().isEmpty) return;
    try {
      final json = jsonDecode(payload) as Map<String, dynamic>;
      if (topic.startsWith('her_music/space/') && topic.endsWith('/live')) {
        final live = CoupleLivePlayback.fromJson(json);
        final spaceId = topic.split('/')[2];
        _liveCache['${spaceId}_${live.senderRole.toLowerCase()}'] = live;
        _liveStream.add(live);
      } else if (topic.startsWith('her_music/space/') && topic.endsWith('/push')) {
        final push = CouplePushSong.fromJson(json);
        final spaceId = topic.split('/')[2];
        _pushCache[spaceId] = push;
        _pushStream.add(push);
      } else if (topic.startsWith('her_music/space/') && topic.endsWith('/chat')) {
        final chat = CoupleChatMessage.fromJson(json);
        final spaceId = topic.split('/')[2];
        final list = _chatCache[spaceId] ?? <CoupleChatMessage>[];
        if (!list.any((m) => m.id == chat.id)) {
          list.add(chat);
          _chatCache[spaceId] = list;
          _chatStream.add(chat);
        }
      } else if (topic.startsWith('her_music/invite/')) {
        final inv = CoupleInvite.fromJson(json);
        final code = topic.split('/').last;
        _invitesCache[code] = inv;
        _inviteStream.add(inv);
      } else if (topic.startsWith('her_music/user/') && topic.endsWith('/device_sync')) {
        final dev = DeviceSyncPayload.fromJson(json);
        _deviceCache[dev.email] = dev;
        _deviceStream.add(dev);
      }
    } catch (_) {}
  }

  static void subscribe(String topic) {
    if (_subscribedTopics.contains(topic)) return;
    _subscribedTopics.add(topic);
    if (_client?.connectionStatus?.state == MqttConnectionState.connected) {
      _client?.subscribe(topic, MqttQos.atLeastOnce);
    } else {
      ensureConnected().then((ok) {
        if (ok) _client?.subscribe(topic, MqttQos.atLeastOnce);
      });
    }
  }

  static Future<bool> publish(String topic, String payload, {bool retain = false}) async {
    final ok = await ensureConnected();
    if (!ok || _client == null) return false;
    try {
      final builder = MqttClientPayloadBuilder();
      builder.addString(payload);
      _client!.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!, retain: retain);
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> testConnection() async {
    return await ensureConnected();
  }

  static Future<bool> registerInvite({
    required String code,
    required String role,
    required String name,
    String? customUrl,
  }) async {
    final clean = code.trim().toUpperCase();
    if (clean.isEmpty) return false;
    subscribe('her_music/invite/$clean');
    final invite = CoupleInvite(
      code: clean,
      role: role,
      name: name,
      matched: false,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
    _invitesCache[clean] = invite;
    return await publish('her_music/invite/$clean', jsonEncode(invite.toJson()), retain: true);
  }

  static Future<CoupleInvite?> checkInviteMatch(String code, {String? customUrl}) async {
    final clean = code.trim().toUpperCase();
    if (clean.isEmpty) return null;
    subscribe('her_music/invite/$clean');
    final inv = _invitesCache[clean];
    if (inv != null && inv.matched && inv.spaceId.isNotEmpty) {
      return inv;
    }
    return null;
  }

  static Future<bool> linkInvite({
    required String partnerCode,
    required String myCode,
    required String myRole,
    required String myName,
    String? customUrl,
  }) async {
    final pCode = partnerCode.trim().toUpperCase();
    final mCode = myCode.trim().toUpperCase();
    if (pCode.isEmpty || mCode.isEmpty) return false;

    final space = calculateSpaceId(mCode, pCode);
    final now = DateTime.now().millisecondsSinceEpoch;

    final partnerUpdate = CoupleInvite(
      code: pCode,
      matched: true,
      partnerCode: mCode,
      partnerName: myName,
      partnerRole: myRole,
      spaceId: space,
      timestamp: now,
    );
    _invitesCache[pCode] = partnerUpdate;
    await publish('her_music/invite/$pCode', jsonEncode(partnerUpdate.toJson()), retain: true);

    final myUpdate = CoupleInvite(
      code: mCode,
      role: myRole,
      name: myName,
      matched: true,
      partnerCode: pCode,
      partnerRole: pCode.startsWith('HER') ? 'HER' : 'HIM',
      spaceId: space,
      timestamp: now,
    );
    _invitesCache[mCode] = myUpdate;
    await publish('her_music/invite/$mCode', jsonEncode(myUpdate.toJson()), retain: true);
    return true;
  }

  static Future<bool> broadcastLivePlayback(
    String spaceId,
    CoupleLivePlayback playback, {
    String? customUrl,
  }) async {
    final clean = spaceId.trim();
    if (clean.isEmpty) return false;
    final topic = 'her_music/space/$clean/live';
    subscribe(topic);
    _liveCache['${clean}_${playback.senderRole.toLowerCase()}'] = playback;
    return await publish(topic, jsonEncode(playback.toJson()), retain: true);
  }

  static Future<CoupleLivePlayback?> fetchPartnerLivePlayback(
    String spaceId,
    String partnerRole, {
    String? customUrl,
  }) async {
    final clean = spaceId.trim();
    if (clean.isEmpty) return null;
    final topic = 'her_music/space/$clean/live';
    subscribe(topic);
    return _liveCache['${clean}_${partnerRole.toLowerCase()}'];
  }

  static Future<bool> sendChatMessage(
    String spaceId,
    CoupleChatMessage message, {
    String? customUrl,
  }) async {
    final clean = spaceId.trim();
    if (clean.isEmpty) return false;
    final topic = 'her_music/space/$clean/chat';
    subscribe(topic);
    final list = _chatCache[clean] ?? <CoupleChatMessage>[];
    if (!list.any((m) => m.id == message.id)) {
      list.add(message);
      _chatCache[clean] = list;
    }
    return await publish(topic, jsonEncode(message.toJson()));
  }

  static Future<List<CoupleChatMessage>> fetchChatMessages(
    String spaceId, {
    String? customUrl,
  }) async {
    final clean = spaceId.trim();
    if (clean.isEmpty) return const [];
    final topic = 'her_music/space/$clean/chat';
    subscribe(topic);
    return _chatCache[clean] ?? const [];
  }

  static Future<bool> pushSong(
    String spaceId,
    CouplePushSong song, {
    String? customUrl,
  }) async {
    final clean = spaceId.trim();
    if (clean.isEmpty) return false;
    final topic = 'her_music/space/$clean/push';
    subscribe(topic);
    _pushCache[clean] = song;
    return await publish(topic, jsonEncode(song.toJson()), retain: true);
  }

  static Future<CouplePushSong?> fetchLatestPushSong(
    String spaceId, {
    String? customUrl,
  }) async {
    final clean = spaceId.trim();
    if (clean.isEmpty) return null;
    final topic = 'her_music/space/$clean/push';
    subscribe(topic);
    return _pushCache[clean];
  }

  static Future<bool> broadcastDeviceSync(DeviceSyncPayload payload) async {
    if (payload.email.trim().isEmpty) return false;
    final hash = hashEmail(payload.email);
    final topic = 'her_music/user/$hash/device_sync';
    subscribe(topic);
    _deviceCache[payload.email] = payload;
    return await publish(topic, jsonEncode(payload.toJson()), retain: true);
  }

  static void subscribeDeviceSync(String email) {
    if (email.trim().isEmpty) return;
    final hash = hashEmail(email);
    subscribe('her_music/user/$hash/device_sync');
  }

  static DeviceSyncPayload? getLatestDeviceSync(String email) {
    return _deviceCache[email];
  }
}
