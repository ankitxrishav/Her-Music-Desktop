import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';

import '../../app/window.dart';
import '../../app/auth_gate.dart';
import '../../core/audio/stream_models.dart';
import '../../core/env/app_env.dart';
import '../../core/storage/prefs.dart';
import '../../features/addons/addon_api.dart';
import '../../features/innertube/innertube_api.dart';
import '../../features/innertube/yt_library_providers.dart';
import '../../features/innertube/yt_web_login.dart';
import '../components/artwork.dart';
import 'yt_profile_chooser.dart';
import '../../features/home/home_providers.dart';
import '../../features/lastfm/auth_repository.dart';
import '../../features/settings/theme_controller.dart';
import '../../features/audio_output/output_controller.dart';
import '../../features/audio_output/output_path_sheet.dart';
import '../../features/lyrics/lyrics_providers.dart';
import '../theme/tokens.dart';
import '../theme/brand_icons.dart';
import '../../features/presence/discord_presence_service.dart';
import '../../features/connect/couple_sync_service.dart';

const _waveSettingsSections = [
  ('general', 'General', FluentIcons.settings),
  ('account', 'Account & Sync', FluentIcons.contact),
  ('couple', 'Couple Space', FluentIcons.heart),
  ('playback', 'Playback', FluentIcons.play),
  ('audio', 'Audio', FluentIcons.speakers),
  ('downloads', 'Downloads', FluentIcons.download),
  ('lyrics', 'Lyrics', FluentIcons.microphone),
  ('appearance', 'Appearance', FluentIcons.brush),
  ('lastfm', 'Last.fm', FluentIcons.heart),
  ('integrations', 'Integrations', FluentIcons.link),
  ('sources', 'Sources', FluentIcons.cloud),
  ('experimental', 'Experimental', FluentIcons.bug),
  ('about', 'About', FluentIcons.info),
];

/// Fluent settings: left nav list + right form.
///
/// Reuses theme_controller + prefs logic; presentation is Fluent
/// (ToggleSwitch, Slider, ComboBox, ContentDialog) — no old ledger
/// switches or boxed groups.
class WaveSettingsPage extends ConsumerStatefulWidget {
  /// Deep-link into a section rail entry (e.g. 'lastfm' from the
  /// profile empty state). Falls back to 'general' when unknown.
  final String? initialSection;
  const WaveSettingsPage({super.key, this.initialSection});

  @override
  ConsumerState<WaveSettingsPage> createState() => _WaveSettingsPageState();
}

class _WaveSettingsPageState extends ConsumerState<WaveSettingsPage> {
  late String _section;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialSection;
    _section =
        initial != null &&
                _waveSettingsSections.any((s) => s.$1 == initial)
            ? initial
            : 'general';
  }

  Future<void> _update(Future<void> Function(Prefs) fn) async {
    await fn(ref.read(prefsProvider));
    ref.read(themeControllerProvider.notifier).refresh();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Content-aware (rail-aware): LayoutBuilder sees real content
        // width, unlike MediaQuery window width (+200 rail error).
        final narrow = constraints.maxWidth < 900;
        if (narrow) {
          return ListView(
            physics: const ClampingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              Text(
                'SYSTEM',
                style: WaveType.overline.copyWith(color: waveAccent(context)),
              ),
              const Text('Settings', style: WaveType.pageTitle),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final s in _waveSettingsSections)
                    ToggleButton(
                      checked: _section == s.$1,
                      onChanged: (_) => setState(() => _section = s.$1),
                      child: Text(s.$2),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              _SectionSwap(
                child: RepaintBoundary(
                  key: ValueKey(_section),
                  child: _SectionBody(section: _section, onUpdate: _update),
                ),
              ),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 220,
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(24, 20, 12, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'SYSTEM',
                      style: WaveType.overline.copyWith(
                        color: waveAccent(context),
                      ),
                    ),
                    const Text('Settings', style: WaveType.pageTitle),
                    const SizedBox(height: 12),
                    for (final s in _waveSettingsSections)
                      ListTile.selectable(
                        selected: _section == s.$1,
                        selectionMode: ListTileSelectionMode.single,
                        leading: Icon(s.$3, size: 15),
                        title: Text(s.$2),
                        onPressed: () => setState(() => _section = s.$1),
                      ),
                  ],
                ),
              ),
            ),
            Container(width: 1, color: waveDivider(context)),
            Expanded(
              child: ListView(
                physics: const ClampingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: _SectionSwap(
                      child: RepaintBoundary(
                        key: ValueKey(_section),
                        child: _SectionBody(
                          section: _section,
                          onUpdate: _update,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SectionBody extends ConsumerWidget {
  final String section;
  final Future<void> Function(Future<void> Function(Prefs)) onUpdate;
  const _SectionBody({required this.section, required this.onUpdate});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    switch (section) {
      case 'general':
        return _General(onUpdate: onUpdate);
      case 'account':
        return _AccountSync(onUpdate: onUpdate);
      case 'couple':
        return _CoupleSpaceSettings(onUpdate: onUpdate);
      case 'playback':
        return _Playback(onUpdate: onUpdate);
      case 'audio':
        return _Audio(onUpdate: onUpdate);
      case 'downloads':
        return _Downloads(onUpdate: onUpdate);
      case 'appearance':
        return _Appearance(onUpdate: onUpdate);
      case 'lyrics':
        return _Lyrics(onUpdate: onUpdate);
      case 'lastfm':
        return _LastFm(onUpdate: onUpdate);
      case 'integrations':
        return _Ytm(onUpdate: onUpdate);
      case 'sources':
        return _Sources(onUpdate: onUpdate);
      case 'experimental':
        return _Experimental(onUpdate: onUpdate);
      default:
        return const _About();
    }
  }
}

/// Section swap: fade only, size from the incoming pane, outgoing overlaid
/// at the top so it cannot re-center or relayout the list mid-transition.
class _SectionSwap extends StatelessWidget {
  final Widget child;
  const _SectionSwap({required this.child});

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: WaveMotion.normal,
      curve: Curves.easeOutCubic,
      alignment: Alignment.topLeft,
      child: AnimatedSwitcher(
        duration: WaveMotion.fast,
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeOutCubic,
        layoutBuilder: (currentChild, previousChildren) {
          return Stack(
            alignment: Alignment.topLeft,
            children: [
              for (final previous in previousChildren)
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: IgnorePointer(
                    child: ExcludeSemantics(child: previous),
                  ),
                ),
              ?currentChild,
            ],
          );
        },
        transitionBuilder: (child, animation) =>
            FadeTransition(opacity: animation, child: child),
        child: child,
      ),
    );
  }
}

class _Group extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;
  final Widget? trailing;
  const _Group({
    required this.title,
    required this.subtitle,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final dark = waveIsDark(context);
    final cardBg = dark ? const Color(0x18FFFFFF) : const Color(0x08000000);
    final headerBg = dark ? const Color(0x22FFFFFF) : const Color(0x0E000000);
    final borderColor = dark ? const Color(0x1FFFFFFF) : const Color(0x14000000);

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.25 : 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: headerBg,
              border: Border(bottom: BorderSide(color: borderColor)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: WaveType.sectionTitle.copyWith(fontWeight: FontWeight.w600)),
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(subtitle, style: WaveType.meta.copyWith(color: waveTextSecondary(context))),
                      ],
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: child,
          ),
        ],
      ),
    );
  }
}

