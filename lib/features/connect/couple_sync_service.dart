import 'dart:async';
import 'dart:io';
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
  final String myEmail;
  final String partnerRole;
  final String partnerName;
  final String partnerCode;
  final String partnerEmail;
  final CoupleLivePlayback? partnerPlayback;
  final bool isLiveSyncing;
  final List<CoupleChatMessage> messages;
  final CouplePushSong? latestPushedSong;
  final DeviceSyncPayload? otherDeviceSync;
  final bool isConnecting;
  final String? noticeMessage;

  const CoupleSyncState({
    this.isPaired = false,
    this.spaceId = '',
    this.myRole = 'HIM',
    this.myName = '',
    this.myCode = '',
    this.myEmail = '',
    this.partnerRole = 'HER',
    this.partnerName = '',
    this.partnerCode = '',
    this.partnerEmail = '',
    this.partnerPlayback,
    this.isLiveSyncing = false,
    this.messages = const [],
    this.latestPushedSong,
    this.otherDeviceSync,
    this.isConnecting = false,
    this.noticeMessage,
  });

  CoupleSyncState copyWith({
    bool? isPaired,
    String? spaceId,
    String? myRole,
    String? myName,
    String? myCode,
    String? myEmail,
    String? partnerRole,
    String? partnerName,
    String? partnerCode,
    String? partnerEmail,
    CoupleLivePlayback? partnerPlayback,
    bool? isLiveSyncing,
    List<CoupleChatMessage>? messages,
    CouplePushSong? latestPushedSong,
    DeviceSyncPayload? otherDeviceSync,
    bool? isConnecting,
    String? noticeMessage,
  }) {
    return CoupleSyncState(
      isPaired: isPaired ?? this.isPaired,
      spaceId: spaceId ?? this.spaceId,
      myRole: myRole ?? this.myRole,
      myName: myName ?? this.myName,
      myCode: myCode ?? this.myCode,
      myEmail: myEmail ?? this.myEmail,
      partnerRole: partnerRole ?? this.partnerRole,
      partnerName: partnerName ?? this.partnerName,
      partnerCode: partnerCode ?? this.partnerCode,
      partnerEmail: partnerEmail ?? this.partnerEmail,
      partnerPlayback: partnerPlayback ?? this.partnerPlayback,
      isLiveSyncing: isLiveSyncing ?? this.isLiveSyncing,
      messages: messages ?? this.messages,
      latestPushedSong: latestPushedSong ?? this.latestPushedSong,
      otherDeviceSync: otherDeviceSync ?? this.otherDeviceSync,
      isConnecting: isConnecting ?? this.isConnecting,
      noticeMessage: noticeMessage,
    );
  }
}

class CoupleSyncService extends StateNotifier<CoupleSyncState> {
  final Ref _ref;
  Timer? _syncTimer;
  Timer? _inviteCheckTimer;
  StreamSubscription? _liveSub;
  StreamSubscription? _pushSub;
  StreamSubscription? _chatSub;
  StreamSubscription? _inviteSub;
  StreamSubscription? _deviceSub;
  bool _isHandlingRemoteSync = false;
  int _lastSeenPushTimestamp = 0;

  CoupleSyncService(this._ref) : super(const CoupleSyncState()) {
    _loadPersisted();
    _listenToLocalPlayer();
    _initMqttStreams();
  }

  void _initMqttStreams() {
    _liveSub = FirebaseCoupleSync.liveStream.listen((live) {
      if (live.senderRole.toUpperCase() != state.myRole.toUpperCase()) {
        state = state.copyWith(partnerPlayback: live);
        if (state.isLiveSyncing) {
          _applyPartnerPlayback(live);
        }
      }
    });

    _pushSub = FirebaseCoupleSync.pushStream.listen((push) {
      if (push.timestamp > _lastSeenPushTimestamp) {
        _lastSeenPushTimestamp = push.timestamp;
        final sender = push.sender.isNotEmpty ? push.sender : state.partnerRole;
        state = state.copyWith(
          latestPushedSong: push,
          noticeMessage: '$sender pushed "${push.title}" 💕',
        );
      }
    });

    _chatSub = FirebaseCoupleSync.chatStream.listen((chat) {
      final list = state.messages;
      if (!list.any((m) => m.id == chat.id)) {
        state = state.copyWith(messages: [...list, chat]);
      }
    });

    _inviteSub = FirebaseCoupleSync.inviteStream.listen((inv) {
      if (!state.isPaired && inv.matched && inv.spaceId.isNotEmpty) {
        final pRole = inv.partnerRole.isNotEmpty ? inv.partnerRole : state.partnerRole;
        final pName = inv.partnerName.isNotEmpty ? inv.partnerName : (pRole == 'HER' ? 'Her' : 'Him');
        state = state.copyWith(
          isPaired: true,
          spaceId: inv.spaceId,
          partnerCode: inv.partnerCode,
          partnerName: pName,
          partnerRole: pRole,
          noticeMessage: 'Hearts Paired Successfully! 💕',
        );
        _persist();
        _subscribeToSpace(inv.spaceId);
      }
    });

    _deviceSub = FirebaseCoupleSync.deviceStream.listen((dev) {
      if (dev.email == state.myEmail && dev.platform != Platform.operatingSystem) {
        state = state.copyWith(otherDeviceSync: dev);
      }
    });
  }

