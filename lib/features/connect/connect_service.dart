import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/stream_models.dart';
import '../player/playback_service.dart';
import '../player/player_state.dart';
import 'connect_models.dart';

final connectServiceProvider =
    StateNotifierProvider<ConnectService, RoomSessionState>((ref) {
  return ConnectService(ref);
});

class ConnectService extends StateNotifier<RoomSessionState> {
  final Ref _ref;
  WebSocket? _socket;
  Timer? _pingTimer;
  bool _handlingRemote = false;

  static const List<String> serverEndpoints = [
    'wss://devilmi-vivi-music-listen-together.hf.space',
    'wss://metroserverx.meowery.eu/ws',
  ];

  ConnectService(this._ref) : super(const RoomSessionState()) {
    _initPlayerListener();
  }

  void _initPlayerListener() {
    _ref.listen<PlayerSnapshot>(playbackServiceProvider, (PlayerSnapshot? prev, PlayerSnapshot next) {
      if (_handlingRemote || state.state != ConnectState.connected) return;

      final track = next.current;
      if (track == null) return;

      if (prev?.current?.videoId != track.videoId && track.videoId.isNotEmpty) {
        sendPlaybackAction(
          action: 'change_track',
          trackId: track.videoId,
          positionMs: next.position.inMilliseconds,
          trackInfo: ConnectTrack(
            id: track.videoId,
            title: track.title,
            artist: track.artist,
            album: track.album,
            durationMs: next.duration.inMilliseconds,
            thumbnail: track.artworkUrl,
          ),
        );
      } else if (prev?.isPlaying != next.isPlaying) {
        sendPlaybackAction(
          action: next.isPlaying ? 'play' : 'pause',
          trackId: track.videoId,
          positionMs: next.position.inMilliseconds,
        );
      }
    });
  }

  Future<void> createRoom({required String username}) async {
    state = state.copyWith(
      state: ConnectState.connecting,
      username: username,
      errorMessage: null,
    );
    final connected = await _connectSocket();
    if (!connected) {
      state = state.copyWith(
        state: ConnectState.error,
        errorMessage: 'Could not connect to sync server',
      );
      return;
    }
    _send({
      'type': 'create_room',
      'payload': {'username': username},
    });
  }

  Future<void> joinRoom({
    required String roomCode,
    required String username,
  }) async {
    final cleanedCode = roomCode.trim().toUpperCase();
    state = state.copyWith(
      state: ConnectState.connecting,
      username: username,
      roomCode: cleanedCode,
      errorMessage: null,
    );
    final connected = await _connectSocket();
    if (!connected) {
      state = state.copyWith(
        state: ConnectState.error,
        errorMessage: 'Could not connect to sync server',
      );
      return;
    }
    _send({
      'type': 'join_room',
      'payload': {
        'room_code': cleanedCode,
        'username': username,
      },
    });
  }

  void leaveRoom() {
    try {
      _send({'type': 'leave_room'});
    } catch (_) {}
    _cleanup();
    state = const RoomSessionState();
  }

  void sendChat(String text) {
    if (text.trim().isEmpty || _socket == null) return;
    _send({
      'type': 'chat',
      'payload': {'message': text.trim()},
    });
  }

  void sendPlaybackAction({
    required String action,
    String? trackId,
    int? positionMs,
    ConnectTrack? trackInfo,
  }) {
    if (_socket == null || state.state != ConnectState.connected) return;
    _send({
      'type': 'playback_action',
      'payload': {
        'action': action,
        'track_id': ?trackId,
        'position': ?positionMs,
        'track_info': ?trackInfo?.toJson(),
      },
    });
  }

  Future<bool> _connectSocket() async {
    _cleanup();
    for (final endpoint in serverEndpoints) {
      try {
        _socket = await WebSocket.connect(endpoint).timeout(
          const Duration(seconds: 8),
        );
        _socket!.listen(
          _onMessage,
          onError: (err) {
            state = state.copyWith(
              state: ConnectState.error,
              errorMessage: '$err',
            );
            _cleanup();
          },
          onDone: () {
            if (state.state == ConnectState.connected) {
              state = state.copyWith(
                state: ConnectState.disconnected,
                errorMessage: 'Connection closed',
              );
            }
            _cleanup();
          },
        );
        _startPing();
        return true;
      } catch (e) {
        debugPrint('Sync connection failed on $endpoint: $e');
      }
    }
    return false;
  }

