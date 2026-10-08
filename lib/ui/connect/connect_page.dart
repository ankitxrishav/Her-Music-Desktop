import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/connect/connect_models.dart';
import '../../features/connect/connect_service.dart';
import '../../features/player/playback_service.dart';
import '../components/buttons.dart';
import '../theme/tokens.dart';

class ConnectPage extends ConsumerStatefulWidget {
  const ConnectPage({super.key});

  @override
  ConsumerState<ConnectPage> createState() => _ConnectPageState();
}

class _ConnectPageState extends ConsumerState<ConnectPage> {
  late final TextEditingController _nameController;
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _chatScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    final defaultDevice = Platform.isMacOS
        ? 'Her Music Mac'
        : (Platform.isWindows ? 'Her Music PC' : 'Her Music Desktop');
    _nameController = TextEditingController(text: defaultDevice);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    _chatController.dispose();
    _chatScroll.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScroll.hasClients) {
        _chatScroll.animateTo(
          _chatScroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final connect = ref.watch(connectServiceProvider);
    final dark = waveIsDark(context);
    final accent = waveAccent(context);

    ref.listen<RoomSessionState>(connectServiceProvider, (prev, next) {
      if (prev?.messages.length != next.messages.length) {
        _scrollToBottom();
      }
    });

    return ScaffoldPage(
      header: PageHeader(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFF43F5E).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                FluentIcons.heart,
                color: Color(0xFFF43F5E),
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Connect & Listen Together',
                    style: WaveType.pageTitle),
                Text(
                  'Real-time synced music between macOS, Windows, and Android',
                  style: WaveType.caption.copyWith(
                    color: waveTextSecondary(context),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      content: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        children: [
          if (connect.errorMessage != null) ...[
            InfoBar(
              title: const Text('Connection Notice'),
              message: Text(connect.errorMessage!),
              severity: InfoBarSeverity.warning,
            ),
            const SizedBox(height: 16),
          ],
          if (connect.state == ConnectState.connecting)
            _buildConnectingView()
          else if (connect.state == ConnectState.connected)
            _buildConnectedView(connect, dark, accent)
          else
            _buildSetupView(dark, accent),
        ],
      ),
    );
  }

  Widget _buildConnectingView() {
    return Container(
      padding: const EdgeInsets.all(40),
      alignment: Alignment.center,
      child: const Column(
        children: [
          ProgressRing(),
          SizedBox(height: 16),
          Text('Connecting to sync room…', style: WaveType.body),
        ],
      ),
    );
  }

  Widget _buildSetupView(bool dark, Color accent) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _card(
                dark: dark,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(FluentIcons.party_leader,
                            color: Color(0xFFF43F5E), size: 18),
                        const SizedBox(width: 8),
                        Text('Host a Room',
                            style: WaveType.sectionTitle
                                .copyWith(fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Create a private session. You will get a 6-letter room code to share with your partner on any device.',
                      style: WaveType.body.copyWith(
                        color: waveTextSecondary(context),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextBox(
                      controller: _nameController,
                      placeholder: 'Your display name',
                      prefix: const Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: Icon(FluentIcons.contact, size: 14),
                      ),
                    ),
                    const SizedBox(height: 16),
                    WavePrimaryButton(
                      label: 'Create Room',
                      icon: FluentIcons.add,
                      onPressed: () {
                        final name = _nameController.text.trim();
                        if (name.isEmpty) return;
                        ref
                            .read(connectServiceProvider.notifier)
                            .createRoom(username: name);
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _card(
                dark: dark,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(FluentIcons.sync_occurence,
                            color: Color(0xFF8B5CF6), size: 18),
                        const SizedBox(width: 8),
                        Text('Join Partner\'s Room',
                            style: WaveType.sectionTitle
                                .copyWith(fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Enter the room code shared by your partner from Her Music (Windows, Mac, or Android).',
                      style: WaveType.body.copyWith(
                        color: waveTextSecondary(context),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextBox(
                      controller: _codeController,
                      placeholder: 'Room code (e.g. HER-1234)',
                      prefix: const Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: Icon(FluentIcons.code, size: 14),
                      ),
                    ),
                    const SizedBox(height: 16),
                    WavePrimaryButton(
                      label: 'Join Session',
                      icon: FluentIcons.plug_connected,
                      onPressed: () {
                        final code = _codeController.text.trim();
                        final name = _nameController.text.trim();
                        if (code.isEmpty || name.isEmpty) return;
                        ref
                            .read(connectServiceProvider.notifier)
                            .joinRoom(roomCode: code, username: name);
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        _card(
          dark: dark,
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFF43F5E).withValues(alpha: 0.12),
                ),
                child: const Icon(FluentIcons.devices3,
                    color: Color(0xFFF43F5E), size: 22),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('True Cross-Platform Sync',
                        style: WaveType.bodyStrong),
                    const SizedBox(height: 2),
                    Text(
                      'Whether one person is on Mac, Windows, or an Android phone with Her Music, song playback, queue changes, and seeks happen simultaneously.',
                      style: WaveType.caption.copyWith(
                        color: waveTextSecondary(context),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildConnectedView(
      RoomSessionState connect, bool dark, Color accent) {
    final player = ref.watch(playbackServiceProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _card(
          dark: dark,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF43F5E).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: const Color(0xFFF43F5E).withValues(alpha: 0.35),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(FluentIcons.radio_bullet,
                            color: Color(0xFFF43F5E), size: 14),
                        const SizedBox(width: 8),
                        Text(
                          connect.roomCode ?? '',
                          style: WaveType.sectionTitle.copyWith(
                            letterSpacing: 2,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFFF43F5E),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  WaveIconButton(
                    tooltip: 'Copy Room Code',
                    icon: const Icon(FluentIcons.copy, size: 16),
                    onPressed: () {
                      if (connect.roomCode != null) {
                        Clipboard.setData(
                            ClipboardData(text: connect.roomCode!));
                      }
                    },
                  ),
                  const SizedBox(width: 16),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'LIVE SYNCED',
                      style: WaveType.caption.copyWith(
                        color: const Color(0xFF10B981),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              WaveGhostButton(
                label: 'Leave Room',
                icon: FluentIcons.leave,
                onPressed: () =>
                    ref.read(connectServiceProvider.notifier).leaveRoom(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 5,
              child: Column(
                children: [
                  _card(
                    dark: dark,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(FluentIcons.group, size: 16),
                            const SizedBox(width: 8),
                            Text('Participants (${connect.users.length})',
                                style: WaveType.bodyStrong),
                          ],
                        ),
                        const SizedBox(height: 12),
                        for (final u in connect.users) ...[
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: u.isHost
                                        ? const Color(0xFFF43F5E)
                                            .withValues(alpha: 0.2)
                                        : waveDivider(context),
                                  ),
                                  child: Center(
                                    child: Text(
                                      u.username.isNotEmpty
                                          ? u.username[0].toUpperCase()
                                          : '?',
                                      style: WaveType.caption.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(u.username,
                                      style: WaveType.body),
                                ),
                                if (u.isHost)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF43F5E)
                                          .withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      'HOST',
                                      style: WaveType.caption.copyWith(
                                        color: const Color(0xFFF43F5E),
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _card(
                    dark: dark,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Now Playing in Room',
                            style: WaveType.bodyStrong),
                        const SizedBox(height: 8),
                        if (player.current != null) ...[
                          Text(player.current!.title,
                              style: WaveType.trackTitle),
                          Text(player.current!.artist,
                              style: WaveType.caption.copyWith(
                                color: waveTextSecondary(context),
                              )),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              WaveIconButton(
                                tooltip: player.isPlaying ? 'Pause' : 'Play',
                                icon: Icon(
                                  player.isPlaying
                                      ? FluentIcons.pause
                                      : FluentIcons.play,
                                  size: 18,
                                ),
                                onPressed: () {
                                  if (player.isPlaying) {
                                    ref
                                        .read(playbackServiceProvider.notifier)
                                        .pause();
                                  } else {
                                    ref
                                        .read(playbackServiceProvider.notifier)
                                        .playResume();
                                  }
                                },
                              ),
                              const SizedBox(width: 8),
                              WaveIconButton(
                                tooltip: 'Next Track',
                                icon: const Icon(FluentIcons.next, size: 16),
                                onPressed: () => ref
                                    .read(playbackServiceProvider.notifier)
                                    .next(),
                              ),
                              const Spacer(),
                              Text(
                                player.isPlaying ? 'Playing' : 'Paused',
                                style: WaveType.caption.copyWith(
                                  color: waveTextSecondary(context),
                                ),
                              ),
                            ],
                          ),
                        ] else
                          Text('Select a song to start synced playback.',
                              style: WaveType.caption.copyWith(
                                color: waveTextSecondary(context),
                              )),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 6,
              child: _card(
                dark: dark,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(FluentIcons.chat, size: 16),
                        const SizedBox(width: 8),
                        const Text('Room Chat & Reactions',
                            style: WaveType.bodyStrong),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      children: [
                        for (final emoji in ['💖', '🐾', '🎵', '✨', '🔥', '🎧'])
                          Button(
                            onPressed: () => ref
                                .read(connectServiceProvider.notifier)
                                .sendChat(emoji),
                            child: Text(emoji, style: const TextStyle(fontSize: 16)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      height: 220,
                      decoration: BoxDecoration(
                        color: dark
                            ? WaveColors.backgroundDeep
                            : WaveColors.lightSurface,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      padding: const EdgeInsets.all(8),
                      child: ListView.builder(
                        controller: _chatScroll,
                        itemCount: connect.messages.length,
                        itemBuilder: (context, idx) {
                          final msg = connect.messages[idx];
                          final isMe = msg.userId == connect.userId;
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${msg.username}: ',
                                  style: WaveType.caption.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: isMe
                                        ? const Color(0xFFF43F5E)
                                        : accent,
                                  ),
                                ),
                                Expanded(
                                  child: Text(msg.message,
                                      style: WaveType.body),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextBox(
                            controller: _chatController,
                            placeholder: 'Send a message or lyric vibe…',
                            onSubmitted: (txt) {
                              if (txt.trim().isEmpty) return;
                              ref
                                  .read(connectServiceProvider.notifier)
                                  .sendChat(txt.trim());
                              _chatController.clear();
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        WaveIconButton(
                          tooltip: 'Send',
                          icon: const Icon(FluentIcons.send, size: 16),
                          onPressed: () {
                            final txt = _chatController.text.trim();
                            if (txt.isEmpty) return;
                            ref
                                .read(connectServiceProvider.notifier)
                                .sendChat(txt);
                            _chatController.clear();
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _card({required bool dark, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: dark ? WaveColors.surface : WaveColors.lightSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: dark ? WaveColors.outlineSoft : WaveColors.lightOutlineSoft,
        ),
      ),
      child: child,
    );
  }
}