  void _loadPersisted() {
    final prefs = _ref.read(prefsProvider);
    final isPaired = prefs.get('couple_is_paired', false);
    final spaceId = prefs.get('couple_space_id', '');
    final myRole = prefs.get('couple_my_role', 'HIM');
    final myName = prefs.get('couple_my_name', '');
    final myCode = prefs.get('couple_my_code', '');
    final myEmail = prefs.get('couple_my_email', '');
    final partnerRole = prefs.get('couple_partner_role', myRole == 'HER' ? 'HIM' : 'HER');
    final partnerName = prefs.get('couple_partner_name', '');
    final partnerCode = prefs.get('couple_partner_code', '');
    final partnerEmail = prefs.get('couple_partner_email', '');

    state = state.copyWith(
      isPaired: isPaired,
      spaceId: spaceId,
      myRole: myRole,
      myName: myName,
      myCode: myCode,
      myEmail: myEmail,
      partnerRole: partnerRole,
      partnerName: partnerName,
      partnerCode: partnerCode,
      partnerEmail: partnerEmail,
    );

    if (myEmail.isNotEmpty) {
      FirebaseCoupleSync.subscribeDeviceSync(myEmail);
    }

    if (myCode.isEmpty) {
      generateMyCode(role: myRole);
    } else {
      FirebaseCoupleSync.subscribe('her_music/invite/$myCode');
    }

    if (isPaired && spaceId.isNotEmpty) {
      _subscribeToSpace(spaceId);
      _startSyncTimer();
    }
  }

  void _subscribeToSpace(String spaceId) {
    if (spaceId.isEmpty) return;
    FirebaseCoupleSync.subscribe('her_music/space/$spaceId/live');
    FirebaseCoupleSync.subscribe('her_music/space/$spaceId/push');
    FirebaseCoupleSync.subscribe('her_music/space/$spaceId/chat');
  }

  void _persist() {
    final prefs = _ref.read(prefsProvider);
    prefs.set('couple_is_paired', state.isPaired);
    prefs.set('couple_space_id', state.spaceId);
    prefs.set('couple_my_role', state.myRole);
    prefs.set('couple_my_name', state.myName);
    prefs.set('couple_my_code', state.myCode);
    prefs.set('couple_my_email', state.myEmail);
    prefs.set('couple_partner_role', state.partnerRole);
    prefs.set('couple_partner_name', state.partnerName);
    prefs.set('couple_partner_code', state.partnerCode);
    prefs.set('couple_partner_email', state.partnerEmail);
  }

  void setMyEmail(String email) {
    final clean = email.trim();
    state = state.copyWith(myEmail: clean);
    _persist();
    if (clean.isNotEmpty) {
      FirebaseCoupleSync.subscribeDeviceSync(clean);
      if (state.partnerEmail.isNotEmpty) {
        linkByEmail(state.partnerEmail);
      }
    }
  }

  void setPartnerEmail(String email) {
    final clean = email.trim();
    state = state.copyWith(partnerEmail: clean);
    _persist();
    if (clean.isNotEmpty && state.myEmail.isNotEmpty) {
      linkByEmail(clean);
    }
  }