class _Account extends ConsumerWidget {
  final Future<void> Function(Future<void> Function(Prefs)) onUpdate;
  const _Account({required this.onUpdate});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authRepositoryProvider);
    final prefs = ref.watch(prefsProvider);
    final signedIn = auth.username.isNotEmpty;
    final guest = auth.status == AuthStatus.guest || prefs.isGuest;
    return _Group(
      title: 'Last.fm connection',
      subtitle: 'Scrobbling and discovery need a session',
      child: Column(
        children: [
          Row(
            children: [
              const Icon(FluentIcons.contact, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      signedIn
                          ? auth.username
                          : (guest ? 'Guest mode' : 'Not connected'),
                      style: WaveType.trackTitle,
                    ),
                    Text(
                      signedIn
                          ? 'Last.fm connected'
                          : (guest
                              ? 'Last.fm disabled — save keys below, then connect'
                              : 'Connect to scrobble and personalize'),
                      style: WaveType.meta,
                    ),
                  ],
                ),
              ),
              signedIn
                  ? Button(
                      onPressed: () => signOutEverywhere(ref),
                      child: const Text('Sign out'),
                    )
                  : const SizedBox.shrink(),
            ],
          ),
          if (!signedIn) ...[
            const SizedBox(height: 10),
            const _InShellConnect(),
          ],
        ],
      ),
    );
  }
}

/// Web-auth connect that runs inside Settings (no /welcome round-trip),
/// so guests can attach Last.fm after saving keys. Mirrors the welcome
/// approval flow: open the browser, approve, finish here.
class _InShellConnect extends ConsumerStatefulWidget {
  const _InShellConnect();
  @override
  ConsumerState<_InShellConnect> createState() => _InShellConnectState();
}

class _InShellConnectState extends ConsumerState<_InShellConnect> {
  WebAuthHandshake? _handshake;
  bool _busy = false;
  String? _error;

  Future<void> _begin() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final handshake = await ref
          .read(authRepositoryProvider.notifier)
          .beginWebAuth();
      if (!mounted) return;
      setState(() => _handshake = handshake);
      final uri = Uri.parse(handshake.url);
      try {
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      } catch (_) {}
    } catch (e) {
      if (!mounted) return;
      setState(() => _error =
          'Could not reach Last.fm. Check your connection and retry.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _finish() async {
    final handshake = _handshake;
    if (handshake == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(authRepositoryProvider.notifier)
          .completeWebAuth(handshake.token);
      ref.invalidate(feedProvider);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error =
          'Not approved yet — approve Her Music in the browser, then retry.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final configured = ref.watch(prefsProvider).isLastFmConfigured;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_error != null) ...[
          Text(
            _error!,
            style: WaveType.meta.copyWith(color: Colors.red),
          ),
          const SizedBox(height: 8),
        ],
        FilledButton(
          onPressed: _busy || !configured ? null : _begin,
          child: _busy && _handshake == null
              ? const Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: ProgressRing(strokeWidth: 2),
                    ),
                    SizedBox(width: 8),
                    Text('Contacting Last.fm…'),
                  ],
                )
              : Text(_handshake == null
                  ? 'Connect with Last.fm'
                  : 'Restart approval'),
        ),
        if (!configured) ...[
          const SizedBox(height: 6),
          Text(
            'Save your API keys below first.',
            style: WaveType.meta.copyWith(
              color: waveTextTertiary(context),
            ),
          ),
        ],
        if (_handshake != null) ...[
          const SizedBox(height: 8),
          Button(
            onPressed: _busy ? null : _finish,
            child: _busy
                ? const Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: ProgressRing(strokeWidth: 2),
                      ),
                      SizedBox(width: 8),
                      Text('Confirming…'),
                    ],
                  )
                : const Text("I've approved — finish sign-in"),
          ),
        ],
      ],
    );
  }
}

class _Audio extends ConsumerWidget {
  final Future<void> Function(Future<void> Function(Prefs)) onUpdate;
  const _Audio({required this.onUpdate});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(prefsProvider);
    return Column(
      children: [
        const SizedBox(height: 8),
        _Group(
          title: 'Audio output',
          subtitle: Platform.isWindows
              ? 'WASAPI Exclusive bypasses the Windows mixer'
              : 'System audio output',
          child: _WasapiOutputSettings(onUpdate: onUpdate),
        ),
        const SizedBox(height: 8),
        _Group(
          title: 'Streaming and Download quality',
          subtitle: 'Lossless-first with YouTube fallback',
          child: Column(
            children: [
              _QualityRow(
                title: 'Streaming quality',
                value: prefs.losslessQuality,
                onChanged: (q) => onUpdate((p) => p.setLosslessQuality(q)),
              ),
              const SizedBox(height: 8),
              _QualityRow(
                title: 'Download quality',
                value: prefs.downloadQuality,
                onChanged: (q) => onUpdate((p) => p.setDownloadQuality(q)),
              ),
              const SizedBox(height: 8),
              _SwitchRow(
                value: prefs.preferLossless,
                onChanged: (v) => onUpdate((p) => p.setPreferLossless(v)),
                title: 'Prefer lossless',
                subtitle: 'Try lossless first, fall back to Opus',
              ),
            ],
          ),
        )
      ],
    );
  }
}

