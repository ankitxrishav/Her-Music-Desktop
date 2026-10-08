import 'dart:convert';
import 'dart:io';

import 'couple_models.dart';

class FirebaseCoupleSync {
  static const String defaultBaseUrl = 'https://her-music-53197-default-rtdb.firebaseio.com';
  static const String relayBaseUrl = 'https://ntfy.sh';
  static const String projectTag = 'her_sync_53197';

  static final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 5);

  static String calculateSpaceId(String codeA, String codeB) {
    final a = codeA.trim().toUpperCase();
    final b = codeB.trim().toUpperCase();
    final list = [a, b]..sort();
    return list.join('-');
  }

  static Future<bool> publishRelay(String topicSuffix, String payload) async {
    try {
      final cleanTopic = '${projectTag}_${topicSuffix.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')}';
      final uri = Uri.parse('$relayBaseUrl/$cleanTopic');
      final request = await _client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      request.write(payload);
      final response = await request.close();
      await response.drain();
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  static Future<List<String>> pollRelay(String topicSuffix, {bool sinceAll = false}) async {
    try {
      final cleanTopic = '${projectTag}_${topicSuffix.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')}';
      final uri = Uri.parse('$relayBaseUrl/$cleanTopic/json?poll=1${sinceAll ? '&since=all' : ''}');
      final request = await _client.getUrl(uri);
      final response = await request.close();
      if (response.statusCode != 200) {
        await response.drain();
        return const [];
      }
      final body = await utf8.decoder.bind(response).join();
      final lines = const LineSplitter().convert(body);
      final messages = <String>[];
      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        try {
          final json = jsonDecode(line) as Map<String, dynamic>;
          if (json['event'] == 'message' && json['message'] != null) {
            messages.add(json['message'] as String);
          }
        } catch (_) {}
      }
      return messages;
    } catch (_) {
      return const [];
    }
  }

  static Future<void> _putFirebase(String path, String payload, {String? customUrl}) async {
    try {
      final base = (customUrl?.trim().isNotEmpty ?? false) ? customUrl!.trim() : defaultBaseUrl;
      final uri = Uri.parse('$base/$path.json');
      final request = await _client.putUrl(uri);
      request.headers.contentType = ContentType.json;
      request.write(payload);
      final response = await request.close();
      await response.drain();
    } catch (_) {}
  }

  static Future<dynamic> _getFirebase(String path, {String? customUrl}) async {
    try {
      final base = (customUrl?.trim().isNotEmpty ?? false) ? customUrl!.trim() : defaultBaseUrl;
      final uri = Uri.parse('$base/$path.json');
      final request = await _client.getUrl(uri);
      final response = await request.close();
      if (response.statusCode != 200) {
        await response.drain();
        return null;
      }
      final body = await utf8.decoder.bind(response).join();
      if (body.isEmpty || body == 'null') return null;
      return jsonDecode(body);
    } catch (_) {
      return null;
    }
  }

  static Future<bool> registerInvite({
    required String code,
    required String role,
    required String name,
    String? customUrl,
  }) async {
    if (code.trim().isEmpty) return false;
    try {
      final invite = CoupleInvite(
        code: code,
        role: role,
        name: name,
        matched: false,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );
      final payload = jsonEncode(invite.toJson());
      await publishRelay('inv_$code', payload);
      await _putFirebase('invites/$code', payload, customUrl: customUrl);
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<CoupleInvite?> checkInviteMatch(String code, {String? customUrl}) async {
    if (code.trim().isEmpty) return null;
    try {
      final fb = await _getFirebase('invites/$code', customUrl: customUrl);
      if (fb is Map<String, dynamic>) {
        final inv = CoupleInvite.fromJson(fb);
        if (inv.matched && inv.spaceId.isNotEmpty) return inv;
      }
      final relayMsgs = await pollRelay('inv_$code');
      for (final msg in relayMsgs.reversed) {
        try {
          final parsed = jsonDecode(msg) as Map<String, dynamic>;
          final inv = CoupleInvite.fromJson(parsed);
          if (inv.matched && inv.spaceId.isNotEmpty) return inv;
        } catch (_) {}
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<bool> linkInvite({
    required String partnerCode,
    required String myCode,
    required String myRole,
    required String myName,
    String? customUrl,
  }) async {
    if (partnerCode.trim().isEmpty || myCode.trim().isEmpty) return false;
    try {
      final space = calculateSpaceId(myCode, partnerCode);
      final now = DateTime.now().millisecondsSinceEpoch;

      final partnerUpdate = CoupleInvite(
        code: partnerCode,
        matched: true,
        partnerCode: myCode,
        partnerName: myName,
        partnerRole: myRole,
        spaceId: space,
        timestamp: now,
      );
      final partnerJson = jsonEncode(partnerUpdate.toJson());
      await publishRelay('inv_$partnerCode', partnerJson);
      await _putFirebase('invites/$partnerCode', partnerJson, customUrl: customUrl);

      final myUpdate = CoupleInvite(
        code: myCode,
        role: myRole,
        name: myName,
        matched: true,
        partnerCode: partnerCode,
        spaceId: space,
        timestamp: now,
      );
      final myJson = jsonEncode(myUpdate.toJson());
      await publishRelay('inv_$myCode', myJson);
      await _putFirebase('invites/$myCode', myJson, customUrl: customUrl);

      final spaceInfo = jsonEncode({'spaceId': space, 'createdAt': now});
      await publishRelay('spc_${space}_info', spaceInfo);
      await _putFirebase('spaces/$space/info', spaceInfo, customUrl: customUrl);

      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> broadcastLivePlayback(
    String spaceId,
    CoupleLivePlayback playback, {
    String? customUrl,
  }) async {
    if (spaceId.trim().isEmpty) return false;
    try {
      final roleKey = playback.senderRole.toLowerCase();
      final payload = jsonEncode(playback.toJson());
      await publishRelay('spc_${spaceId}_pb_$roleKey', payload);
      await _putFirebase('spaces/$spaceId/playback_$roleKey', payload, customUrl: customUrl);
      await _putFirebase('spaces/$spaceId/live_playback', payload, customUrl: customUrl);
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<CoupleLivePlayback?> fetchPartnerLivePlayback(
    String spaceId,
    String partnerRole, {
    String? customUrl,
  }) async {
    if (spaceId.trim().isEmpty) return null;
    try {
      final roleKey = partnerRole.toLowerCase();
      final fb = await _getFirebase('spaces/$spaceId/playback_$roleKey', customUrl: customUrl);
      if (fb is Map<String, dynamic>) {
        return CoupleLivePlayback.fromJson(fb);
      }
      final msgs = await pollRelay('spc_${spaceId}_pb_$roleKey');
      if (msgs.isNotEmpty) {
        try {
          final parsed = jsonDecode(msgs.last) as Map<String, dynamic>;
          return CoupleLivePlayback.fromJson(parsed);
        } catch (_) {}
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<bool> sendChatMessage(
    String spaceId,
    CoupleChatMessage message, {
    String? customUrl,
  }) async {
    if (spaceId.trim().isEmpty) return false;
    try {
      final payload = jsonEncode(message.toJson());
      await publishRelay('spc_${spaceId}_chat', payload);
      await _putFirebase('spaces/$spaceId/messages/${message.id}', payload, customUrl: customUrl);
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<List<CoupleChatMessage>> fetchChatMessages(
    String spaceId, {
    String? customUrl,
  }) async {
    if (spaceId.trim().isEmpty) return const [];
    final map = <String, CoupleChatMessage>{};
    try {
      final fb = await _getFirebase('spaces/$spaceId/messages', customUrl: customUrl);
      if (fb is Map<String, dynamic>) {
        fb.forEach((key, val) {
          if (val is Map<String, dynamic>) {
            try {
              final msg = CoupleChatMessage.fromJson(val);
              map[msg.id] = msg;
            } catch (_) {}
          }
        });
      }

      final relayMsgs = await pollRelay('spc_${spaceId}_chat', sinceAll: true);
      for (final line in relayMsgs) {
        try {
          final parsed = jsonDecode(line) as Map<String, dynamic>;
          final msg = CoupleChatMessage.fromJson(parsed);
          map[msg.id] = msg;
        } catch (_) {}
      }

      final list = map.values.toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      return list;
    } catch (_) {
      return map.values.toList();
    }
  }

  static Future<bool> pushSong(
    String spaceId,
    CouplePushSong song, {
    String? customUrl,
  }) async {
    if (spaceId.trim().isEmpty) return false;
    try {
      final payload = jsonEncode(song.toJson());
      await publishRelay('spc_${spaceId}_push', payload);
      await _putFirebase('spaces/$spaceId/push_song', payload, customUrl: customUrl);
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<CouplePushSong?> fetchLatestPushSong(
    String spaceId, {
    String? customUrl,
  }) async {
    if (spaceId.trim().isEmpty) return null;
    try {
      final fb = await _getFirebase('spaces/$spaceId/push_song', customUrl: customUrl);
      if (fb is Map<String, dynamic>) {
        return CouplePushSong.fromJson(fb);
      }
      final msgs = await pollRelay('spc_${spaceId}_push');
      if (msgs.isNotEmpty) {
        try {
          final parsed = jsonDecode(msgs.last) as Map<String, dynamic>;
          return CouplePushSong.fromJson(parsed);
        } catch (_) {}
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
