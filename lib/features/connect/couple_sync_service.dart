import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/stream_models.dart';
import '../../core/storage/prefs.dart';
import '../player/playback_service.dart';
import '../player/player_state.dart';
import 'couple_models.dart';
import 'firebase_couple_sync.dart';

final coupleSyncProvider =
    StateNotifierProvider<CoupleSyncService, CoupleSyncState>((ref) {
  return CoupleSyncService(ref);
});

class CoupleSyncState {
  final bool isPaired;
  final String spaceId;
  final String myRole;
  final String myName;
  final String myCode;
  final String partnerRole;
  final String partnerName;
  final String partnerCode;
  final CoupleLivePlayback? partnerPlayback;
  final bool isLiveSyncing;
  final List<CoupleChatMessage> messages;
  final CouplePushSong? latestPushedSong;
  final bool isConnecting;
  final String? noticeMessage;

  const CoupleSyncState({
    this.isPaired = false,
    this.spaceId = '',
    this.myRole = 'HIM',
    this.myName = '',
    this.myCode = '',
    this.partnerRole = 'HER',
    this.partnerName = '',
    this.partnerCode = '',
    this.partnerPlayback,
    this.isLiveSyncing = false,
    this.messages = const [],
    this.latestPushedSong,
    this.isConnecting = false,
    this.noticeMessage,
  });

  CoupleSyncState copyWith({
    bool? isPaired,
    String? spaceId,
    String? myRole,
    String? myName,
    String? myCode,
    String? partnerRole,
    String? partnerName,
    String? partnerCode,
    CoupleLivePlayback? partnerPlayback,
    bool? isLiveSyncing,
    List<CoupleChatMessage>? messages,
    CouplePushSong? latestPushedSong,
    bool? isConnecting,
    String? noticeMessage,
  }) {
    return CoupleSyncState(
      isPaired: isPaired ?? this.isPaired,
      spaceId: spaceId ?? this.spaceId,
      myRole: myRole ?? this.myRole,
      myName: myName ?? this.myName,
      myCode: myCode ?? this.myCode,
      partnerRole: partnerRole ?? this.partnerRole,
      partnerName: partnerName ?? this.partnerName,
      partnerCode: partnerCode ?? this.partnerCode,
      partnerPlayback: partnerPlayback ?? this.partnerPlayback,
      isLiveSyncing: isLiveSyncing ?? this.isLiveSyncing,
      messages: messages ?? this.messages,
      latestPushedSong: latestPushedSong ?? this.latestPushedSong,
      isConnecting: isConnecting ?? this.isConnecting,
      noticeMessage: noticeMessage,
    );
  }
}

class CoupleSyncService extends StateNotifier<CoupleSyncState> {
  final Ref _ref;
  Timer? _syncTimer;
  Timer? _inviteCheckTimer;
  bool _isHandlingRemoteSync = false;
  int _lastSeenPushTimestamp = 0;

  CoupleSyncService(this._ref) : super(const CoupleSyncState()) {
    _loadPersisted();
    _listenToLocalPlayer();
  }

  void _loadPersisted() {
    final prefs = _ref.read(prefsProvider);
    final isPaired = prefs.get('couple_is_paired', false);
    final spaceId = prefs.get('couple_space_id', '');
    final myRole = prefs.get('couple_my_role', 'HIM');
    final myName = prefs.get('couple_my_name', '');
    final myCode = prefs.get('couple_my_code', '');
    final partnerRole = prefs.get('couple_partner_role', myRole == 'HER' ? 'HIM' : 'HER');
    final partnerName = prefs.get('couple_partner_name', '');
    final partnerCode = prefs.get('couple_partner_code', '');

    state = state.copyWith(
      isPaired: isPaired,
      spaceId: spaceId,
      myRole: myRole,
      myName: myName,
      myCode: myCode,
      partnerRole: partnerRole,
      partnerName: partnerName,
      partnerCode: partnerCode,
    );

    if (myCode.isEmpty) {
      generateMyCode(role: myRole);
    }

    if (isPaired && spaceId.isNotEmpty) {
      _startSyncTimer();
    }
  }

  void _persist() {
    final prefs = _ref.read(prefsProvider);
    prefs.set('couple_is_paired', state.isPaired);
    prefs.set('couple_space_id', state.spaceId);
    prefs.set('couple_my_role', state.myRole);
    prefs.set('couple_my_name', state.myName);
    prefs.set('couple_my_code', state.myCode);
    prefs.set('couple_partner_role', state.partnerRole);
    prefs.set('couple_partner_name', state.partnerName);
    prefs.set('couple_partner_code', state.partnerCode);
  }

  void setRole(String role) {
    final cleanRole = role.toUpperCase();
    final partnerRole = cleanRole == 'HER' ? 'HIM' : 'HER';
    state = state.copyWith(
      myRole: cleanRole,
      partnerRole: partnerRole,
    );
    generateMyCode(role: cleanRole);
    _persist();
  }