class _Appearance extends ConsumerWidget {
  final Future<void> Function(Future<void> Function(Prefs)) onUpdate;
  const _Appearance({required this.onUpdate});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(prefsProvider);
    final theme = ref.watch(themeControllerProvider);
    return Column(
      children: [
        _Group(
          title: 'Theme',
          subtitle: 'Midnight charcoal or pearl light',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: ToggleButton(
                      checked: !theme.isLight,
                      onChanged: (_) async {
                        await ref
                            .read(themeControllerProvider.notifier)
                            .setThemeMode(false);
                        await applyWindowMaterial(isLight: false);
                      },
                      child: const Text('Midnight'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ToggleButton(
                      checked: theme.isLight,
                      onChanged: (_) async {
                        await ref
                            .read(themeControllerProvider.notifier)
                            .setThemeMode(true);
                        await applyWindowMaterial(isLight: true);
                      },
                      child: const Text('Pearl'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text('Accent source', style: WaveType.trackTitle),
              const SizedBox(height: 6),
              ComboBox<String>(
                value: theme.accentSource,
                items: const [
                  ComboBoxItem(value: 'custom', child: Text('Custom colour')),
                  ComboBoxItem(
                    value: 'her_music',
                    child: Text('Her Music neutral'),
                  ),
                  ComboBoxItem(value: 'system', child: Text('System accent')),
                  ComboBoxItem(value: 'artwork', child: Text('Artwork tint')),
                ],
                onChanged: (v) {
                  if (v != null) {
                    onUpdate((p) => p.setAccentSource(v));
                  }
                },
              ),
              const SizedBox(height: 10),
              const Text('Accent colour', style: WaveType.trackTitle),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: [
                  for (final c in [
                    const Color(0xFFF5F4F0),
                    const Color(0xFF4CC2FF),
                    const Color(0xFFE03030),
                    const Color(0xFF7C4DFF),
                    const Color(0xFF2196C6),
                    const Color(0xFF6B9E6B),
                    const Color(0xFFE0A030),
                    const Color(0xFFE0507A),
                  ])
                    GestureDetector(
                      onTap: () =>
                          onUpdate((p) => p.setAccentColor(c.toARGB32())),
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: c,
                          border: Border.all(
                            color: theme.accent.toARGB32() == c.toARGB32()
                                ? waveAccent(context)
                                : waveDivider(context),
                            width: 2,
                          ),
                        ),
                        child: theme.accent.toARGB32() == c.toARGB32()
                            ? Icon(
                                FluentIcons.check_mark,
                                size: 14,
                                color: c.computeLuminance() > 0.5
                                    ? Colors.black
                                    : Colors.white,
                              )
                            : null,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _Group(
          title: 'Haze material',
          subtitle:
              'Automatic uses Haze L1–L3 as designed · Solid disables blur',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ComboBox<String>(
                value: theme.hazeMaterial,
                items: const [
                  ComboBoxItem(value: 'automatic', child: Text('Automatic')),
                  ComboBoxItem(value: 'haze', child: Text('Haze')),
                  ComboBoxItem(value: 'solid', child: Text('Solid')),
                ],
                onChanged: (v) {
                  if (v != null) {
                    onUpdate((p) => p.setHazeMaterial(v));
                  }
                },
              ),
              const SizedBox(height: 10),
              const Text('Haze intensity', style: WaveType.trackTitle),
              const SizedBox(height: 6),
              Row(
                children: [
                  for (final opt in ['low', 'medium', 'high'])
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ToggleButton(
                        checked: theme.hazeIntensity == opt,
                        onChanged: (_) =>
                            onUpdate((p) => p.setHazeIntensity(opt)),
                        child: Text(
                          '${opt[0].toUpperCase()}${opt.substring(1)}',
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _Group(
          title: 'Surfaces',
          subtitle: 'Contrast and artwork tinting',
          child: Column(
            children: [
              _SwitchRow(
                value: prefs.amoled,
                onChanged: (v) => onUpdate((p) => p.setAmoled(v)),
                title: 'AMOLED black',
              ),
              _SwitchRow(
                value: prefs.dynamicNowPlaying,
                onChanged: (v) => onUpdate((p) => p.setDynamicNowPlaying(v)),
                title: 'Dynamic artwork theme',
                subtitle: 'Tint Now Playing from album art',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Lyrics extends ConsumerWidget {
  final Future<void> Function(Future<void> Function(Prefs)) onUpdate;
  const _Lyrics({required this.onUpdate});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(prefsProvider);
    return _Group(
      title: 'Timing',
      subtitle: 'Synced lyrics providers',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SwitchRow(
            value: prefs.wordByWord,
            onChanged: (v) => onUpdate((p) => p.setWordByWord(v)),
            title: 'Word-by-word lyrics',
            subtitle: 'Karaoke word highlight. Off uses Apple Music line lyrics.',
          ),
          const SizedBox(height: 10),
          const Text('Primary provider', style: WaveType.trackTitle),
          const SizedBox(height: 6),
          ComboBox<String>(
            value: LyricsProviderId.fromId(prefs.lyricsProviderId).id,
            items: [
              for (final provider in LyricsProviderId.values)
                ComboBoxItem(
                  value: provider.id,
                  child: Text(provider.title),
                ),
            ],
            onChanged: (v) {
              if (v != null) {
                onUpdate((p) => p.setLyricsProviderId(v));
              }
            },
          ),
          const SizedBox(height: 4),
          Text(
            LyricsProviderId.fromId(prefs.lyricsProviderId).subtitle,
            style: WaveType.meta,
          ),
        ],
      ),
    );
  }
}

class _Scrobbler extends ConsumerStatefulWidget {
  final Future<void> Function(Future<void> Function(Prefs)) onUpdate;
  const _Scrobbler({required this.onUpdate});

  @override
  ConsumerState<_Scrobbler> createState() => _ScrobblerState();
}

class _ScrobblerState extends ConsumerState<_Scrobbler> {
  double? _dragPercent;

  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(prefsProvider);
    final percent = (_dragPercent ?? prefs.scrobblePercent.toDouble())
        .clamp(25, 90)
        .toDouble();
    return _Group(
      title: 'Last.fm scrobbling',
      subtitle: 'Thresholds mirror Last.fm rules',
      child: Column(
        children: [
          _SwitchRow(
            value: prefs.scrobblerEnabled,
            onChanged: (v) =>
                widget.onUpdate((p) => p.setScrobbler(enabled: v)),
            title: 'Enable scrobbling',
            subtitle: 'Requires a write-capable session',
          ),
          _SwitchRow(
            value: prefs.scrobbleNowPlaying,
            onChanged: (v) =>
                widget.onUpdate((p) => p.setScrobbler(nowPlaying: v)),
            title: 'Now playing updates',
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Scrobble at ${percent.round()}% of track',
                    style: WaveType.trackTitle,
                  ),
                ),
                SizedBox(
                  width: 180,
                  child: Slider(
                    value: percent,
                    min: 25,
                    max: 90,
                    onChanged: (v) => setState(() => _dragPercent = v),
                    onChangeEnd: (v) {
                      setState(() => _dragPercent = null);
                      widget.onUpdate(
                        (p) => p.setScrobbler(percent: v.round()),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Ytm extends ConsumerWidget {
  final Future<void> Function(Future<void> Function(Prefs)) onUpdate;
  const _Ytm({required this.onUpdate});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Reactive mirror — the API singleton never changes identity, so
    // watching innerTubeProvider alone would never rebuild this row.
    final connection = ref.watch(ytConnectionProvider);
    final account = ref.watch(ytAccountProvider).valueOrNull;
    final prefs = ref.watch(prefsProvider);
    return _Group(
      title: 'YouTube Music',
      subtitle: 'Personal library, history and uploads',
      child: connection.connected
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _connectedRow(context, ref, connection, account),
                const SizedBox(height: 8),
                _SwitchRow(
                  value: prefs.syncYtHistory,
                  onChanged: (v) =>
                      onUpdate((p) => p.setSyncYtHistory(v)),
                  title: 'Sync listening history',
                  subtitle:
                      'Record plays to your YouTube Music history',
                ),
              ],
            )
          : Row(
              children: [
                const Icon(FluentIcons.video, size: 18),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('Not connected', style: WaveType.trackTitle),
                ),
                FilledButton(
                  onPressed: () => ytConnect(context, ref),
                  child: const Text('Connect'),
                ),
              ],
            ),
    );
  }

  Widget _connectedRow(
    BuildContext context,
    WidgetRef ref,
    YtConnection connection,
    YtAccount? account,
  ) {
    // Provisional connections (identity transiently empty right after
    // login) fall back to the roster email so the card never renders
    // a bare "Connected" for a known account.
    final connEmail =
        connection.profileEmail != 'unknown' ? connection.profileEmail : '';
    final rawName = account?.name ?? '';
    final name = rawName.isNotEmpty
        ? rawName
        : (connEmail.isNotEmpty ? connEmail : '');
    // Same @-gate as the chooser: fresh parses never emit junk, but
    // this keeps every path honest if a shape ever surprises us.
    final handle = (account?.handle ?? '').startsWith('@')
        ? account!.handle
        : '';
    final email = (account?.email ?? '').isNotEmpty
        ? account!.email
        : connEmail;
    final idLine = handle.isNotEmpty ? handle : ytDisplayEmail(email);
    final since = DateTime.fromMillisecondsSinceEpoch(
      connection.connectedAtMillis,
      isUtc: false,
    );
    final sinceText = connection.connectedAtMillis > 0
        ? ' · since ${since.year}-'
              '${since.month.toString().padLeft(2, '0')}-'
              '${since.day.toString().padLeft(2, '0')}'
        : '';
    final sub = [
      if (idLine.isNotEmpty) idLine,
      'Connected$sinceText',
    ].join(' · ');
    return Row(
      children: [
        if (account?.photoUrl.isNotEmpty == true)
          WaveArtwork.circle(
            url: account!.photoUrl,
            size: 40,
            label: name,
            // Identity avatar: never let the official-source upgrade
            // swap it for a Deezer artist photo matching the name.
            upgrade: false,
          )
        else
          const Icon(FluentIcons.video, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                name.isNotEmpty ? name : 'Connected',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: WaveType.trackTitle,
              ),
              Text(
                name.isNotEmpty ? sub : 'Connected$sinceText',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: WaveType.meta.copyWith(
                  color: waveTextSecondary(context),
                ),
              ),
            ],
          ),
        ),
        const _CardActions(),
      ],
    );
  }

  /// In-app Google sign-in: opens music.youtube.com in a system
  /// WebView, waits for login, captures cookies automatically, then
  /// runs the shared roster upsert + chooser tail.
  static Future<void> ytConnect(BuildContext context, WidgetRef ref) async {
    var cancelled = false;
    // Non-blocking wait dialog — Cancel just stops listening; the
    // user closes the browser window via the native guard (hide).
    // NOTE: popped via the dialog's OWN context. A rootNavigator pop
    // here would eat the settings page under the go_router ShellRoute.
    BuildContext? waitDialogContext;
    unawaited(
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          waitDialogContext = dialogContext;
          return ContentDialog(
            title: const Text('Sign in with Google'),
            content: const Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    SizedBox(width: 20, height: 20, child: ProgressRing()),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Complete the sign-in in the browser window. '
                        'This dialog closes automatically.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                Text(
                  'Passkey verified but the Google page looks stuck? '
                  'Press Reload — or pick "Try another way" in the '
                  'Google window and use your password instead.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
            actions: [
              Button(
                onPressed: () {
                  YtWebLogin.reloadLoginPage();
                },
                child: const Text('Reload'),
              ),
              Button(
                onPressed: () {
                  cancelled = true;
                  Navigator.of(dialogContext).pop();
                },
                child: const Text('Cancel'),
              ),
            ],
          );
        },
      ),
    );
    if (kDebugMode) {
      debugPrint('YtWebSignIn: waiting for browser login');
    }
    String? header;
    try {
      header = await YtWebLogin.signIn();
    } catch (_) {
      header = null;
    }
    if (kDebugMode) {
      debugPrint(
        'YtWebSignIn: flow returned header=${header == null ? 'null' : '${header.length} chars'} cancelled=$cancelled',
      );
    }
    // Dismiss the wait dialog if it is still up.
    final waitCtx = waitDialogContext;
    if (waitCtx != null && waitCtx.mounted) {
      Navigator.of(waitCtx).maybePop();
    }
    if (cancelled || header == null || header.isEmpty) {
      if (!cancelled && context.mounted) {
        await showDialog(
          context: context,
          builder: (dialogContext) => ContentDialog(
            title: const Text('Sign-in incomplete'),
            content: const Text(
              'No session was captured. Please try again — if Google '
              'shows a passkey step that stalls after Windows Hello, '
              'reload the browser window or pick "Try another way" '
              'and sign in with your password instead. Make sure you '
              'complete the sign-in fully before closing the window.',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
      return;
    }
    if (!context.mounted) return;
    await _ytConnectCaptured(
      context,
      ref,
      header: header,
      pageId: YtWebLogin.lastCapturedPageId ?? '',
    );
    await _refocusMain();
  }
}

/// Card buttons: Switch (multi-channel roster), Add (account/channel),
/// Disconnect. Extracted so the row rebuilds cheaply.
class _CardActions extends ConsumerWidget {
  const _CardActions();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    var channels = 0;
    for (final p in ref.watch(ytProfilesProvider)) {
      channels += p.channels.isEmpty ? 1 : p.channels.length;
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (channels >= 2)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Button(
              onPressed: () => _ytSwitch(context, ref),
              child: const Text('Switch'),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Button(
            onPressed: () => _ytAddMenu(context, ref),
            child: const Text('Add'),
          ),
        ),
        Button(
          onPressed: () async {
            final tube = ref.read(innerTubeProvider);
            await tube.signOut();
            ref.read(ytConnectionProvider.notifier).state = tube.connection;
          },
          child: const Text('Disconnect'),
        ),
      ],
    );
  }

  static Future<void> _ytSwitch(BuildContext context, WidgetRef ref) async {
    final roster = ref.read(ytProfilesProvider);
    final conn = ref.read(ytConnectionProvider);
    final sel = await showYtProfileChooser(
      context: context,
      roster: roster,
      activeEmail: conn.profileEmail,
      activePageId: conn.activePageId,
      title: 'Switch channel',
    );
    if (sel == null || !context.mounted) return;
    YtProfile? target;
    for (final p in ref.read(ytProfilesProvider)) {
      if (p.email == sel.email) {
        target = p;
        break;
      }
    }
    if (target == null) return;
    if (target.email == conn.profileEmail && sel.pageId == conn.activePageId) {
      return; // already active
    }
    try {
      await switchYtIdentity(ref, profile: target, pageId: sel.pageId);
      if (context.mounted) {
        await _showYtOk(
          context,
          'Switched',
          'Now using ${target.email}'
              '${sel.pageId.isEmpty ? '' : ' · brand channel'}. '
              'Library, history and uploads reloaded.',
        );
      }
    } catch (e) {
      if (context.mounted) {
        await _showYtFail(context, e);
      }
    }
  }

  static Future<void> _ytAddMenu(BuildContext context, WidgetRef ref) async {
    final mode = await showDialog<String>(
      context: context,
      builder: (dialogContext) => ContentDialog(
        title: const Text('Add to YouTube Music'),
        content: const Text(
          'Add another Google login, or a brand channel on the '
          'current login.',
          style: TextStyle(fontSize: 12),
        ),
        actions: [
          Button(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          Button(
            onPressed: () => Navigator.of(dialogContext).pop('channel'),
            child: const Text('Brand channel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop('account'),
            child: const Text('Google account'),
          ),
        ],
      ),
    );
    if (mode == null || !context.mounted) return;
    if (mode == 'account') {
      await _ytAddAccount(context, ref);
    } else {
      await _ytAddChannel(context, ref);
    }
  }

  /// Add another Google login: clean-room sign-in (logout URL first,
  /// same window, never destroyed), then the shared capture tail.
  static Future<void> _ytAddAccount(BuildContext context, WidgetRef ref) async {
    var cancelled = false;
    BuildContext? waitCtx;
    unawaited(
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          waitCtx = dialogContext;
          return ContentDialog(
            title: const Text('Add Google account'),
            content: const Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    SizedBox(width: 20, height: 20, child: ProgressRing()),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Log in as the other Google account in the '
                        'browser window. This dialog closes automatically.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                Text(
                  'Passkey verified but the Google page looks stuck? '
                  'Press Reload — or pick "Try another way" in the '
                  'Google window and use your password instead.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
            actions: [
              Button(
                onPressed: () {
                  YtWebLogin.reloadLoginPage();
                },
                child: const Text('Reload'),
              ),
              Button(
                onPressed: () {
                  cancelled = true;
                  Navigator.of(dialogContext).pop();
                },
                child: const Text('Cancel'),
              ),
            ],
          );
        },
      ),
    );
    String? header;
    try {
      header = await YtWebLogin.signInFresh();
    } catch (_) {
      header = null;
    }
    final wc = waitCtx;
    if (wc != null && wc.mounted) {
      Navigator.of(wc).maybePop();
    }
    if (cancelled || header == null || header.isEmpty) {
      if (!cancelled && context.mounted) {
        await _showYtFail(
          context,
          'No session was captured. Please try again.',
        );
      }
      return;
    }
    if (!context.mounted) return;
    await _ytConnectCaptured(
      context,
      ref,
      header: header,
      pageId: YtWebLogin.lastCapturedPageId ?? '',
    );
    await _refocusMain();
  }

  /// Add a brand channel: the window already holds the Google login;
  /// the user flips to the brand channel in-page, presses Done, and
  /// the delegation page ID is read from ytcfg.
  static Future<void> _ytAddChannel(BuildContext context, WidgetRef ref) async {
    final w = await YtWebLogin.ensureWindow();
    if (w == null) {
      if (context.mounted) {
        await _showYtFail(context, 'No system WebView available.');
      }
      return;
    }
    if (!context.mounted) return;
    try {
      w.launch('https://music.youtube.com/',
          triggerOnUrlRequestEvent: false);
    } catch (_) {}
    var cancelled = false;
    var done = false;
    BuildContext? waitCtx;
    unawaited(
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          waitCtx = dialogContext;
          return ContentDialog(
            title: const Text('Add brand channel'),
            content: const Row(
              children: [
                SizedBox(width: 20, height: 20, child: ProgressRing()),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Sign in if needed, then switch to the brand '
                    'channel in the browser window and press Done.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
            actions: [
              Button(
                onPressed: () {
                  cancelled = true;
                  Navigator.of(dialogContext).pop();
                },
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  done = true;
                  Navigator.of(dialogContext).pop();
                },
                child: const Text('Done'),
              ),
            ],
          );
        },
      ),
    );
    String? header;
    try {
      // Generous window: user may need to sign in first.
      header = await YtWebLogin.waitForLoginSession(
        w,
        timeout: const Duration(minutes: 5),
      );
      if (header != null && !cancelled) {
        // Wait for Done/Cancel (the dialog above stays up).
        while (!done && !cancelled) {
          await Future<void>.delayed(const Duration(milliseconds: 300));
        }
      }
    } catch (_) {
      header = null;
    }
    final wc = waitCtx;
    if (wc != null && wc.mounted) {
      Navigator.of(wc).maybePop();
    }
    await YtWebLogin.hideWindow();
    await _refocusMain();
    if (cancelled || header == null || header.isEmpty) {
      if (!cancelled && context.mounted) {
        await _showYtFail(
          context,
          'No session was captured. Please try again.',
        );
      }
      return;
    }
    if (!context.mounted) return;
    final pageId = await YtWebLogin.readDelegatedPageId(w) ?? '';
    if (kDebugMode) {
      debugPrint(
        'YtChannel: Done with pageId=${pageId.isEmpty ? 'main' : '${pageId.length} digits'}',
      );
    }
    if (!context.mounted) return;
    await _ytConnectCaptured(context, ref, header: header, pageId: pageId);
  }
}

/// Shared capture tail: roster upsert → ALWAYS show the channel
/// chooser (even a single row — identity double-check) → switch to
/// the pick. Cancelled chooser falls back to connecting the captured
/// jar directly (legacy behavior).
Future<void> _ytConnectCaptured(
  BuildContext context,
  WidgetRef ref, {
  required String header,
  required String pageId,
}) async {
  final profile = await upsertYtCapture(ref, cookies: header, pageId: pageId);
  if (!context.mounted) return;
  final roster = ref.read(ytProfilesProvider);
  final conn = ref.read(ytConnectionProvider);
  final sel = await showYtProfileChooser(
    context: context,
    roster: roster,
    activeEmail: profile?.email ?? conn.profileEmail,
    activePageId: pageId,
  );
  if (!context.mounted) return;
  if (sel == null) {
    await _YtmStaticFallback.finish(context, ref, header, profile, pageId);
    return;
  }
  YtProfile? target;
  for (final p in ref.read(ytProfilesProvider)) {
    if (p.email == sel.email) {
      target = p;
      break;
    }
  }
  target ??= profile;
  if (target == null) {
    await _showYtFail(context, 'Profile vanished — please try again.');
    return;
  }
  try {
    await switchYtIdentity(ref, profile: target, pageId: sel.pageId);
    // Identity is often transiently empty right after login; one
    // force-refresh backfills the roster row + settings card without
    // needing an app restart. Best-effort: failures just leave the
    // provisional entry for the startup repair pass.
    await _refreshYtIdentity(ref, pageId: sel.pageId);
    if (context.mounted) {
      await _showYtOk(
        context,
        'YouTube Music connected',
        'Account verified — library, history and uploads are unlocked.',
      );
    }
  } catch (e) {
    if (context.mounted) {
      await _showYtFail(context, e);
    }
  }
}

/// One best-effort identity backfill after a fresh connect: re-runs
/// the roster upsert now that the session is live (YouTube serves
/// identity a moment after login — the capture-time resolve is often
/// transiently empty) and refreshes the account card. Best-effort:
/// failures just leave the provisional entry for the startup repair
/// pass.
Future<void> _refreshYtIdentity(WidgetRef ref, {String pageId = ''}) async {
  try {
    final cookies = ref.read(innerTubeProvider).connection.cookies;
    if (cookies.isNotEmpty) {
      await upsertYtCapture(ref, cookies: cookies, pageId: pageId);
    }
    ref.invalidate(ytAccountProvider);
  } catch (_) {}
}

/// Cancelled-chooser fallback: connect the captured jar directly.
abstract class _YtmStaticFallback {
  static Future<void> finish(
    BuildContext context,
    WidgetRef ref,
    String header,
    YtProfile? profile,
    String pageId,
  ) async {
    final tube = ref.read(innerTubeProvider);
    try {
      await tube.connectAs(
        cookies: header,
        profileEmail: profile?.email ?? '',
        pageId: pageId,
      );
      ref.read(ytConnectionProvider.notifier).state = tube.connection;
      await _refreshYtIdentity(ref, pageId: pageId);
      if (context.mounted) {
        await _showYtOk(
          context,
          'YouTube Music connected',
          'Account verified — library, history and uploads are unlocked.',
        );
      }
    } catch (e) {
      if (context.mounted) {
        await _showYtFail(context, e);
      }
    }
  }
}

Future<void> _showYtOk(BuildContext context, String title, String message) {
  return showDialog(
    context: context,
    builder: (dialogContext) => ContentDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

Future<void> _showYtFail(BuildContext context, Object e) {
  return showDialog(
    context: context,
    builder: (dialogContext) => ContentDialog(
      title: const Text('Connection failed'),
      content: Text('$e'),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

Future<void> _refocusMain() async {
  try {
    await windowManager.focus();
  } catch (_) {}
}

/// Addon sources: personal addon URLs replace the built-in lossless
/// backend as the lossless tier (see [AddonApi]). Quota meters fill
/// in after playback; unknown until the first stream attempt.
class _Sources extends ConsumerWidget {
  final Future<void> Function(Future<void> Function(Prefs)) onUpdate;
  const _Sources({required this.onUpdate});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final urls = ref.watch(prefsProvider).addonUrls;
    final src = ref.watch(losslessApiProvider);
    final quotas = src is AddonApi
        ? src.quotaByBase
        : const <String, AddonQuota>{};
    return _Group(
      title: 'Addon sources',
      subtitle: urls.isEmpty
          ? 'No addon configured — using the built-in lossless backend'
          : 'Addons serve the lossless tier instead of the built-in backend',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (AppEnv.addonClientSecret.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                'This build has no addon app key — addon calls will fail. '
                'Rebuild with ADDON_CLIENT_SECRET set.',
                style: TextStyle(fontSize: 12),
              ),
            ),
          for (final u in urls)
            _AddonRow(
              url: u,
              quota: quotas[u],
              onRemove: () async {
                await onUpdate(
                  (p) => p.setAddonUrls(urls.where((e) => e != u).toList()),
                );
                ref.invalidate(losslessApiProvider);
              },
            ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              onPressed: () => _addAddonDialog(context, ref, urls, onUpdate),
              child: const Text('Add addon'),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Paste the full addon URL from your dashboard. Anyone holding '
            'it plays on your quota — keep the dashboard backup safe.',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }

  Future<void> _addAddonDialog(
    BuildContext context,
    WidgetRef ref,
    List<String> urls,
    Future<void> Function(Future<void> Function(Prefs)) onUpdate,
  ) async {
    final controller = TextEditingController();
    final pasted = await showDialog<String>(
      context: context,
      builder: (context) => ContentDialog(
        title: const Text('Add addon'),
        content: TextBox(
          controller: controller,
          placeholder: 'https://…/a/<token>/',
          maxLines: 2,
        ),
        actions: [
          Button(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    final raw = pasted ?? '';
    controller.dispose();
    if (raw.isEmpty || !context.mounted) return;
    final parsed = AddonApi.parseAddonUrl(raw);
    if (parsed == null) {
      if (context.mounted) {
        await showDialog(
          context: context,
          builder: (dialogContext) => ContentDialog(
            title: const Text('Not an addon URL'),
            content: const Text(
              'Expected something like https://host/a/<token>/.',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
      return;
    }
    AddonManifest? manifest;
    try {
      manifest = await AddonApi([parsed.root]).manifestFor(parsed.root);
    } catch (_) {
      manifest = null;
    }
    if (!context.mounted) return;
    if (manifest == null) {
      await showDialog(
        context: context,
        builder: (dialogContext) => ContentDialog(
          title: const Text('Addon unreachable'),
          content: const Text(
            'No usable addon answered there — revoked, offline, '
            'or wrong URL. Nothing was saved.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }
    final root = parsed.root;
    final next = [...urls.where((e) => e != root), root];
    await onUpdate((p) => p.setAddonUrls(next));
    ref.invalidate(losslessApiProvider);
    ref.invalidate(addonManifestProvider);
  }
}

class _AddonRow extends ConsumerWidget {
  final String url;
  final AddonQuota? quota;
  final Future<void> Function() onRemove;
  const _AddonRow({
    required this.url,
    required this.quota,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final manifest = ref.watch(addonManifestProvider(url)).valueOrNull;
    final host = Uri.tryParse(url)?.host ?? url;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          const Icon(FluentIcons.cloud, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  manifest?.name ?? host,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: WaveType.trackTitle,
                ),
                Text(
                  manifest == null ? '$host · unreachable' : host,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: WaveType.meta.copyWith(
                    color: waveTextSecondary(context),
                  ),
                ),
              ],
            ),
          ),
          Button(onPressed: () => onRemove(), child: const Text('Remove')),
        ],
      ),
    );
  }
}

class _About extends StatelessWidget {
  const _About();

  Future<void> _open(String url) async {
    final uri = Uri.parse(url);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return _Group(
      title: 'About Her Music',
      subtitle: 'Build and project links',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Her Music Desktop · v1.0.0', style: WaveType.trackTitle),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Button(
                onPressed: () =>
                    _open('https://github.com/ankitxrishav/Her-Music-Desktop'),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(FluentIcons.open_in_new_window, size: 14),
                    SizedBox(width: 6),
                    Text('GitHub repository'),
                  ],
                ),
              ),
              Button(
                onPressed: () => _open(
                  'https://github.com/ankitxrishav/Her-Music-Desktop/issues',
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(FluentIcons.error, size: 14),
                    SizedBox(width: 6),
                    Text('Report an issue'),
                  ],
                ),
              ),
              Button(
                onPressed: () =>
                    _open('https://github.com/ankitxrishav/Her-Music-Desktop'),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(FluentIcons.favorite_star, size: 14),
                    SizedBox(width: 6),
                    Text('Star / support the project'),
                  ],
                ),
              ),
              Button(
                onPressed: () =>
                    _open('https://github.com/ankitxrishav'),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TelegramIcon(size: 14),
                    SizedBox(width: 6),
                    Text('Developer Profile'),
                  ],
                ),
              ),
              Button(
                onPressed: () => _open(
                  'https://github.com/ankitxrishav/Her-Music-Desktop',
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DiscordIcon(size: 14),
                    SizedBox(width: 6),
                    Text('Project Releases'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _General extends ConsumerWidget {
  final Future<void> Function(Future<void> Function(Prefs)) onUpdate;
  const _General({required this.onUpdate});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(prefsProvider);
    return Column(
      children: [
        _Group(
          title: 'Behaviour',
          subtitle: 'Startup and window defaults',
          child: Column(
            children: [
              _SwitchRow(
                value: prefs.closeToTray,
                onChanged: (v) => onUpdate((p) => p.setCloseToTray(v)),
                title: 'Close button minimize to tray.',
                subtitle:
                    'Keep the player running in the background when closed.',
              ),
              const SizedBox(height: 8),
              _SwitchRow(
                value: prefs.discordRichPresence,
                onChanged: (v) async {
                  await onUpdate((p) => p.setDiscordRichPresence(v));
                  try {
                    ref.read(discordPresenceProvider).refresh();
                  } catch (_) {}
                },
                title: 'Discord Rich Presence',
                subtitle:
                    'Show the current track in your Discord status.',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Playback extends ConsumerWidget {
  final Future<void> Function(Future<void> Function(Prefs)) onUpdate;
  const _Playback({required this.onUpdate});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(prefsProvider);
    return _Group(
      title: 'Playback',
      subtitle: 'Gapless, crossfade and output behaviour',
      child: Column(
        children: [
          _SwitchRow(
            value: prefs.autoplaySimilar,
            onChanged: (v) => onUpdate((p) => p.setAutoplaySimilar(v)),
            title: 'Autoplay similar',
            subtitle: 'Keep playing related tracks after a queue ends',
          ),
          const SizedBox(height: 8),
          _SwitchRow(
            value: prefs.crossfadeEnabled,
            onChanged: (v) async {
              await onUpdate((p) => p.setCrossfade(v));
              ref.read(audioOutputProvider.notifier).refreshPath();
            },
            title: 'Crossfade',
            subtitle: '${prefs.crossfadeSeconds}s · gapless otherwise',
          ),
        ],
      ),
    );
  }
}

class _Downloads extends ConsumerWidget {
  final Future<void> Function(Future<void> Function(Prefs)) onUpdate;
  const _Downloads({required this.onUpdate});

  Future<void> _pickDir(WidgetRef ref) async {
    try {
      final path = await FilePicker.getDirectoryPath(
        dialogTitle: 'Choose download folder',
      );
      if (path == null || path.trim().isEmpty) return;
      await onUpdate((p) => p.setDownloadDir(path));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(prefsProvider);
    final custom = prefs.downloadDir;
    return _Group(
      title: 'Offline',
      subtitle: 'Download behaviour and lyrics sidecars',
      child: Column(
        children: [
          _SwitchRow(
            value: prefs.downloadLyrics,
            onChanged: (v) => onUpdate((p) => p.setDownloadLyrics(v)),
            title: 'Download lyrics',
            subtitle: 'Save synced .lrc sidecars with downloads',
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(
                  FluentIcons.open_folder_horizontal, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Save location',
                        style: WaveType.trackTitle),
                    Text(
                      custom.isEmpty
                          ? 'Default location'
                          : custom,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: WaveType.meta,
                    ),
                  ],
                ),
              ),
              Button(
                onPressed: () => _pickDir(ref),
                child: const Text('Change'),
              ),
              if (custom.isNotEmpty) ...[
                const SizedBox(width: 8),
                Button(
                  onPressed: () =>
                      onUpdate((p) => p.resetDownloadDir()),
                  child: const Text('Reset'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _LastFm extends ConsumerWidget {
  final Future<void> Function(Future<void> Function(Prefs)) onUpdate;
  const _LastFm({required this.onUpdate});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        _Account(onUpdate: onUpdate),
        const SizedBox(height: 8),
        const _ApiKeys(),
        const SizedBox(height: 8),
        _Scrobbler(onUpdate: onUpdate),
      ],
    );
  }
}

/// Last.fm BYOK editor: the user's own API key + shared secret.
///
/// Validated with a signed `auth.getToken` call before persisting;
/// saving *different* keys signs the session out (sessions belong to
/// their API key). Key values are never logged — only presence.
class _ApiKeys extends ConsumerStatefulWidget {
  const _ApiKeys();
  @override
  ConsumerState<_ApiKeys> createState() => _ApiKeysState();
}

class _ApiKeysState extends ConsumerState<_ApiKeys> {
  TextEditingController? _key;
  TextEditingController? _secret;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _key?.dispose();
    _secret?.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider.notifier).saveCustomKeys(
            _key?.text ?? '',
            _secret?.text ?? '',
          );
    } catch (e) {
      if (mounted) {
        setState(() => _error = _shortError(e));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clear() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider.notifier).clearCustomKeys();
      _key?.clear();
      _secret?.clear();
    } catch (e) {
      if (mounted) {
        setState(() => _error = _shortError(e));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static String _shortError(Object e) =>
      e.toString().replaceFirst('LastFmException(null): ', '');

  @override
  Widget build(BuildContext context) {
    // Subscribe to auth transitions so the status line below flips
    // right after save/clear: Prefs itself never notifies (see
    // welcome _AuthPanel — same pattern).
    ref.watch(authRepositoryProvider.select((s) => s.status));
    final prefs = ref.watch(prefsProvider);
    _key ??= TextEditingController(text: prefs.lastFmApiKey);
    _secret ??= TextEditingController(text: prefs.lastFmApiSecret);
    final configured = prefs.isLastFmConfigured;
    return _Group(
      title: 'API keys',
      subtitle: 'Your own keys from last.fm/api/account/create',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                configured
                    ? FluentIcons.check_mark
                    : FluentIcons.warning,
                size: 14,
                color: configured ? Colors.green : Colors.orange,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  configured
                      ? 'Keys saved — values never shown here'
                      : 'Not configured — Last.fm is disabled',
                  style: WaveType.meta,
                ),
              ),
              if (configured)
                Button(
                  onPressed: _busy ? null : _clear,
                  child: const Text('Clear'),
                ),
            ],
          ),
          const SizedBox(height: 10),
          const Text('API key', style: WaveType.label),
          const SizedBox(height: 4),
          TextBox(
            controller: _key,
            placeholder: '32-character hex key',
          ),
          const SizedBox(height: 8),
          const Text('Shared secret', style: WaveType.label),
          const SizedBox(height: 4),
          TextBox(
            controller: _secret,
            placeholder: 'Shared secret',
            obscureText: true,
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: WaveType.meta.copyWith(color: Colors.red),
            ),
          ],
          const SizedBox(height: 10),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: _busy
                ? const Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: ProgressRing(strokeWidth: 2),
                      ),
                      SizedBox(width: 8),
                      Text('Validating…'),
                    ],
                  )
                : const Text('Save & validate'),
          ),
          const SizedBox(height: 6),
          Text(
            'Saving different keys signs you out — sessions belong '
            'to their API key. Reconnect afterwards.',
            style: WaveType.meta.copyWith(
              color: waveTextTertiary(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _Experimental extends ConsumerWidget {
  final Future<void> Function(Future<void> Function(Prefs)) onUpdate;
  const _Experimental({required this.onUpdate});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(prefsProvider);
    return _Group(
      title: 'Experimental',
      subtitle: 'Opt-in desktop prototypes',
      child: Column(
        children: [
          _SwitchRow(
            value: prefs.liquidGlass,
            onChanged: (v) => onUpdate((p) => p.setLiquidGlass(v)),
            title: 'Extra translucency',
            subtitle: 'Stronger Haze on panels (may cost FPS)',
          ),
          _SwitchRow(
            value: prefs.wavySeekbar,
            onChanged: (v) => onUpdate((p) => p.setWavySeekbar(v)),
            title: 'Wavy seekbar',
            subtitle: 'Experimental timeline treatment',
          ),
        ],
      ),
    );
  }
}

class _WasapiOutputSettings extends ConsumerWidget {
  final Future<void> Function(Future<void> Function(Prefs)) onUpdate;
  const _WasapiOutputSettings({required this.onUpdate});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final output = ref.watch(audioOutputProvider);
    final notifier = ref.read(audioOutputProvider.notifier);
    final devices = output.devices;
    final selected = output.selectedId.isEmpty ? '' : output.selectedId;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Device', style: WaveType.trackTitle),
        const SizedBox(height: 6),
        ComboBox<String>(
          isExpanded: true,
          value: devices.any((d) => d.id == selected) ? selected : '',
          items: [
            const ComboBoxItem(value: '', child: Text('System Default')),
            for (final d in devices)
              ComboBoxItem(
                value: d.id,
                child: Text(
                  d.isDefault ? '${d.displayName} (default)' : d.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (v) async {
            if (v == null) return;
            await notifier.selectDevice(v);
            await onUpdate((_) async {});
          },
        ),
        const SizedBox(height: 10),
        if (Platform.isWindows)
          _SwitchRow(
            value: output.exclusiveRequested,
            onChanged: (v) async {
              await notifier.setExclusive(v);
              await onUpdate((_) async {});
            },
            title: 'WASAPI Exclusive',
            subtitle: output.path.bitPerfect
                ? 'Mixer bypassed · bit-perfect when the DAC matches the source'
                : (output.exclusiveRequested
                      ? output.path.reason.label
                      : 'Shared mode — mixer may resample'),
          ),
        const SizedBox(height: 8),
        Text(
          output.selected == null
              ? 'Probe the DAC after connecting it to see exclusive PCM rates.'
              : output.selected!.supportedSummary,
          style: WaveType.meta.copyWith(color: waveTextSecondary(context)),
        ),
        const SizedBox(height: 12),
        WaveStreamPathPanel(path: output.path),
      ],
    );
  }
}

class _QualityRow extends StatelessWidget {
  final String title;
  final int value;
  final ValueChanged<int> onChanged;
  const _QualityRow({
    required this.title,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: WaveType.trackTitle),
              Text(AudioQualityTiers.label(value), style: WaveType.meta),
            ],
          ),
        ),
        ComboBox<int>(
          value: value,
          items: const [
            ComboBoxItem(value: 27, child: Text('Hi-Res · 24/192')),
            ComboBoxItem(value: 7, child: Text('Hi-Res · 24/96')),
            ComboBoxItem(value: 6, child: Text('Lossless · 16/44.1')),
            ComboBoxItem(value: 5, child: Text('320k MP3')),
            ComboBoxItem(value: -1, child: Text('Opus · YouTube')),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ],
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final String title;
  final String? subtitle;
  const _SwitchRow({
    required this.value,
    required this.onChanged,
    required this.title,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: WaveType.trackTitle),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: WaveType.meta.copyWith(
                      color: waveTextSecondary(context),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          ToggleSwitch(checked: value, onChanged: onChanged),
        ],
      ),
    );
  }
}


class _AccountSync extends ConsumerStatefulWidget {
  final Future<void> Function(Future<void> Function(Prefs)) onUpdate;
  const _AccountSync({required this.onUpdate});

  @override
  ConsumerState<_AccountSync> createState() => _AccountSyncState();
}

class _AccountSyncState extends ConsumerState<_AccountSync> {
  late final TextEditingController _emailCtrl;

  @override
  void initState() {
    super.initState();
    final currentEmail = ref.read(coupleSyncProvider).myEmail;
    _emailCtrl = TextEditingController(text: currentEmail);
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sync = ref.watch(coupleSyncProvider);
    final ytConn = ref.watch(ytConnectionProvider);
    final ytLoggedIn = ytConn.connected;
    final account = ref.watch(ytAccountProvider).valueOrNull;
    final otherDevice = sync.otherDeviceSync;
    final dark = waveIsDark(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Group(
          title: "YouTube Music Account",
          subtitle: "Sign in to access your YouTube Music library, playlists & recommendations",
          trailing: FilledButton(
            onPressed: () => _Ytm.ytConnect(context, ref),
            child: Text(ytLoggedIn ? "Switch Account" : "Sign In with Google"),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: ytLoggedIn
                      ? const Color(0xFFFF0000).withValues(alpha: 0.15)
                      : (dark ? const Color(0x1AFFFFFF) : const Color(0x0A000000)),
                ),
                child: Center(
                  child: Icon(
                    FluentIcons.video,
                    color: ytLoggedIn ? const Color(0xFFFF0000) : waveTextSecondary(context),
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ytLoggedIn
                          ? (account?.name ?? "YouTube Music Connected")
                          : "Not signed in (Guest Mode)",
                      style: WaveType.trackTitle,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      ytLoggedIn
                          ? (account?.handle ?? "Syncing with your YouTube account")
                          : "Sign in via webview to access personal mixes and library",
                      style: WaveType.meta.copyWith(color: waveTextSecondary(context)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _Group(
          title: "Tri-Platform Cloud Sync (Android, macOS & Windows)",
          subtitle: "Synchronize playback, handoff songs, and link devices via your Google / Email ID",
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextBox(
                      controller: _emailCtrl,
                      placeholder: "Enter your email ID (e.g. yourname@gmail.com)",
                      prefix: const Padding(
                        padding: EdgeInsets.only(left: 10),
                        child: Icon(FluentIcons.mail, size: 16),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton(
                    onPressed: () {
                      final email = _emailCtrl.text.trim();
                      if (email.isNotEmpty) {
                        ref.read(coupleSyncProvider.notifier).setMyEmail(email);
                      }
                    },
                    child: const Text("Save & Connect"),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: dark ? const Color(0x12FFFFFF) : const Color(0x08000000),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: waveDivider(context)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          FluentIcons.cell_phone,
                          size: 16,
                          color: otherDevice != null ? const Color(0xFF10B981) : waveTextSecondary(context),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          otherDevice != null
                              ? "Active Device Linked: ${otherDevice.platform.toUpperCase()}"
                              : "Waiting for Android phone or other devices...",
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: otherDevice != null ? const Color(0xFF10B981) : null,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0x2210B981),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            "MQTT ACTIVE",
                            style: TextStyle(
                              color: Color(0xFF10B981),
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (otherDevice != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        "Now Playing on ${otherDevice.platform}: \"${otherDevice.title}\" by ${otherDevice.artist}",
                        style: WaveType.meta,
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          FilledButton(
                            onPressed: () => ref.read(coupleSyncProvider.notifier).handoffFromDevice(),
                            child: const Text("Handoff Playback to This Machine"),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CoupleSpaceSettings extends ConsumerStatefulWidget {
  final Future<void> Function(Future<void> Function(Prefs)) onUpdate;
  const _CoupleSpaceSettings({required this.onUpdate});

  @override
  ConsumerState<_CoupleSpaceSettings> createState() => _CoupleSpaceSettingsState();
}

class _CoupleSpaceSettingsState extends ConsumerState<_CoupleSpaceSettings> {
  late final TextEditingController _partnerEmailCtrl;
  late final TextEditingController _partnerCodeCtrl;

  @override
  void initState() {
    super.initState();
    final sync = ref.read(coupleSyncProvider);
    _partnerEmailCtrl = TextEditingController(text: sync.partnerEmail);
    _partnerCodeCtrl = TextEditingController(text: sync.partnerCode);
  }

  @override
  void dispose() {
    _partnerEmailCtrl.dispose();
    _partnerCodeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sync = ref.watch(coupleSyncProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Group(
          title: "Couple Space Status",
          subtitle: sync.isPaired
              ? "Paired with ${sync.partnerName.isNotEmpty ? sync.partnerName : sync.partnerRole} 💕"
              : "Link your app with your partner across Android, macOS, and Windows",
          trailing: sync.isPaired
              ? Button(
                  onPressed: () => ref.read(coupleSyncProvider.notifier).unpair(),
                  child: const Text("Unpair Space"),
                )
              : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: sync.isPaired ? const Color(0x3310B981) : const Color(0x33FF4081),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      sync.isPaired ? "PAIRED & SYNCHRONIZED 💕" : "NOT PAIRED",
                      style: TextStyle(
                        color: sync.isPaired ? const Color(0xFF10B981) : const Color(0xFFFF4081),
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (sync.isPaired) ...[
                    Text("Live Playback Sync", style: WaveType.meta),
                    const SizedBox(width: 8),
                    ToggleSwitch(
                      checked: sync.isLiveSyncing,
                      onChanged: (val) => ref.read(coupleSyncProvider.notifier).toggleLiveSync(val),
                    ),
                  ],
                ],
              ),
              if (sync.isPaired) ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    FilledButton(
                      onPressed: () => ref.read(coupleSyncProvider.notifier).pushCurrentSongToPartner(),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(FluentIcons.send, size: 14),
                          SizedBox(width: 6),
                          Text("Push Currently Playing Song Now"),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        if (!sync.isPaired) ...[
          const SizedBox(height: 16),
          _Group(
            title: "1-Click Direct Email Pairing",
            subtitle: "Enter both your email and your partner's email to auto-connect on all systems",
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextBox(
                  controller: _partnerEmailCtrl,
                  placeholder: "Partner's Google or Email ID",
                  prefix: const Padding(
                    padding: EdgeInsets.only(left: 10),
                    child: Icon(FluentIcons.heart, size: 16),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () {
                    final pEmail = _partnerEmailCtrl.text.trim();
                    if (pEmail.isNotEmpty) {
                      ref.read(coupleSyncProvider.notifier).linkByEmail(pEmail);
                    }
                  },
                  child: const Text("Connect by Email"),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _Group(
            title: "Invite Code Fallback",
            subtitle: "Share your 6-digit code or enter your partner's code",
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Your Invite Code: ${sync.myCode}", style: WaveType.trackTitle),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextBox(
                        controller: _partnerCodeCtrl,
                        placeholder: "Enter partner's 6-digit invite code",
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilledButton(
                      onPressed: () {
                        final code = _partnerCodeCtrl.text.trim();
                        if (code.isNotEmpty) {
                          ref.read(coupleSyncProvider.notifier).pairWithCode(code);
                        }
                      },
                      child: const Text("Pair with Code"),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