  Future<bool> linkByEmail(String partnerEmailInput) async {
    final pEmail = partnerEmailInput.trim();
    final mEmail = state.myEmail.trim();
    if (pEmail.isEmpty) return false;
    if (mEmail.isEmpty) {
      state = state.copyWith(partnerEmail: pEmail);
      _persist();
      return false;
    }
    final space = FirebaseCoupleSync.calculateEmailSpaceId(mEmail, pEmail);
    if (space.isEmpty) return false;

    state = state.copyWith(
      isPaired: true,
      spaceId: space,
      partnerEmail: pEmail,
      noticeMessage: 'Connected via Email Space! 💕',
    );
    _persist();
    _subscribeToSpace(space);
    _startSyncTimer();
    return true;
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
    FirebaseCoupleSync.subscribe('her_music/invite/$code');
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
        _subscribeToSpace(match.spaceId);
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
      _subscribeToSpace(space);
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
      noticeMessage: 'Unlinked from partner.',
    );
    _persist();
  }

  void toggleLiveSync([bool? enabled]) {
    final next = enabled ?? !state.isLiveSyncing;
    state = state.copyWith(isLiveSyncing: next);
    if (next && state.partnerPlayback != null) {
      _applyPartnerPlayback(state.partnerPlayback!);
    }
  }

  void unpair() => unlink();

  Future<bool> pairWithCode(String code) => linkPartner(code);

  void _listenToLocalPlayer() {
    _ref.listen<PlayerSnapshot>(playbackServiceProvider, (prev, next) {
      if (!state.isPaired || state.spaceId.isEmpty) return;
      if (_isHandlingRemoteSync) return;

      final prevTrack = prev?.current?.videoId;
      final nextTrack = next.current?.videoId;
      final prevPlaying = prev?.isPlaying ?? false;
      final nextPlaying = next.isPlaying;

      if (prevTrack != nextTrack || prevPlaying != nextPlaying) {
        _broadcastLocal(next);
      }
    });
  }

  Future<void> _broadcastLocal(PlayerSnapshot snap) async {
    final current = snap.current;
    if (current == null) return;

    if (state.isPaired && state.spaceId.isNotEmpty) {
      final live = CoupleLivePlayback(
        songId: current.videoId,
        title: current.title,
        artist: current.artist,
        thumbnailUrl: current.artworkUrl,
        isPlaying: snap.isPlaying,
        positionMs: snap.position.inMilliseconds,
        durationMs: snap.duration.inMilliseconds,
        timestampEpochMs: DateTime.now().millisecondsSinceEpoch,
        senderRole: state.myRole,
        senderName: state.myName.isNotEmpty ? state.myName : state.myRole,
      );
      await FirebaseCoupleSync.broadcastLivePlayback(state.spaceId, live);
    }

    if (state.myEmail.isNotEmpty) {
      final dev = DeviceSyncPayload(
        deviceId: 'desktop_${Platform.operatingSystem}',
        deviceName: Platform.isMacOS ? 'Mac' : 'Windows PC',
        platform: Platform.operatingSystem,
        email: state.myEmail,
        songId: current.videoId,
        title: current.title,
        artist: current.artist,
        thumbnailUrl: current.artworkUrl,
        isPlaying: snap.isPlaying,
        positionMs: snap.position.inMilliseconds,
        durationMs: snap.duration.inMilliseconds,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );
      await FirebaseCoupleSync.broadcastDeviceSync(dev);
    }
  }

  void _startSyncTimer() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(milliseconds: 2000), (_) async {
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
      } catch (_) {}
    });
  }

  Future<void> syncPartnerNow() async {
    final partner = state.partnerPlayback;
    if (partner == null || partner.songId.isEmpty) return;
    await _applyPartnerPlayback(partner, force: true);
  }

  Future<void> handoffFromDevice() async {
    final dev = state.otherDeviceSync;
    if (dev == null || dev.songId.isEmpty) return;
    final player = _ref.read(playbackServiceProvider.notifier);
    final playable = PlayableTrack(
      videoId: dev.songId,
      title: dev.title,
      artist: dev.artist,
      album: '',
      artworkUrl: dev.thumbnailUrl ?? '',
    );
    await player.play(playable);
    if (dev.positionMs > 1000) {
      await player.seek(Duration(milliseconds: dev.positionMs));
    }
    state = state.copyWith(noticeMessage: 'Transferred playback from ${dev.deviceName}!');
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
    _liveSub?.cancel();
    _pushSub?.cancel();
    _chatSub?.cancel();
    _inviteSub?.cancel();
    _deviceSub?.cancel();
    super.dispose();
  }
}
