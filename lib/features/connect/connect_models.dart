class ConnectTrack {
  final String id;
  final String title;
  final String artist;
  final String album;
  final int durationMs;
  final String thumbnail;

  const ConnectTrack({
    required this.id,
    required this.title,
    required this.artist,
    this.album = '',
    this.durationMs = 0,
    this.thumbnail = '',
  });

  factory ConnectTrack.fromJson(Map<String, dynamic> json) {
    return ConnectTrack(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      artist: json['artist'] as String? ?? '',
      album: json['album'] as String? ?? '',
      durationMs: (json['duration'] as num?)?.toInt() ?? 0,
      thumbnail: json['thumbnail'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'artist': artist,
    'album': album,
    'duration': durationMs,
    'thumbnail': thumbnail,
  };
}

class ConnectUser {
  final String userId;
  final String username;
  final bool isHost;
  final bool isConnected;

  const ConnectUser({
    required this.userId,
    required this.username,
    required this.isHost,
    this.isConnected = true,
  });

  factory ConnectUser.fromJson(Map<String, dynamic> json) {
    return ConnectUser(
      userId: json['user_id'] as String? ?? '',
      username: json['username'] as String? ?? 'User',
      isHost: json['is_host'] as bool? ?? false,
      isConnected: json['is_connected'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
    'user_id': userId,
    'username': username,
    'is_host': isHost,
    'is_connected': isConnected,
  };
}

class ConnectChatMessage {
  final String userId;
  final String username;
  final String message;
  final int timestamp;

  const ConnectChatMessage({
    required this.userId,
    required this.username,
    required this.message,
    required this.timestamp,
  });

  factory ConnectChatMessage.fromJson(Map<String, dynamic> json) {
    return ConnectChatMessage(
      userId: json['user_id'] as String? ?? '',
      username: json['username'] as String? ?? 'User',
      message: json['message'] as String? ?? '',
      timestamp: (json['timestamp'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch,
    );
  }
}

enum ConnectState {
  disconnected,
  connecting,
  connected,
  error,
}

class RoomSessionState {
  final ConnectState state;
  final String? roomCode;
  final String? userId;
  final String? username;
  final bool isHost;
  final List<ConnectUser> users;
  final ConnectTrack? currentTrack;
  final bool isPlaying;
  final int positionMs;
  final List<ConnectChatMessage> messages;
  final String? errorMessage;

  const RoomSessionState({
    this.state = ConnectState.disconnected,
    this.roomCode,
    this.userId,
    this.username,
    this.isHost = false,
    this.users = const [],
    this.currentTrack,
    this.isPlaying = false,
    this.positionMs = 0,
    this.messages = const [],
    this.errorMessage,
  });

  RoomSessionState copyWith({
    ConnectState? state,
    String? roomCode,
    String? userId,
    String? username,
    bool? isHost,
    List<ConnectUser>? users,
    ConnectTrack? currentTrack,
    bool? isPlaying,
    int? positionMs,
    List<ConnectChatMessage>? messages,
    String? errorMessage,
  }) {
    return RoomSessionState(
      state: state ?? this.state,
      roomCode: roomCode ?? this.roomCode,
      userId: userId ?? this.userId,
      username: username ?? this.username,
      isHost: isHost ?? this.isHost,
      users: users ?? this.users,
      currentTrack: currentTrack ?? this.currentTrack,
      isPlaying: isPlaying ?? this.isPlaying,
      positionMs: positionMs ?? this.positionMs,
      messages: messages ?? this.messages,
      errorMessage: errorMessage,
    );
  }
}
