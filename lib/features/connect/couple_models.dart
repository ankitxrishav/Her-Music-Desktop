class CoupleInvite {
  final String code;
  final String role;
  final String name;
  final bool matched;
  final String partnerCode;
  final String partnerName;
  final String partnerRole;
  final String spaceId;
  final int timestamp;

  const CoupleInvite({
    this.code = '',
    this.role = '',
    this.name = '',
    this.matched = false,
    this.partnerCode = '',
    this.partnerName = '',
    this.partnerRole = '',
    this.spaceId = '',
    this.timestamp = 0,
  });

  factory CoupleInvite.fromJson(Map<String, dynamic> json) {
    return CoupleInvite(
      code: json['code'] as String? ?? '',
      role: json['role'] as String? ?? '',
      name: json['name'] as String? ?? '',
      matched: json['matched'] as bool? ?? false,
      partnerCode: json['partnerCode'] as String? ?? '',
      partnerName: json['partnerName'] as String? ?? '',
      partnerRole: json['partnerRole'] as String? ?? '',
      spaceId: json['spaceId'] as String? ?? '',
      timestamp: (json['timestamp'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'code': code,
    'role': role,
    'name': name,
    'matched': matched,
    'partnerCode': partnerCode,
    'partnerName': partnerName,
    'partnerRole': partnerRole,
    'spaceId': spaceId,
    'timestamp': timestamp,
  };
}

class CoupleLivePlayback {
  final String songId;
  final String title;
  final String artist;
  final String? thumbnailUrl;
  final bool isPlaying;
  final int positionMs;
  final int durationMs;
  final int timestampEpochMs;
  final String senderRole;
  final String senderName;

  const CoupleLivePlayback({
    this.songId = '',
    this.title = '',
    this.artist = '',
    this.thumbnailUrl,
    this.isPlaying = false,
    this.positionMs = 0,
    this.durationMs = 0,
    this.timestampEpochMs = 0,
    this.senderRole = '',
    this.senderName = '',
  });

  factory CoupleLivePlayback.fromJson(Map<String, dynamic> json) {
    return CoupleLivePlayback(
      songId: json['songId'] as String? ?? '',
      title: json['title'] as String? ?? '',
      artist: json['artist'] as String? ?? '',
      thumbnailUrl: json['thumbnailUrl'] as String?,
      isPlaying: json['isPlaying'] as bool? ?? false,
      positionMs: (json['positionMs'] as num?)?.toInt() ?? 0,
      durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
      timestampEpochMs: (json['timestampEpochMs'] as num?)?.toInt() ?? 0,
      senderRole: json['senderRole'] as String? ?? '',
      senderName: json['senderName'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'songId': songId,
    'title': title,
    'artist': artist,
    if (thumbnailUrl != null) 'thumbnailUrl': thumbnailUrl,
    'isPlaying': isPlaying,
    'positionMs': positionMs,
    'durationMs': durationMs,
    'timestampEpochMs': timestampEpochMs,
    'senderRole': senderRole,
    'senderName': senderName,
  };
}

class CoupleChatMessage {
  final String id;
  final String sender;
  final String text;
  final int timestamp;
  final String? songId;
  final String? songTitle;
  final String? songArtist;
  final String? songThumbnail;
  final String? reaction;

  const CoupleChatMessage({
    required this.id,
    required this.sender,
    required this.text,
    required this.timestamp,
    this.songId,
    this.songTitle,
    this.songArtist,
    this.songThumbnail,
    this.reaction,
  });

  factory CoupleChatMessage.fromJson(Map<String, dynamic> json) {
    return CoupleChatMessage(
      id: json['id'] as String? ?? '',
      sender: json['sender'] as String? ?? '',
      text: json['text'] as String? ?? '',
      timestamp: (json['timestamp'] as num?)?.toInt() ?? 0,
      songId: json['songId'] as String?,
      songTitle: json['songTitle'] as String?,
      songArtist: json['songArtist'] as String?,
      songThumbnail: json['songThumbnail'] as String?,
      reaction: json['reaction'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'sender': sender,
    'text': text,
    'timestamp': timestamp,
    if (songId != null) 'songId': songId,
    if (songTitle != null) 'songTitle': songTitle,
    if (songArtist != null) 'songArtist': songArtist,
    if (songThumbnail != null) 'songThumbnail': songThumbnail,
    if (reaction != null) 'reaction': reaction,
  };
}

class CouplePushSong {
  final String songId;
  final String title;
  final String artist;
  final String? thumbnailUrl;
  final String sender;
  final int timestamp;

  const CouplePushSong({
    this.songId = '',
    this.title = '',
    this.artist = '',
    this.thumbnailUrl,
    this.sender = '',
    this.timestamp = 0,
  });

  factory CouplePushSong.fromJson(Map<String, dynamic> json) {
    return CouplePushSong(
      songId: json['songId'] as String? ?? '',
      title: json['title'] as String? ?? '',
      artist: json['artist'] as String? ?? '',
      thumbnailUrl: json['thumbnailUrl'] as String?,
      sender: json['sender'] as String? ?? '',
      timestamp: (json['timestamp'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'songId': songId,
    'title': title,
    'artist': artist,
    if (thumbnailUrl != null) 'thumbnailUrl': thumbnailUrl,
    'sender': sender,
    'timestamp': timestamp,
  };
}

class DeviceSyncPayload {
  final String deviceId;
  final String deviceName;
  final String platform;
  final String email;
  final String songId;
  final String title;
  final String artist;
  final String? thumbnailUrl;
  final bool isPlaying;
  final int positionMs;
  final int durationMs;
  final int timestamp;

  const DeviceSyncPayload({
    this.deviceId = '',
    this.deviceName = '',
    this.platform = '',
    this.email = '',
    this.songId = '',
    this.title = '',
    this.artist = '',
    this.thumbnailUrl,
    this.isPlaying = false,
    this.positionMs = 0,
    this.durationMs = 0,
    this.timestamp = 0,
  });

  factory DeviceSyncPayload.fromJson(Map<String, dynamic> json) {
    return DeviceSyncPayload(
      deviceId: json['deviceId'] as String? ?? '',
      deviceName: json['deviceName'] as String? ?? '',
      platform: json['platform'] as String? ?? '',
      email: json['email'] as String? ?? '',
      songId: json['songId'] as String? ?? '',
      title: json['title'] as String? ?? '',
      artist: json['artist'] as String? ?? '',
      thumbnailUrl: json['thumbnailUrl'] as String?,
      isPlaying: json['isPlaying'] as bool? ?? false,
      positionMs: (json['positionMs'] as num?)?.toInt() ?? 0,
      durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
      timestamp: (json['timestamp'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'deviceId': deviceId,
    'deviceName': deviceName,
    'platform': platform,
    'email': email,
    'songId': songId,
    'title': title,
    'artist': artist,
    if (thumbnailUrl != null) 'thumbnailUrl': thumbnailUrl,
    'isPlaying': isPlaying,
    'positionMs': positionMs,
    'durationMs': durationMs,
    'timestamp': timestamp,
  };
}
