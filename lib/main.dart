import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:tray_manager/tray_manager.dart';
import 'app.dart';
import 'models/server_config.dart';
import 'services/dufs_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Opt into the device's highest supported refresh rate on Android. Without
  // this call most OEMs (Xiaomi/OPPO/Realme/OnePlus) cap third-party apps at
  // 60Hz for power saving, which produces visible micro-judder on 90/120Hz
  // panels. Safe no-op on devices that only support 60Hz.
  if (Platform.isAndroid) {
    try {
      await FlutterDisplayMode.setHighRefreshRate();
    } catch (_) {
      // Some devices return errors from this API — ignore and accept 60Hz.
    }
  }

  // Pull the version from the platform package metadata so it always tracks
  // pubspec.yaml without manual sync. (See lib/app.dart::appVersion.)
  try {
    final pkgInfo = await PackageInfo.fromPlatform();
    appVersion = pkgInfo.version;
  } catch (_) {
    // Fallback already covered by `appVersion = '0.0.0'` initializer.
  }

  // Desktop: frameless window + system tray
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await windowManager.ensureInitialized();
    const windowOptions = WindowOptions(
      size: Size(420, 740),
      minimumSize: Size(360, 600),
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden,
    );
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.setPreventClose(true);
      await windowManager.show();
      await windowManager.focus();
    });
  }

  final config = await ServerConfig.load();

  runApp(
    ChangeNotifierProvider(
      create: (_) => DufsService(),
      child: FileInfraApp(config: config),
    ),
  );
}

class FileInfraApp extends StatefulWidget {
  final ServerConfig config;
  const FileInfraApp({super.key, required this.config});

  @override
  State<FileInfraApp> createState() => _FileInfraAppState();
}

class _FileInfraAppState extends State<FileInfraApp> with TrayListener, WindowListener {
  late ThemeMode _themeMode;
  late String _colorScheme;
  late String _language;
  late bool _setupDone;
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    _themeMode = _themeModeFromString(widget.config.themeMode);
    _colorScheme = widget.config.colorScheme;
    _language = widget.config.language;
    _setupDone = widget.config.setupDone;
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      windowManager.addListener(this);
    }
  }

  bool _trayInitialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_trayInitialized &&
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      _trayInitialized = true;
      _initTray();
    }
  }

  Future<void> _initTray() async {
    try {
      // Load asset bytes synchronously from context, before any other awaits
      final assetBundle = DefaultAssetBundle.of(context);
      final icoBytes = await assetBundle.load('assets/icon/tray_icon.ico');
      final pngBytes = await assetBundle.load('assets/icon/app_icon.png');
      if (!mounted) return;
      // Reuse a stable temp dir; createTemp() leaks a fresh fileinfra_trayXXXXXX
      // directory on every launch.
      final dir = Directory('${Directory.systemTemp.path}/fileinfra_tray');
      await dir.create(recursive: true);
      if (Platform.isWindows) {
        final iconFile = File('${dir.path}/tray_icon.ico');
        await iconFile.writeAsBytes(icoBytes.buffer.asUint8List());
        await trayManager.setIcon(iconFile.path);
      } else {
        final iconFile = File('${dir.path}/tray_icon.png');
        await iconFile.writeAsBytes(pngBytes.buffer.asUint8List());
        await trayManager.setIcon(iconFile.path);
      }
      // setToolTip throws MissingPluginException on Linux (tray_manager 0.5.2
      // doesn't implement it). Isolate the failure so the rest of init —
      // crucially the context menu — still runs.
      try {
        await trayManager.setToolTip('FileInfra');
      } catch (e) {
        debugPrint('Tray setToolTip skipped: $e');
      }

      // Small delay before setting context menu (Windows needs icon to be registered first)
      await Future.delayed(const Duration(milliseconds: 200));

      await trayManager.setContextMenu(
        Menu(
          items: [
            MenuItem(key: 'show', label: 'Show'),
            MenuItem(key: 'quit', label: 'Quit'),
          ],
        ),
      );
      trayManager.addListener(this);
      debugPrint('Tray initialized successfully');
    } catch (e) {
      debugPrint('Tray init failed: $e');
    }
  }

  @override
  void dispose() {
    trayManager.removeListener(this);
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  @override
  void onWindowClose() async {
    // HomePage owns the close flow (close-action dialog + clean server
    // shutdown) and registers its own WindowListener once mounted. Before setup
    // completes HomePage isn't shown, so handle the close here as a fallback;
    // otherwise defer to HomePage to avoid double-handling the event.
    if (!_setupDone) {
      // exit(0) rather than windowManager.destroy() — see the tray 'quit' note.
      // Pre-setup the server can't be running, so there's nothing to stop.
      exit(0);
    }
  }

  @override
  void onTrayIconMouseDown() async {
    // Single click: show and focus window
    await windowManager.show();
    await windowManager.focus();
  }

  @override
  void onTrayIconRightMouseDown() async {
    debugPrint('Tray right-click detected, popping up context menu');
    try {
      await trayManager.popUpContextMenu();
      debugPrint('popUpContextMenu completed');
    } catch (e) {
      debugPrint('popUpContextMenu error: $e');
    }
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    debugPrint('Tray menu clicked: ${menuItem.key}');
    switch (menuItem.key) {
      case 'show':
        await windowManager.show();
        await windowManager.focus();
        break;
      case 'quit':
        // Exit hard on desktop: windowManager.destroy() can block ~30s on
        // Windows waiting on the dufs runtime's lingering worker threads.
        try {
          await trayManager.destroy().timeout(
            const Duration(milliseconds: 500),
          );
        } catch (_) {}
        exit(0);
    }
  }

  ThemeMode _themeModeFromString(String s) {
    switch (s) {
      case 'dark':
        return ThemeMode.dark;
      case 'light':
        return ThemeMode.light;
      default:
        return ThemeMode.system;
    }
  }

  void _onThemeChanged(ThemeMode mode) {
    setState(() {
      _themeMode = mode;
      widget.config.themeMode = mode.name;
    });
    widget.config.save();
  }

  void _onColorChanged(String scheme) {
    setState(() {
      _colorScheme = scheme;
      widget.config.colorScheme = scheme;
    });
    widget.config.save();
  }

  void _onLanguageChanged(String code) {
    setState(() {
      _language = code;
      widget.config.language = code;
    });
    widget.config.save();
  }

  void _onSetupDone() {
    setState(() {
      _themeMode = _themeModeFromString(widget.config.themeMode);
      _colorScheme = widget.config.colorScheme;
      _language = widget.config.language;
      _setupDone = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return App(
      config: widget.config,
      themeMode: _themeMode,
      colorScheme: _colorScheme,
      language: _language,
      setupDone: _setupDone,
      onThemeModeChanged: _onThemeChanged,
      onColorChanged: _onColorChanged,
      onLanguageChanged: _onLanguageChanged,
      onSetupDone: _onSetupDone,
      onCloseRequested: () => onWindowClose(),
      navigatorKey: _navigatorKey,
    );
  }
}
