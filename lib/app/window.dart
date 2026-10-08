import 'dart:ffi' hide Size;
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'package:flutter/services.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

/// Desktop platform integration: native Mica/acrylic materials,
/// custom window chrome, tray, global hotkeys.
///
/// Everything is best-effort — failures are swallowed so the app
/// always starts, even on platforms missing a backend. Opaque
/// observatory surfaces are the polished fallback.
Future<void> setupWindow() async {
  _setMacDockIcon();
  await _setupAcrylic();
  try {
    await windowManager.ensureInitialized();
    // Route every close request (× button, Alt+F4) through Dart
    // instead of raw GTK destroy: the shell decides hide-to-tray vs
    // ordered quit. Without this, Alt+F4 tears the engine down while
    // libmpv's thread is still calling into Dart (startup crash).
    await windowManager.setPreventClose(true);
    const options = WindowOptions(
      size: Size(1360, 860),
      minimumSize: Size(1024, 640),
      center: true,
      title: 'Her Music',
      titleBarStyle: TitleBarStyle.hidden,
      // Neutral graphite — matches WaveColors.background so first frame
      // never flashes navy in either theme.
      backgroundColor: Color(0xFF0E0E0E),
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  } catch (_) {}
  await _setupTray();
  await _setupHotkeys();
}

Future<void> _setupAcrylic() async {
  try {
    await Window.initialize();
    // Mica incorporates wallpaper + theme: the native observatory
    // base. Tinted dark; light pearl theme switches at runtime.
    await Window.setEffect(
      effect: WindowEffect.mica,
      dark: true,
    );
  } catch (_) {
    // Opaque fallback is the designed default — remain readable.
  }
}

/// Switch the native material when the pearl/midnight theme changes.
Future<void> applyWindowMaterial({required bool isLight}) async {
  try {
    await Window.setEffect(
      effect: WindowEffect.mica,
      dark: !isLight,
    );
  } catch (_) {}
}

Future<void> _setupTray() async {
  try {
    String iconPath = Platform.isWindows 
      ? 'assets/icons/tray_icon.ico' 
      : 'assets/icons/tray_icon.png';

    await trayManager.setIcon(iconPath);
    if (!Platform.isLinux) {
      await trayManager.setToolTip('Her Music');
    }
    await trayManager.setContextMenu(Menu(items: [
      MenuItem(key: 'show', label: 'Show Her Music'),
      MenuItem.separator(),
      MenuItem(key: 'toggle', label: 'Play / Pause  (Ctrl+Alt+P)'),
      MenuItem(key: 'next', label: 'Next  (Ctrl+Alt+N)'),
      MenuItem(key: 'prev', label: 'Previous  (Ctrl+Alt+B)'),
      MenuItem.separator(),
      MenuItem(key: 'quit', label: 'Quit'),
    ]));
  } catch (_) {}
}

/// Whether the OS backend can deliver *global* transport hotkeys.
///
/// libkeybinder (hotkey_manager_linux) is X11-only: on Wayland sessions
/// (`WAYLAND_DISPLAY` set) registration always fails with
/// `Binding '<Primary><Alt>…' failed!` warnings and the keys stay dead.
/// Shell UI must offer the same combos as in-app shortcuts instead.
bool get globalHotkeysSupported {
  if (!Platform.isLinux) return true;
  return Platform.environment['WAYLAND_DISPLAY'] == null;
}

Future<void> _setupHotkeys() async {
  // Global transport: Ctrl+Alt+P play/pause, Ctrl+Alt+N next,
  // Ctrl+Alt+B previous. Handlers are wired in the shell via
  // hotKeyManager.keyDownHandler forwarding to PlaybackService —
  // see WaveShell initState. Registration here stays best-effort so
  // a missing backend never blocks startup.
  // Wayland has no global-hotkey backend: skip registration so the
  // native plugin never logs `Binding '<Primary><Alt>…' failed!`.
  // The shell falls back to in-app shortcuts (globalHotkeysSupported).
  if (!globalHotkeysSupported) return;
  try {
    await hotKeyManager.unregisterAll();
    final bindings = [
      HotKey(
        key: PhysicalKeyboardKey.keyP,
        modifiers: [HotKeyModifier.control, HotKeyModifier.alt],
        identifier: 'hermusic-toggle',
      ),
      HotKey(
        key: PhysicalKeyboardKey.keyN,
        modifiers: [HotKeyModifier.control, HotKeyModifier.alt],
        identifier: 'hermusic-next',
      ),
      HotKey(
        key: PhysicalKeyboardKey.keyB,
        modifiers: [HotKeyModifier.control, HotKeyModifier.alt],
        identifier: 'hermusic-prev',
      ),
    ];
    for (final binding in bindings) {
      await hotKeyManager.register(
        binding,
        // No-op here: the live shell overrides keyDownHandler with a
        // Riverpod-aware dispatcher once providers exist.
        keyDownHandler: (_) {},
      );
    }
  } catch (_) {}
}

void _setMacDockIcon() {
  if (!Platform.isMacOS) return;
  try {
    final candidatePaths = [
      '${Platform.resolvedExecutable.replaceAll(RegExp(r'/Contents/MacOS/.*'), '')}/Contents/Resources/AppIcon.icns',
      '/Applications/Her Music.app/Contents/Resources/AppIcon.icns',
    ];
    String? validPath;
    for (final p in candidatePaths) {
      if (File(p).existsSync()) {
        validPath = p;
        break;
      }
    }
    if (validPath == null) return;

    final objc = DynamicLibrary.process();
    final objcGetClass = objc.lookupFunction<Pointer<Void> Function(Pointer<Utf8>), Pointer<Void> Function(Pointer<Utf8>)>('objcGetClass');
    final selRegisterName = objc.lookupFunction<Pointer<Void> Function(Pointer<Utf8>), Pointer<Void> Function(Pointer<Utf8>)>('selRegisterName');
    final msgSend = objc.lookup<NativeFunction<Pointer<Void> Function(Pointer<Void>, Pointer<Void>)>>('objc_msgSend').asFunction<Pointer<Void> Function(Pointer<Void>, Pointer<Void>)>();
    final msgSend1 = objc.lookup<NativeFunction<Pointer<Void> Function(Pointer<Void>, Pointer<Void>, Pointer<Void>)>>('objc_msgSend').asFunction<Pointer<Void> Function(Pointer<Void>, Pointer<Void>, Pointer<Void>)>();

    final nsAppClass = objcGetClass('NSApplication'.toNativeUtf8());
    final sharedAppSel = selRegisterName('sharedApplication'.toNativeUtf8());
    final app = msgSend(nsAppClass, sharedAppSel);

    final nsImageClass = objcGetClass('NSImage'.toNativeUtf8());
    final allocSel = selRegisterName('alloc'.toNativeUtf8());
    final initPathSel = selRegisterName('initWithContentsOfFile:'.toNativeUtf8());

    final nsStringClass = objcGetClass('NSString'.toNativeUtf8());
    final strSel = selRegisterName('stringWithUTF8String:'.toNativeUtf8());
    final nsPath = msgSend1(nsStringClass, strSel, validPath.toNativeUtf8().cast());

    final uninitImage = msgSend(nsImageClass, allocSel);
    final image = msgSend1(uninitImage, initPathSel, nsPath);

    final setIconSel = selRegisterName('setApplicationIconImage:'.toNativeUtf8());
    msgSend1(app, setIconSel, image);
  } catch (_) {}
}