  void setMyName(String name) {
    state = state.copyWith(myName: name.trim());
    _persist();
    if (state.myCode.isNotEmpty) {
      final nameToSend = state.myName.isNotEmpty ? state.myName : state.myRole;
      FirebaseCoupleSync.registerInvite(
        code: state.myCode,
        role: state.myRole,
        name: nameToSend,
      );
    }
  }

  String generateMyCode({String? role}) {
    final r = (role ?? state.myRole).toUpperCase();
    final rand = (1000 + Random().nextInt(9000)).toString();
    final code = '$r-$rand';
    state = state.copyWith(myCode: code);
    _persist();
    final nameToSend = state.myName.isNotEmpty ? state.myName : r;
    FirebaseCoupleSync.registerInvite(code: code, role: r, name: nameToSend);
    _startInviteCheck(code);
    return code;
  }

  void _startInviteCheck(String code) {
    _inviteCheckTimer?.cancel();
    _inviteCheckTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (state.isPaired) {
        _inviteCheckTimer?.cancel();
        return;
      }
      final match = await FirebaseCoupleSync.checkInviteMatch(code);
      if (match != null && match.matched && match.spaceId.isNotEmpty) {
        _inviteCheckTimer?.cancel();
        final pRole = match.partnerRole.isNotEmpty ? match.partnerRole : state.partnerRole;
        final pName = match.partnerName.isNotEmpty
            ? match.partnerName
            : (state.partnerName.isNotEmpty ? state.partnerName : (pRole == 'HER' ? 'Her' : 'Him'));
        state = state.copyWith(
          isPaired: true,
          spaceId: match.spaceId,
          partnerCode: match.partnerCode,
          partnerName: pName,
          partnerRole: pRole,
          noticeMessage: 'Hearts Paired Successfully! 💕',
        );
        _persist();
        _startSyncTimer();
      }
    });
  }

  Future<bool> linkPartner(String partnerCodeInput) async {
    final clean = partnerCodeInput.trim().toUpperCase();
    if (clean.isEmpty) return false;
    state = state.copyWith(isConnecting: true, noticeMessage: null);

    var code = state.myCode;
    if (code.isEmpty) {
      code = generateMyCode();
    }

    final nameToSend = state.myName.isNotEmpty ? state.myName : state.myRole;
    final success = await FirebaseCoupleSync.linkInvite(
      partnerCode: clean,
      myCode: code,
      myRole: state.myRole,
      myName: nameToSend,
    );

    if (success) {
      final space = FirebaseCoupleSync.calculateSpaceId(code, clean);
      final partnerRole = clean.startsWith('HER') ? 'HER' : 'HIM';
      final partnerName = state.partnerName.isNotEmpty
          ? state.partnerName
          : (partnerRole == 'HER' ? 'Her' : 'Him');

      state = state.copyWith(
        isPaired: true,
        spaceId: space,
        partnerCode: clean,
        partnerRole: partnerRole,
        partnerName: partnerName,
        isConnecting: false,
        noticeMessage: 'Connected with partner space! 💕',
      );
      _persist();
      _startSyncTimer();
      return true;
    } else {
      state = state.copyWith(
        isConnecting: false,
        noticeMessage: 'Could not connect with code. Please verify.',
      );
      return false;
    }
  }

  void unlink() {
    _syncTimer?.cancel();
    _inviteCheckTimer?.cancel();
    state = state.copyWith(
      isPaired: false,
      spaceId: '',
      partnerCode: '',
      partnerPlayback: null,
      isLiveSyncing: false,
      messages: const [],
      noticeMessage: 'Unlinked Couple Space',
    );
    _persist();
  }

  void toggleLiveSync() {
    final next = !state.isLiveSyncing;
    state = state.copyWith(
      isLiveSyncing: next,
      noticeMessage: next ? 'Live Sync Enabled 💖' : 'Live Sync Disabled',
    );
    if (next && state.partnerPlayback != null) {
      syncPartnerNow();
    }
  }

  void _listenToLocalPlayer() {
    _ref.listen<PlayerSnapshot>(playbackServiceProvider, (prev, next) {
      if (_isHandlingRemoteSync || !state.isPaired || state.spaceId.isEmpty) return;
      final current = next.current;
      if (current == null) return;

      if (prev?.current?.videoId != current.videoId ||
          prev?.isPlaying != next.isPlaying ||
          (prev != null && (prev.position.inSeconds - next.position.inSeconds).abs() > 4)) {
        _broadcastLocal(next);
      }
    });
  }

  Future<void> _broadcastLocal(PlayerSnapshot snap) async {
    final track = snap.current;
    if (track == null || state.spaceId.isEmpty) return;

    final live = CoupleLivePlayback(
      songId: track.videoId,
      title: track.title,
      artist: track.artist,
      thumbnailUrl: track.artworkUrl,
      isPlaying: snap.isPlaying,
      positionMs: snap.position.inMilliseconds,
      durationMs: snap.duration.inMilliseconds,
      timestampEpochMs: DateTime.now().millisecondsSinceEpoch,
      senderRole: state.myRole,
      senderName: state.myName.isNotEmpty ? state.myName : state.myRole,
    );

    await FirebaseCoupleSync.broadcastLivePlayback(state.spaceId, live);
  }

  void _startSyncTimer() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) async {
      if (!state.isPaired || state.spaceId.isEmpty) return;

      final localSnap = _ref.read(playbackServiceProvider);
      if (localSnap.isPlaying && !_isHandlingRemoteSync) {
        _broadcastLocal(localSnap);
      }

      try {
        final playback = await FirebaseCoupleSync.fetchPartnerLivePlayback(
          state.spaceId,
          state.partnerRole,
        );

        if (playback != null) {
          state = state.copyWith(partnerPlayback: playback);
          if (state.isLiveSyncing) {
            _applyPartnerPlayback(playback);
          }
        }

        final msgs = await FirebaseCoupleSync.fetchChatMessages(state.spaceId);
        if (msgs.isNotEmpty && msgs.length != state.messages.length) {
          state = state.copyWith(messages: msgs);
        }

        final pushed = await FirebaseCoupleSync.fetchLatestPushSong(state.spaceId);
        if (pushed != null && pushed.timestamp > _lastSeenPushTimestamp) {
          _lastSeenPushTimestamp = pushed.timestamp;
          if (pushed.sender != (state.myName.isNotEmpty ? state.myName : state.myRole)) {
            state = state.copyWith(
              latestPushedSong: pushed,
              noticeMessage: '${pushed.sender} pushed "${pushed.title}" 💕',
            );
          }
        }
      } catch (_) {}
    });
  }

  Future<void> syncPartnerNow() async {
    final partner = state.partnerPlayback;
    if (partner == null || partner.songId.isEmpty) return;
    await _applyPartnerPlayback(partner, force: true);
  }

  Future<void> _applyPartnerPlayback(CoupleLivePlayback playback, {bool force = false}) async {
    if (playback.songId.isEmpty) return;
    final player = _ref.read(playbackServiceProvider.notifier);
    final current = _ref.read(playbackServiceProvider).current;

    final elapsed = playback.isPlaying
        ? (DateTime.now().millisecondsSinceEpoch - playback.timestampEpochMs).clamp(0, 15000)
        : 0;
    final targetMs = playback.positionMs + elapsed;

    _isHandlingRemoteSync = true;
    try {
      if (current?.videoId != playback.songId || force) {
        final playable = PlayableTrack(
          videoId: playback.songId,
          title: playback.title,
          artist: playback.artist,
          album: '',
          artworkUrl: playback.thumbnailUrl ?? '',
        );
        await player.play(playable);
        if (targetMs > 1000) {
          await player.seek(Duration(milliseconds: targetMs));
        }
        if (!playback.isPlaying) {
          await player.pause();
        }
      } else {
        final snap = _ref.read(playbackServiceProvider);
        final currentPos = snap.position.inMilliseconds;
        final drift = (currentPos - targetMs).abs();
        if (drift > 2000) {
          await player.seek(Duration(milliseconds: targetMs));
        }
        if (playback.isPlaying && !snap.isPlaying) {
          await player.playResume();
        } else if (!playback.isPlaying && snap.isPlaying) {
          await player.pause();
        }
      }
    } finally {
      Future.delayed(const Duration(milliseconds: 500), () {
        _isHandlingRemoteSync = false;
      });
    }
  }

  Future<void> pushCurrentSongToPartner() async {
    if (!state.isPaired || state.spaceId.isEmpty) return;
    final snap = _ref.read(playbackServiceProvider);
    final current = snap.current;
    if (current == null) return;

    final push = CouplePushSong(
      songId: current.videoId,
      title: current.title,
      artist: current.artist,
      thumbnailUrl: current.artworkUrl,
      sender: state.myName.isNotEmpty ? state.myName : state.myRole,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );

    final ok = await FirebaseCoupleSync.pushSong(state.spaceId, push);
    if (ok) {
      state = state.copyWith(noticeMessage: 'Pushed "${current.title}" to partner! 💕');
    }
  }

  Future<void> sendChat(String text, {bool includeCurrentSong = false}) async {
    if (!state.isPaired || state.spaceId.isEmpty || text.trim().isEmpty) return;

    String? songId;
    String? songTitle;
    String? songArtist;
    String? songThumb;

    if (includeCurrentSong) {
      final current = _ref.read(playbackServiceProvider).current;
      if (current != null) {
        songId = current.videoId;
        songTitle = current.title;
        songArtist = current.artist;
        songThumb = current.artworkUrl;
      }
    }

    final id = '${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}';
    final msg = CoupleChatMessage(
      id: id,
      sender: state.myName.isNotEmpty ? state.myName : state.myRole,
      text: text.trim(),
      timestamp: DateTime.now().millisecondsSinceEpoch,
      songId: songId,
      songTitle: songTitle,
      songArtist: songArtist,
      songThumbnail: songThumb,
    );

    final ok = await FirebaseCoupleSync.sendChatMessage(state.spaceId, msg);
    if (ok) {
      final list = [...state.messages, msg];
      state = state.copyWith(messages: list);
    }
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    _inviteCheckTimer?.cancel();
    super.dispose();
  }
}
