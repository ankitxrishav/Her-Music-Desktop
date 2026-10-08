import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/connect/couple_sync_service.dart';
import '../../features/player/playback_service.dart';
import '../components/buttons.dart';
import '../theme/tokens.dart';

class ConnectPage extends ConsumerStatefulWidget {
  const ConnectPage({super.key});

  @override
  ConsumerState<ConnectPage> createState() => _ConnectPageState();
}

class _ConnectPageState extends ConsumerState<ConnectPage> {
  final TextEditingController _partnerCodeController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _chatController = TextEditingController();
  final TextEditingController _myEmailController = TextEditingController();
  final TextEditingController _partnerEmailController = TextEditingController();
  final ScrollController _chatScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    final sync = ref.read(coupleSyncProvider);
    if (sync.myName.isNotEmpty) { _nameController.text = sync.myName; }
    if (sync.myEmail.isNotEmpty) { _myEmailController.text = sync.myEmail; }
    if (sync.partnerEmail.isNotEmpty) { _partnerEmailController.text = sync.partnerEmail; }
  }

  @override
  void dispose() {
    _partnerCodeController.dispose();
    _nameController.dispose();
    _chatController.dispose();
    _myEmailController.dispose();
    _partnerEmailController.dispose();
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
    final sync = ref.watch(coupleSyncProvider);
    final player = ref.watch(playbackServiceProvider);
    final dark = waveIsDark(context);
    final accent = waveAccent(context);

    ref.listen<CoupleSyncState>(coupleSyncProvider, (prev, next) {
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
                color: const Color(0xFFFF4081).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                FluentIcons.heart,
                color: Color(0xFFFF4081),
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Text('Couple Space', style: WaveType.pageTitle),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: sync.isPaired
                            ? const Color(0x3310B981)
                            : const Color(0x33FF4081),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        sync.isPaired ? 'PAIRED 💕' : 'LINK SPACE',
                        style: TextStyle(
                          color: sync.isPaired
                              ? const Color(0xFF10B981)
                              : const Color(0xFFFF4081),
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  'Real-time YouTube sync, live playback mirroring & couple messaging',
                  style: WaveType.meta.copyWith(color: waveTextSecondary(context)),
                ),
              ],
            ),
          ],
        ),
      ),
      content: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        children: [
          if (sync.noticeMessage != null) ...[
            InfoBar(
              title: const Text('Couple Space Notice'),
              content: Text(sync.noticeMessage!),
              severity: InfoBarSeverity.info,
            ),
            const SizedBox(height: 14),
          ],
          if (!sync.isPaired)
            _buildPairingView(sync, dark, accent)
          else
            _buildPairedView(sync, player, dark, accent),
        ],
      ),
    );
  }

  Widget _buildPairingView(CoupleSyncState sync, bool dark, Color accent) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _card(
          dark: dark,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(FluentIcons.heart, color: Color(0xFFFF4081), size: 20),
                  SizedBox(width: 10),
                  Text("Instant Pair by Email (Tri-Platform Phone & Laptop)", style: WaveType.sectionTitle),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                "When you and your partner enter each other\x27s email address, your Android phones and laptops automatically sync into the exact same Couple Space without needing invite codes.",
                style: WaveType.meta.copyWith(color: waveTextSecondary(context)),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TextBox(
                      controller: _myEmailController,
                      placeholder: "Your Google / Email ID",
                      prefix: const Padding(
                        padding: EdgeInsets.only(left: 10),
                        child: Icon(FluentIcons.mail, size: 16),
                      ),
                      onChanged: (val) => ref.read(coupleSyncProvider.notifier).setMyEmail(val),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextBox(
                      controller: _partnerEmailController,
                      placeholder: "Partner\x27s Google / Email ID",
                      prefix: const Padding(
                        padding: EdgeInsets.only(left: 10),
                        child: Icon(FluentIcons.heart, size: 16),
                      ),
                      onChanged: (val) => ref.read(coupleSyncProvider.notifier).setPartnerEmail(val),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: () {
                      final pEmail = _partnerEmailController.text.trim();
                      if (pEmail.isNotEmpty) {
                        ref.read(coupleSyncProvider.notifier).linkByEmail(pEmail);
                      }
                    },
                    style: ButtonStyle(
                      backgroundColor: WidgetStateProperty.all(const Color(0xFFFF4081)),
                      shape: WidgetStateProperty.all(RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                    ),
                    child: const Text("Connect Couple Space 💕", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _card(
                dark: dark,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(FluentIcons.contact, color: Color(0xFFFF4081), size: 18),
                        SizedBox(width: 8),
                        Text('1. Your Profile & Invite Code', style: WaveType.sectionTitle),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () => ref.read(coupleSyncProvider.notifier).setRole('HIM'),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                color: sync.myRole == 'HIM'
                                    ? const Color(0xFFFF4081)
                                    : (dark ? const Color(0x1AFFFFFF) : const Color(0x0A000000)),
                                border: Border.all(
                                  color: sync.myRole == 'HIM'
                                      ? const Color(0xFFFF4081)
                                      : waveDivider(context),
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  'Him 💙',
                                  style: TextStyle(
                                    color: sync.myRole == 'HIM' ? Colors.white : null,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: GestureDetector(
                            onTap: () => ref.read(coupleSyncProvider.notifier).setRole('HER'),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                color: sync.myRole == 'HER'
                                    ? const Color(0xFFFF4081)
                                    : (dark ? const Color(0x1AFFFFFF) : const Color(0x0A000000)),
                                border: Border.all(
                                  color: sync.myRole == 'HER'
                                      ? const Color(0xFFFF4081)
                                      : waveDivider(context),
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  'Her 💖',
                                  style: TextStyle(
                                    color: sync.myRole == 'HER' ? Colors.white : null,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextBox(
                      controller: _nameController,
                      placeholder: 'Enter your name...',
                      onChanged: (v) => ref.read(coupleSyncProvider.notifier).setMyName(v),
                    ),
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF281537),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0x4DFF4081)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Share This Code With Your Partner:',
                              style: TextStyle(fontSize: 11, color: Color(0xFFE0D0E8))),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Text(
                                sync.myCode,
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 2,
                                  color: Colors.white,
                                ),
                              ),
                              const Spacer(),
                              WaveIconButton(
                                tooltip: 'Copy Code',
                                icon: const Icon(FluentIcons.copy, size: 16, color: Colors.white),
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(text: sync.myCode));
                                },
                              ),
                              WaveIconButton(
                                tooltip: 'New Code',
                                icon: const Icon(FluentIcons.refresh, size: 16, color: Colors.white),
                                onPressed: () {
                                  ref.read(coupleSyncProvider.notifier).generateMyCode();
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          const Row(
                            children: [
                              SizedBox(
                                width: 12,
                                height: 12,
                                child: ProgressRing(strokeWidth: 1.5),
                              ),
                              SizedBox(width: 8),
                              Text('Waiting for partner to enter code…',
                                  style: TextStyle(fontSize: 11, color: Color(0xFFFF80AB))),
                            ],
                          ),
                        ],
                      ),
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
                    const Row(
                      children: [
                        Icon(FluentIcons.heart, color: Color(0xFFFF4081), size: 18),
                        SizedBox(width: 8),
                        Text('2. Enter Partner\'s Code', style: WaveType.sectionTitle),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Enter the invite code from your partner\'s Her Music app (Phone, Mac, or Windows).',
                      style: WaveType.body.copyWith(color: waveTextSecondary(context)),
                    ),
                    const SizedBox(height: 16),
                    TextBox(
                      controller: _partnerCodeController,
                      placeholder: 'Partner Code (e.g. HER-1234 or HIM-5678)',
                      prefix: const Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: Icon(FluentIcons.code, size: 14),
                      ),
                    ),
                    const SizedBox(height: 18),
                    FilledButton(
                      onPressed: sync.isConnecting
                          ? null
                          : () {
                              final code = _partnerCodeController.text.trim();
                              if (code.isEmpty) return;
                              ref.read(coupleSyncProvider.notifier).linkPartner(code);
                            },
                      style: ButtonStyle(
                        backgroundColor: WidgetStateProperty.all(const Color(0xFFFF4081)),
                        shape: WidgetStateProperty.all(
                          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        padding: WidgetStateProperty.all(
                          const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (sync.isConnecting) ...[
                            const SizedBox(
                              width: 14,
                              height: 14,
                              child: ProgressRing(strokeWidth: 2),
                            ),
                            const SizedBox(width: 8),
                          ] else ...[
                            const Icon(FluentIcons.heart, size: 14, color: Colors.white),
                            const SizedBox(width: 8),
                          ],
                          const Text(
                            '💖 Pair Hearts 💕',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
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

  Widget _buildPairedView(
    CoupleSyncState sync,
    dynamic player,
    bool dark,
    Color accent,
  ) {
    final partner = sync.partnerPlayback;

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
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0x33FF4081),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0x66FF4081)),
                    ),
                    child: Row(
                      children: [
                        const Icon(FluentIcons.heart, color: Color(0xFFFF4081), size: 14),
                        const SizedBox(width: 6),
                        Text(
                          '${sync.myName} & ${sync.partnerName}',
                          style: const TextStyle(
                            color: Color(0xFFFF4081),
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text('Space: ${sync.spaceId}',
                      style: WaveType.meta.copyWith(color: waveTextSecondary(context))),
                  const SizedBox(width: 6),
                  WaveIconButton(
                    tooltip: 'Copy Space ID',
                    icon: const Icon(FluentIcons.copy, size: 14),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: sync.spaceId));
                    },
                  ),
                ],
              ),
              Row(
                children: [
                  FilledButton(
                    onPressed: () => ref.read(coupleSyncProvider.notifier).toggleLiveSync(),
                    style: ButtonStyle(
                      backgroundColor: WidgetStateProperty.all(
                        sync.isLiveSyncing ? const Color(0xFFFF4081) : const Color(0x33FFFFFF),
                      ),
                      shape: WidgetStateProperty.all(
                        RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      padding: WidgetStateProperty.all(
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          sync.isLiveSyncing ? FluentIcons.sync_occurence : FluentIcons.sync,
                          size: 13,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          sync.isLiveSyncing ? 'Live Sync: ON 💖' : 'Live Sync: OFF',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  WaveGhostButton(
                    label: 'Unlink Space',
                    icon: FluentIcons.leave,
                    onPressed: () => ref.read(coupleSyncProvider.notifier).unlink(),
                  ),
                ],
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
                            const Icon(FluentIcons.music_note, color: Color(0xFFFF4081), size: 18),
                            const SizedBox(width: 8),
                            Text(
                              '${sync.partnerName.isNotEmpty ? sync.partnerName : (sync.partnerRole == "HER" ? "Her" : "Him")}\'s Live Playback',
                              style: WaveType.sectionTitle.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (partner != null && partner.songId.isNotEmpty) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              color: dark ? const Color(0xFF1E1428) : const Color(0xFFF8F0FA),
                              border: Border.all(color: const Color(0x33FF4081)),
                            ),
                            child: Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: partner.thumbnailUrl != null && partner.thumbnailUrl!.isNotEmpty
                                      ? Image.network(
                                          partner.thumbnailUrl!,
                                          width: 60,
                                          height: 60,
                                          fit: BoxFit.cover,
                                          errorBuilder: (ctx, err, st) => Container(
                                            width: 60,
                                            height: 60,
                                            color: const Color(0xFF281537),
                                            child: const Icon(FluentIcons.music_note, color: Colors.white),
                                          ),
                                        )
                                      : Container(
                                          width: 60,
                                          height: 60,
                                          color: const Color(0xFF281537),
                                          child: const Icon(FluentIcons.music_note, color: Colors.white),
                                        ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        partner.title,
                                        style: WaveType.trackTitle.copyWith(fontWeight: FontWeight.bold),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        partner.artist,
                                        style: WaveType.meta.copyWith(color: waveTextSecondary(context)),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Icon(
                                            partner.isPlaying ? FluentIcons.play : FluentIcons.pause,
                                            size: 11,
                                            color: const Color(0xFFFF4081),
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            partner.isPlaying ? 'Playing in real time' : 'Paused',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: Color(0xFFFF4081),
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: () => ref.read(coupleSyncProvider.notifier).syncPartnerNow(),
                            style: ButtonStyle(
                              backgroundColor: WidgetStateProperty.all(const Color(0xFFFF4081)),
                              shape: WidgetStateProperty.all(
                                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              padding: WidgetStateProperty.all(
                                const EdgeInsets.symmetric(vertical: 10),
                              ),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(FluentIcons.sync_occurence, size: 14, color: Colors.white),
                                SizedBox(width: 8),
                                Text(
                                  '💖 Sync & Listen Together',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ] else
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: Text(
                              '${sync.partnerName} is not playing music right now. When they play a song on Android or Desktop, it will sync here!',
                              style: WaveType.body.copyWith(color: waveTextSecondary(context)),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _card(
                    dark: dark,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(FluentIcons.send, color: Color(0xFFFF4081), size: 16),
                            SizedBox(width: 8),
                            Text('Push Current Song 💕', style: WaveType.sectionTitle),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (player.current != null) ...[
                          Text(player.current!.title, style: WaveType.body.copyWith(fontWeight: FontWeight.bold)),
                          Text(player.current!.artist, style: WaveType.meta.copyWith(color: waveTextSecondary(context))),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: () => ref.read(coupleSyncProvider.notifier).pushCurrentSongToPartner(),
                            style: ButtonStyle(
                              backgroundColor: WidgetStateProperty.all(const Color(0xFFE91E63)),
                              shape: WidgetStateProperty.all(
                                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              padding: WidgetStateProperty.all(
                                const EdgeInsets.symmetric(vertical: 8),
                              ),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(FluentIcons.heart, size: 12, color: Colors.white),
                                SizedBox(width: 6),
                                Text(
                                  'Push to Partner\'s Phone 💕',
                                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ] else
                          Text('Play any song to push it to your partner.',
                              style: WaveType.meta.copyWith(color: waveTextSecondary(context))),
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
                        const Icon(FluentIcons.chat, color: Color(0xFFFF4081), size: 18),
                        const SizedBox(width: 8),
                        Text(
                          'Couple Chat & Song Notes 💕',
                          style: WaveType.sectionTitle.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      children: [
                        for (final emoji in ['💖', '🐾', '🎵', '✨', '🔥', '🎧', '💕', '😘'])
                          Button(
                            onPressed: () => ref.read(coupleSyncProvider.notifier).sendChat(emoji),
                            child: Text(emoji, style: const TextStyle(fontSize: 16)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      height: 280,
                      decoration: BoxDecoration(
                        color: dark ? WaveColors.backgroundDeep : WaveColors.lightSurface,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.all(10),
                      child: ListView.builder(
                        controller: _chatScroll,
                        itemCount: sync.messages.length,
                        itemBuilder: (context, idx) {
                          final msg = sync.messages[idx];
                          final isMe = msg.sender == sync.myName;
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Align(
                              alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                              child: Container(
                                constraints: const BoxConstraints(maxWidth: 320),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: isMe
                                      ? const Color(0xFFFF4081)
                                      : (dark ? const Color(0xFF281537) : const Color(0xFFEDE7F6)),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      msg.sender,
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: isMe ? const Color(0xB3FFFFFF) : const Color(0xFFFF4081),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      msg.text,
                                      style: TextStyle(
                                        color: isMe ? Colors.white : (dark ? Colors.white : const Color(0xDD000000)),
                                        fontSize: 13,
                                      ),
                                    ),
                                    if (msg.songTitle != null) ...[
                                      const SizedBox(height: 6),
                                      Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(6),
                                          color: const Color(0x42000000),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(FluentIcons.music_note, size: 12, color: Colors.white),
                                            const SizedBox(width: 4),
                                            Flexible(
                                              child: Text(
                                                '${msg.songTitle} - ${msg.songArtist ?? ""}',
                                                style: const TextStyle(fontSize: 11, color: Colors.white),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextBox(
                            controller: _chatController,
                            placeholder: 'Send a love note, song vibe or message…',
                            onSubmitted: (txt) {
                              if (txt.trim().isEmpty) return;
                              ref.read(coupleSyncProvider.notifier).sendChat(txt.trim());
                              _chatController.clear();
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        WaveIconButton(
                          tooltip: 'Share Playing Song',
                          icon: const Icon(FluentIcons.music_note, size: 16),
                          onPressed: () {
                            ref.read(coupleSyncProvider.notifier).sendChat(
                                  'Listening to this with you 💕',
                                  includeCurrentSong: true,
                                );
                          },
                        ),
                        const SizedBox(width: 6),
                        FilledButton(
                          onPressed: () {
                            final txt = _chatController.text.trim();
                            if (txt.isEmpty) return;
                            ref.read(coupleSyncProvider.notifier).sendChat(txt);
                            _chatController.clear();
                          },
                          style: ButtonStyle(
                            backgroundColor: WidgetStateProperty.all(const Color(0xFFFF4081)),
                            shape: WidgetStateProperty.all(
                              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                          child: const Icon(FluentIcons.send, size: 14, color: Colors.white),
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
        color: dark ? const Color(0x18FFFFFF) : const Color(0x08000000),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: dark ? const Color(0x1FFFFFFF) : const Color(0x14000000)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.25 : 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}