  void _onMessage(dynamic raw) {
    try {
      final json = jsonDecode(raw.toString()) as Map<String, dynamic>;
      final type = json['type'] as String? ?? '';
      final payload = json['payload'] as Map<String, dynamic>? ?? {};

      switch (type) {
        case 'room_created':
          state = state.copyWith(
            state: ConnectState.connected,
            roomCode: payload['room_code'] as String?,
            userId: payload['user_id'] as String?,
            isHost: true,
            users: [
              ConnectUser(
                userId: payload['user_id'] as String? ?? '',
                username: state.username ?? 'Host',
                isHost: true,
              )
            ],
          );
          break;

        case 'join_approved':
          final rawUsers = (payload['state']?['users'] as List?) ?? [];
          final users = rawUsers
              .map((u) => ConnectUser.fromJson(Map<String, dynamic>.from(u)))
              .toList();

          state = state.copyWith(
            state: ConnectState.connected,
            roomCode: payload['room_code'] as String?,
            userId: payload['user_id'] as String?,
            isHost: false,
            users: users,
          );
          _handleRemoteSync(payload['state'] as Map<String, dynamic>? ?? {});
          break;

        case 'user_joined':
          final user = ConnectUser(
            userId: payload['user_id'] as String? ?? '',
            username: payload['username'] as String? ?? 'User',
            isHost: false,
          );
          state = state.copyWith(
            users: [...state.users.where((u) => u.userId != user.userId), user],
          );
          break;

        case 'user_left':
          final leftId = payload['user_id'] as String? ?? '';
          state = state.copyWith(
            users: state.users.where((u) => u.userId != leftId).toList(),
          );
          break;

        case 'sync_playback':
        case 'sync_state':
          _handleRemoteSync(payload);
          break;

        case 'playback_action':
          _handlePlaybackAction(payload);
          break;

        case 'chat_message':
          final chat = ConnectChatMessage.fromJson(payload);
          state = state.copyWith(
            messages: [...state.messages, chat],
          );
          break;

        case 'error':
          state = state.copyWith(
            errorMessage: payload['message'] as String? ?? 'Unknown sync error',
          );
          break;
      }
    } catch (e) {
      debugPrint('Sync message parse error: $e');
    }
  }

  void _handleRemoteSync(Map<String, dynamic> data) {
    final trackJson = data['current_track'] as Map<String, dynamic>?;
    final isPlaying = data['is_playing'] as bool? ?? false;
    final pos = (data['position'] as num?)?.toInt() ?? 0;

    ConnectTrack? track;
    if (trackJson != null) {
      track = ConnectTrack.fromJson(trackJson);
    }

    state = state.copyWith(
      currentTrack: track,
      isPlaying: isPlaying,
      positionMs: pos,
    );

    if (track != null && track.id.isNotEmpty) {
      _applyTrackAndPlayback(
        trackId: track.id,
        title: track.title,
        artist: track.artist,
        artworkUrl: track.thumbnail,
        isPlaying: isPlaying,
        positionMs: pos,
      );
    }
  }

  void _handlePlaybackAction(Map<String, dynamic> payload) {
    final action = payload['action'] as String? ?? '';
    final pos = (payload['position'] as num?)?.toInt();
    final trackJson = payload['track_info'] as Map<String, dynamic>?;

    ConnectTrack? track;
    if (trackJson != null) {
      track = ConnectTrack.fromJson(trackJson);
    }

    if (action == 'change_track' && track != null) {
      state = state.copyWith(
        currentTrack: track,
        isPlaying: true,
        positionMs: pos ?? 0,
      );
      _applyTrackAndPlayback(
        trackId: track.id,
        title: track.title,
        artist: track.artist,
        artworkUrl: track.thumbnail,
        isPlaying: true,
        positionMs: pos ?? 0,
      );
    } else if (action == 'play') {
      state = state.copyWith(isPlaying: true);
      _applyPlayPause(play: true, positionMs: pos);
    } else if (action == 'pause') {
      state = state.copyWith(isPlaying: false);
      _applyPlayPause(play: false, positionMs: pos);
    } else if (action == 'seek' && pos != null) {
      state = state.copyWith(positionMs: pos);
      _applySeek(pos);
    }
  }

  Future<void> _applyTrackAndPlayback({
    required String trackId,
    required String title,
    required String artist,
    required String artworkUrl,
    required bool isPlaying,
    required int positionMs,
  }) async {
    _handlingRemote = true;
    try {
      final player = _ref.read(playbackServiceProvider.notifier);
      final current = _ref.read(playbackServiceProvider).current;
      if (current?.videoId != trackId) {
        await player.play(
          PlayableTrack(
            videoId: trackId,
            title: title,
            artist: artist,
            artworkUrl: artworkUrl,
          ),
          sourceLabel: 'Connect Sync',
        );
      }
      if (positionMs > 0) {
        await player.seek(Duration(milliseconds: positionMs));
      }
      if (!isPlaying) {
        await player.pause();
      }
    } finally {
      Future.delayed(const Duration(milliseconds: 500), () {
        _handlingRemote = false;
      });
    }
  }

  Future<void> _applyPlayPause({required bool play, int? positionMs}) async {
    _handlingRemote = true;
    try {
      final player = _ref.read(playbackServiceProvider.notifier);
      if (positionMs != null) {
        await player.seek(Duration(milliseconds: positionMs));
      }
      if (play) {
        await player.playResume();
      } else {
        await player.pause();
      }
    } finally {
      Future.delayed(const Duration(milliseconds: 500), () {
        _handlingRemote = false;
      });
    }
  }

  Future<void> _applySeek(int positionMs) async {
    _handlingRemote = true;
    try {
      await _ref
          .read(playbackServiceProvider.notifier)
          .seek(Duration(milliseconds: positionMs));
    } finally {
      Future.delayed(const Duration(milliseconds: 500), () {
        _handlingRemote = false;
      });
    }
  }

  void _send(Map<String, dynamic> data) {
    if (_socket == null) return;
    try {
      _socket!.add(jsonEncode(data));
    } catch (e) {
      debugPrint('Failed to send sync frame: $e');
    }
  }

  void _startPing() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      _send({'type': 'ping'});
    });
  }

  void _cleanup() {
    _pingTimer?.cancel();
    _pingTimer = null;
    try {
      _socket?.close();
    } catch (_) {}
    _socket = null;
  }

  @override
  void dispose() {
    _cleanup();
    super.dispose();
  }
}
