import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:window_manager/window_manager.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:path/path.dart' as p;
import '../l10n/app_localizations.dart';
import '../models/server_config.dart';
import '../services/dufs_service.dart';
import 'settings_page.dart';
import 'log_page.dart';

class HomePage extends StatefulWidget {
  final ServerConfig config;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final ValueChanged<String> onColorChanged;
  final ValueChanged<String> onLanguageChanged;
  final VoidCallback? onCloseRequested;

  const HomePage({
    super.key,
    required this.config,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.onColorChanged,
    required this.onLanguageChanged,
    this.onCloseRequested,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with WindowListener, WidgetsBindingObserver {
  late ServerConfig _config;
  bool _showAdvanced = false;
  bool _enableAuth = false;
  bool _obscurePassword = true;
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  late final TextEditingController _portController;
  int _navIndex = 0;
  bool _isDragOver = false;
  bool _isServerTransitioning = false;
  bool _isStoppingServer = false;
  Timer? _portSaveDebounce;

  AppLocalizations get l10n => AppLocalizations(_config.language);

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    WidgetsBinding.instance.addObserver(this);
    _config = widget.config;
    _portController = TextEditingController(text: _config.port.toString());
    if (_config.auth != null && _config.auth!.contains(':')) {
      final parts = _config.auth!.split(':');
      _enableAuth = true;
      _usernameController.text = parts[0];
      _passwordController.text = parts.sublist(1).join(':');
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _checkServerOnResume();
    });
  }

  @override
  void dispose() {
    _portSaveDebounce?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    windowManager.removeListener(this);
    _usernameController.dispose();
    _passwordController.dispose();
    _portController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkServerOnResume();
    }
  }

  /// App 恢复前台时检测并恢复服务状态
  /// Native Service 决定运行状态；恢复工具服务或清理已停止的本地状态。
  Future<void> _checkServerOnResume() async {
    if (!Platform.isAndroid) return;
    final service = context.read<DufsService>();
    await service.restoreFromService();
  }

  Future<void> _saveConfig() async {
    _config.auth = _buildAuth();
    await _config.save();
  }

  String? _buildAuth() {
    if (!_enableAuth) return null;
    final user = _usernameController.text.trim();
    final pass = _passwordController.text.trim();
    if (user.isEmpty || pass.isEmpty) return null;
    return '$user:$pass';
  }

  @override
  void onWindowClose() {
    // Desktop OS-level close (Alt+F4 / window-manager close button) routes
    // through the same close-action flow as the custom title-bar button.
    // setPreventClose is on, so the window stays open until _handleClose acts.
    _handleClose();
  }

  Future<void> _handleClose() async {
    final service = context.read<DufsService>();
    final action = _config.closeAction;
    debugPrint('HomePage._handleClose: action=$action');
    if (action == 'exit') {
      await _exitApp(service);
      return;
    }
    if (action == 'tray') {
      windowManager.hide();
      return;
    }
    // action == 'ask': show dialog (context is inside MaterialApp, has MaterialLocalizations)
    final result = await _showCloseDialog();
    debugPrint('Close dialog result: $result');
    if (result == null) return;
    final actionResult = result['action'] as String;
    final dontAsk = result['dontAsk'] as bool;
    if (actionResult == 'tray') {
      windowManager.hide();
    } else {
      await _exitApp(service);
    }
    if (dontAsk) {
      _config.closeAction = actionResult;
      await _config.save();
    }
  }

  Future<Map<String, dynamic>?> _showCloseDialog() async {
    bool dontAsk = false;
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(l10n.t('home.closeTitle')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.minimize),
                title: Text(l10n.t('home.closeTray')),
                onTap: () =>
                    Navigator.pop(ctx, {'action': 'tray', 'dontAsk': dontAsk}),
              ),
              ListTile(
                leading: const Icon(Icons.exit_to_app),
                title: Text(l10n.t('home.closeExit')),
                onTap: () =>
                    Navigator.pop(ctx, {'action': 'exit', 'dontAsk': dontAsk}),
              ),
              const Divider(),
              CheckboxListTile(
                title: Text(l10n.t('home.closeDontAsk')),
                value: dontAsk,
                onChanged: (v) => setDialogState(() => dontAsk = v ?? false),
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _exitApp(DufsService service) async {
    if (service.isRunning) {
      await _runServerTransition(() async {
        await service.stopServer();
      }, stopping: true);
    }
    if (Platform.isAndroid) {
      SystemNavigator.pop();
      return;
    }
    // Desktop: terminate immediately. windowManager.destroy() has been observed
    // to block ~30s on Windows while native teardown waits on the dufs runtime's
    // lingering worker threads (server stop is intentionally non-blocking, so
    // those threads wind down in the background). Config is already persisted;
    // exit(0) closes instantly. Bound the tray cleanup so it can't reintroduce
    // the hang, and so the icon doesn't ghost until hover.
    try {
      await trayManager.destroy().timeout(const Duration(milliseconds: 500));
    } catch (_) {}
    exit(0);
  }

  Future<void> _pickDirectory() async {
    String? result;
    var pickerFailed = false;
    // Linux 上 file_picker 的 getDirectoryPath 走 XDG portal
    // OpenFile + directory:true，部分 portal 后端（尤其 Ubuntu 18.04 的
    // xdg-desktop-portal-gtk）忽略该选项，弹出文件选择器而非目录选择器。
    // 优先用桌面环境原生工具（zenity/kdialog），file_picker 兜底。
    if (Platform.isLinux) {
      final (path, handled) = await _pickDirLinuxNative();
      // handled=true 表示原生工具已给出确定结果（选中或明确取消），
      // 不再回退 file_picker；handled=false 表示无可用原生工具或工具
      // 异常退出（崩溃/无 display），继续走 file_picker 兜底。
      if (handled) {
        if (path != null) {
          await _applyDirPath(path);
        }
        return;
      }
      result = path;
    }
    // 非 Linux，或 Linux 无可用原生工具 → file_picker
    try {
      result ??= await FilePicker.platform.getDirectoryPath();
    } catch (e) {
      // Linux 走 XDG portal（DBus org.freedesktop.portal.Desktop）；无桌面
      // /无 portal 服务（如 Ubuntu 18.04 离线环境）时抛异常而非返回 null。
      debugPrint('pickDirectory failed: $e');
      pickerFailed = true;
    }
    if (result != null) {
      await _applyDirPath(result);
      return;
    }
    // 用户取消（result==null）不是失败，静默；仅工具抛异常才提示。
    if (pickerFailed) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.t('home.pickDirFailed'))));
    }
  }

  Future<void> _applyDirPath(String path) async {
    // 若 portal 返回文件路径而非目录（directory:true 被忽略），取父目录。
    // 注意：这是兜底猜测，原生工具路径下通常不会触发。
    final dir = await Directory(path).exists() ? path : p.dirname(path);
    setState(() {
      _config.path = dir;
      _config.shareSingleFile = false;
    });
    await _saveConfig();
  }

  /// Linux 遍历式尝试原生目录选择器（zenity → kdialog）。
  /// 返回 (路径, 是否已处理)：
  ///   - 选中目录 → (path, true)
  ///   - 用户明确取消（exit 1）→ (null, true)，不再回退 file_picker
  ///   - 工具不存在 / 异常退出（崩溃、无 display 等 exit>=2）→
  ///     (null, false)，由调用方回退 file_picker
  Future<(String?, bool)> _pickDirLinuxNative() async {
    final title = l10n.t('home.selectDir');
    // AppImage 通过 apprun hook 注入了自带的 GTK/GLib 库路径
    // （LD_LIBRARY_PATH / GTK_PATH / GSETTINGS_SCHEMA_DIR 等）。这些变量
    // 会被子进程继承，导致系统 zenity/kdialog 加载到版本不匹配的 GTK
    // 而崩溃或异常退出。这里显式清洗环境，让原生工具用系统库运行。
    final env = Map<String, String>.from(Platform.environment)
      ..remove('LD_LIBRARY_PATH')
      ..remove('LD_PRELOAD')
      ..remove('GTK_PATH')
      ..remove('GTK_DATA_PREFIX')
      ..remove('GSETTINGS_SCHEMA_DIR')
      ..remove('GIO_MODULE_DIR')
      ..remove('XDG_DATA_DIRS')
      ..remove('FONTCONFIG_PATH')
      ..remove('FONTCONFIG_FILE');
    final candidates = <List<String>>[
      ['zenity', '--file-selection', '--directory', '--title=$title'],
      // kdialog 的 --getexistingdirectory 会把后一个 arg 当作起始目录，
      // 因此 --title 必须放在 --getexistingdirectory 之前。
      [
        'kdialog',
        '--title',
        title,
        '--getexistingdirectory',
        Platform.environment['HOME'] ?? '/',
      ],
    ];
    for (final cmd in candidates) {
      ProcessResult r;
      try {
        r = await Process.run(
          cmd[0],
          cmd.sublist(1),
          environment: env,
          includeParentEnvironment: false,
        );
      } catch (_) {
        // 二进制不存在（ENOENT）→ 尝试下一个
        continue;
      }
      final path = (r.stdout as String).trim();
      if (r.exitCode == 0 && path.isNotEmpty) return (path, true); // 选中
      if (r.exitCode == 1) return (null, true); // 明确取消
      // exit >= 2：崩溃 / 无 display 等异常 → 视为未处理，回退 file_picker
    }
    return (null, false);
  }

  Future<void> _pickFile() async {
    PlatformFile? picked;
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        lockParentWindow: true,
      );
      // 部分平台取消时返回非 null 但空列表，`files.single` 会 StateError
      final files = result?.files ?? const <PlatformFile>[];
      picked = files.isNotEmpty ? files.single : null;
    } catch (e) {
      debugPrint('pickFile failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.t('home.pickDirFailed'))));
      return;
    }
    final pickedPath = picked?.path;
    if (pickedPath != null && pickedPath.isNotEmpty) {
      setState(() {
        _config.path = pickedPath;
        _config.shareSingleFile = true;
      });
      await _saveConfig();
    }
  }

  // ==================== Title Bar ====================

  Widget _buildTitleBar() {
    return GestureDetector(
      onPanStart: (_) => windowManager.startDragging(),
      child: Container(
        height: 48,
        color: Colors.transparent,
        child: Row(
          children: [
            const SizedBox(width: 12),
            Icon(
              Icons.swap_horiz,
              size: 18,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 6),
            Text(
              'FileInfra',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const Spacer(),
            _TitleBarButton(
              icon: Icons.remove,
              tooltip: l10n.t('window.minimize'),
              onPressed: () => windowManager.minimize(),
            ),
            _TitleBarButton(
              icon: Icons.crop_square,
              tooltip: l10n.t('window.toggleMaximize'),
              onPressed: () async {
                if (await windowManager.isMaximized()) {
                  windowManager.unmaximize();
                } else {
                  windowManager.maximize();
                }
              },
            ),
            _TitleBarButton(
              icon: Icons.close,
              tooltip: l10n.t('window.close'),
              isClose: true,
              onPressed: () => _handleClose(),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== Preset Dirs (Android) ====================

  Widget _buildPresetDirs() {
    if (Theme.of(context).platform != TargetPlatform.android) {
      return const SizedBox.shrink();
    }
    const presets = {
      'Download': '/storage/emulated/0/Download',
      'Documents': '/storage/emulated/0/Documents',
      'DCIM': '/storage/emulated/0/DCIM',
      'Movies': '/storage/emulated/0/Movies',
      'Music': '/storage/emulated/0/Music',
    };
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: presets.entries.map((e) {
        final sel = _config.path == e.value;
        return ActionChip(
          avatar: Icon(
            Icons.folder_outlined,
            size: 18,
            color: sel ? Theme.of(context).colorScheme.onPrimary : null,
          ),
          label: Text(
            e.key,
            style: TextStyle(
              color: sel ? Theme.of(context).colorScheme.onPrimary : null,
            ),
          ),
          backgroundColor: sel ? Theme.of(context).colorScheme.primary : null,
          onPressed: () async {
            setState(() {
              _config.path = e.value;
              _config.shareSingleFile = false;
            });
            await _saveConfig();
          },
        );
      }).toList(),
    );
  }

  // ==================== Dir Picker ====================

  Widget _buildDirPicker() {
    final isSingleFile = _config.shareSingleFile;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  isSingleFile ? Icons.insert_drive_file : Icons.folder_open,
                  size: 32,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isSingleFile
                            ? l10n.t('home.selectFile')
                            : l10n.t('home.selectDir'),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _config.path.isEmpty
                            ? (isSingleFile
                                  ? l10n.t('home.selectFile')
                                  : l10n.t('home.selectDir'))
                            : _config.path,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: _config.path.isEmpty
                              ? Theme.of(context).colorScheme.outline
                              : null,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: _pickDirectory,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(112, 48),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  icon: const Icon(Icons.folder_open),
                  label: Text(l10n.t('home.chooseFolder')),
                ),
                FilledButton.tonalIcon(
                  onPressed: _pickFile,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(112, 48),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  icon: const Icon(Icons.insert_drive_file_outlined),
                  label: Text(l10n.t('home.chooseFile')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ==================== Permission Presets ====================

  Widget _buildPermPresets(DufsService service) {
    final running = service.isRunning;
    return Row(
      children: [
        Expanded(
          child: FilterChip(
            avatar: const Icon(Icons.visibility, size: 18),
            label: Text(l10n.t('home.readonly')),
            selected: _config.readonly,
            showCheckmark: false,
            onSelected: running
                ? null
                : (_) async {
                    setState(() => _config.applyReadonly());
                    await _saveConfig();
                  },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FilterChip(
            avatar: const Icon(Icons.cloud_upload, size: 18),
            label: Text(l10n.t('home.upload')),
            selected:
                !_config.readonly &&
                _config.allowUpload &&
                !_config.allowDelete,
            showCheckmark: false,
            onSelected: running
                ? null
                : (_) async {
                    setState(() => _config.applyUpload());
                    await _saveConfig();
                  },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FilterChip(
            avatar: const Icon(Icons.lock_open, size: 18),
            label: Text(l10n.t('home.full')),
            selected:
                !_config.readonly && _config.allowUpload && _config.allowDelete,
            showCheckmark: false,
            onSelected: running
                ? null
                : (_) async {
                    setState(() => _config.applyFull());
                    await _saveConfig();
                  },
          ),
        ),
      ],
    );
  }

  // ==================== Custom Permissions ====================

  Widget _buildCustomPerms(DufsService service) {
    final running = service.isRunning;
    final singleFile = _config.shareSingleFile;
    final items = [
      {
        'label': l10n.t('home.allowUpload'),
        'value': _config.allowUpload,
        'icon': Icons.cloud_upload,
        'disabled': singleFile,
        'onChanged': (v) async {
          setState(() {
            _config.allowUpload = v;
            if (v) {
              _config.readonly = false;
              _config.allowSearch = true;
            }
          });
          await _saveConfig();
        },
      },
      {
        'label': l10n.t('home.allowDelete'),
        'value': _config.allowDelete,
        'icon': Icons.delete_outline,
        'disabled': singleFile,
        'onChanged': (v) async {
          setState(() {
            _config.allowDelete = v;
            if (v) {
              _config.readonly = false;
              _config.allowSearch = true;
            }
          });
          await _saveConfig();
        },
      },
      {
        'label': l10n.t('home.allowSearch'),
        'value': _config.allowSearch,
        'icon': Icons.search,
        'disabled': singleFile,
        'onChanged': (v) async {
          setState(() => _config.allowSearch = v);
          await _saveConfig();
        },
      },
      {
        'label': l10n.t('home.allowArchive'),
        'value': _config.allowArchive,
        'icon': Icons.folder_zip,
        'disabled': false,
        'onChanged': (v) async {
          setState(() => _config.allowArchive = v);
          await _saveConfig();
        },
      },
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Theme.of(
              context,
            ).colorScheme.outline.withValues(alpha: 0.15),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...items.map((item) {
              final disabled = item['disabled'] as bool;
              return SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                secondary: Icon(
                  item['icon'] as IconData,
                  size: 20,
                  color: (running || disabled)
                      ? Theme.of(context).colorScheme.outline
                      : null,
                ),
                title: Text(item['label'] as String),
                value: item['value'] as bool,
                onChanged: (running || disabled)
                    ? null
                    : (v) => (item['onChanged'] as Function(bool))(v),
              );
            }),
          ],
        ),
      ),
    );
  }

  Future<void> _runServerTransition(
    Future<void> Function() action, {
    required bool stopping,
  }) async {
    if (_isServerTransitioning) return;
    setState(() {
      _isServerTransitioning = true;
      _isStoppingServer = stopping;
    });
    try {
      await action();
    } finally {
      if (mounted) {
        setState(() {
          _isServerTransitioning = false;
          _isStoppingServer = false;
        });
        final service = context.read<DufsService>();
        final notice = service.portInfo;
        if (notice != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(notice),
              duration: const Duration(seconds: 4),
            ),
          );
          service.clearPortInfo();
        }
      }
    }
  }

  // ==================== Start/Stop Button ====================

  Widget _buildControlButton(DufsService service) {
    final running = service.isRunning;
    final busy = _isServerTransitioning;
    final label = busy
        ? (_isStoppingServer
              ? l10n.t('home.stoppingServer')
              : l10n.t('home.startingServer'))
        : (running ? l10n.t('home.stopServer') : l10n.t('home.startServer'));
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: FilledButton.icon(
        icon: busy
            ? SizedBox(
                width: 18,
                height: 18,
                child: _BouncingDots(
                  size: 18,
                  color: Theme.of(context).colorScheme.onSecondary,
                ),
              )
            : Icon(running ? Icons.stop : Icons.play_arrow),
        label: Text(label, style: const TextStyle(fontSize: 16)),
        style: FilledButton.styleFrom(
          foregroundColor: busy
              ? Theme.of(context).colorScheme.onSecondary
              : running
              ? Theme.of(context).colorScheme.onError
              : Theme.of(context).colorScheme.onPrimary,
          disabledBackgroundColor: busy
              ? Theme.of(context).colorScheme.secondary
              : null,
          disabledForegroundColor: busy
              ? Theme.of(context).colorScheme.onSecondary
              : null,
          backgroundColor: busy
              ? Theme.of(context).colorScheme.secondary
              : running
              ? Theme.of(context).colorScheme.error
              : Theme.of(context).colorScheme.primary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        onPressed: busy
            ? null
            : () async {
                if (running) {
                  await _runServerTransition(
                    () => service.stopServer(),
                    stopping: true,
                  );
                } else {
                  if (_enableAuth && _config.auth == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l10n.t('home.authRequired'))),
                    );
                    return;
                  }
                  await _runServerTransition(() async {
                    await _saveConfig();
                    await service.startServer(_config);
                  }, stopping: false);
                }
              },
      ),
    );
  }

  Widget _buildServerTransitionIndicator() {
    if (!_isServerTransitioning) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
        decoration: BoxDecoration(
          color: Theme.of(
            context,
          ).colorScheme.secondaryContainer.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.t('home.transitionHint'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSecondaryContainer,
              ),
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: const LinearProgressIndicator(minHeight: 5),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== Running Card (QR + Stats) ====================

  Widget _buildRunningCard(DufsService service) {
    if (!service.isRunning || service.serverUrl == null) {
      return const SizedBox.shrink();
    }
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            // Status dot
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  l10n.t('home.running'),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // QR Code
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Selector<DufsService, String?>(
                selector: (_, s) => s.serverUrl,
                builder: (_, url, _) => QrImageView(
                  data: url ?? '',
                  version: QrVersions.auto,
                  size: 140,
                  backgroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 8),
            // URL (tap to copy)
            InkWell(
              onTap: () {
                Clipboard.setData(ClipboardData(text: service.serverUrl!));
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(l10n.t('home.copyUrl'))));
              },
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        service.serverUrl!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(
                            context,
                          ).colorScheme.onPrimaryContainer,
                          decoration: TextDecoration.underline,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.copy,
                      size: 14,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            // IP + Hint（跟随默认地址）
            Text(
              '${l10n.t('home.localIp')}: ${service.preferredAddress ?? service.localIp ?? 'N/A'}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              l10n.t('home.scanHint'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 8),
            // Tools URL uses its own bounded row so long IPv6 URLs can shrink.
            if (service.clipboardUrl != null)
              Column(
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.content_paste,
                        size: 16,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          l10n.t('home.clipboard'),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                fontWeight: FontWeight.w500,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onPrimaryContainer,
                              ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.qr_code, size: 18),
                        onPressed: () => _showQrDialog(service.clipboardUrl!),
                        tooltip: l10n.t('home.qrCode'),
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ],
                  ),
                  InkWell(
                    onTap: () {
                      Clipboard.setData(
                        ClipboardData(text: service.clipboardUrl!),
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(l10n.t('home.copyUrl'))),
                      );
                    },
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 48),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              service.clipboardUrl!,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    decoration: TextDecoration.underline,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onPrimaryContainer,
                                  ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.copy,
                            size: 14,
                            color: Theme.of(
                              context,
                            ).colorScheme.onPrimaryContainer,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 8),
            // Stats
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.surface.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _stat(
                    context,
                    Icons.http,
                    '${service.totalRequests}',
                    l10n.t('home.statRequests'),
                  ),
                  Container(
                    width: 1,
                    height: 24,
                    color: Theme.of(
                      context,
                    ).colorScheme.outline.withValues(alpha: 0.2),
                  ),
                  _stat(
                    context,
                    Icons.access_time,
                    service.lastActivity ?? '--',
                    l10n.t('home.statLast'),
                  ),
                  Container(
                    width: 1,
                    height: 24,
                    color: Theme.of(
                      context,
                    ).colorScheme.outline.withValues(alpha: 0.2),
                  ),
                  InkWell(
                    onTap: () => _showLogPage(context),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      child: _stat(
                        context,
                        Icons.history,
                        '${service.transferLogs.length}',
                        l10n.t('log.title'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== Multi-NIC Address List ====================
  Widget _buildAddressList(DufsService service) {
    if (!service.isRunning) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        child: ExpansionTile(
          title: Row(
            children: [
              Icon(
                Icons.lan,
                size: 18,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  l10n.t('home.allAddresses'),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            ],
          ),
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          initiallyExpanded: false,
          children: service.allAddresses.asMap().entries.map((entry) {
            final idx = entry.key;
            final ip = entry.value;
            final ifaceName = idx < service.allInterfaceNames.length
                ? service.allInterfaceNames[idx]
                : '';
            // Use the actually-bound port from the service, not the user's
            // configured port — they may differ when conflict auto-bumped.
            final urlPort = service.activePort != 0
                ? service.activePort
                : _config.port;
            final url = 'http://${_formatHost(ip)}:$urlPort';
            // 默认地址跟随用户选择（service.preferredAddress），而不是固定第一个
            final isDefault = ip == service.preferredAddress;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isDefault
                      ? Theme.of(
                          context,
                        ).colorScheme.primaryContainer.withValues(alpha: 0.3)
                      : Theme.of(context).colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    // 设为默认星标
                    IconButton(
                      icon: Icon(
                        isDefault ? Icons.star : Icons.star_border,
                        size: 20,
                        color: isDefault
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.outline,
                      ),
                      onPressed: () {
                        if (isDefault) return;
                        _config.preferredAddress = ip;
                        _config.save();
                        service.setPreferredAddress(ip);
                      },
                      tooltip: l10n.t('home.setDefault'),
                      constraints: const BoxConstraints(
                        minWidth: 48,
                        minHeight: 48,
                      ),
                      padding: EdgeInsets.zero,
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (ifaceName.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.outline.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                ifaceName,
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                              ),
                            ),
                          Text(
                            url,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  fontWeight: isDefault
                                      ? FontWeight.w600
                                      : null,
                                  decoration: TextDecoration.underline,
                                ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    // 二维码按钮
                    IconButton(
                      icon: Icon(
                        Icons.qr_code,
                        size: 18,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      onPressed: () => _showQrDialog(url),
                      tooltip: l10n.t('home.qrCode'),
                      constraints: const BoxConstraints(
                        minWidth: 48,
                        minHeight: 48,
                      ),
                      padding: EdgeInsets.zero,
                    ),
                    // 复制按钮
                    IconButton(
                      icon: Icon(
                        Icons.copy,
                        size: 16,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      tooltip: l10n.t('home.copyAddress'),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: url));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('${l10n.t('home.copyUrl')}: $url'),
                          ),
                        );
                      },
                      constraints: const BoxConstraints(
                        minWidth: 48,
                        minHeight: 48,
                      ),
                      padding: EdgeInsets.zero,
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  /// 显示指定地址的二维码弹窗
  void _showQrDialog(String url) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: QrImageView(
                  data: url,
                  version: QrVersions.auto,
                  size: 200,
                  backgroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              InkWell(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: url));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l10n.t('home.copyUrl'))),
                  );
                  Navigator.pop(ctx);
                },
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Center(
                    child: Text(
                      url,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        decoration: TextDecoration.underline,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                l10n.t('home.scanHint'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// IPv6 地址加方括号：http://[fe80::1]:5000
  String _formatHost(String ip) => ip.contains(':') ? '[$ip]' : ip;


  Widget _stat(
    BuildContext context,
    IconData icon,
    String value,
    String label,
  ) {
    return Column(
      children: [
        Icon(
          icon,
          size: 18,
          color: Theme.of(context).colorScheme.onPrimaryContainer,
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.onPrimaryContainer,
          ),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.onPrimaryContainer,
          ),
        ),
      ],
    );
  }

  void _showLogPage(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(l10n.t('log.title'))),
          body: LogPage(config: _config),
        ),
      ),
    );
  }

  // ==================== Error Banner ====================

  Widget _buildError(DufsService service) {
    if (service.error == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            Icons.error_outline,
            color: Theme.of(context).colorScheme.onErrorContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              service.error!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 非阻断的可读性警告（Android 10/EMUI 分区存储下目录可能不可读，
  /// 但服务已启动）。用警告色区分于上方 errorContainer。
  Widget _buildReadableWarning(DufsService service) {
    final msg = service.androidReadableWarning;
    if (msg == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            color: Theme.of(context).colorScheme.onTertiaryContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              msg,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onTertiaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== Advanced Options ====================

  Widget _buildAdvancedOptions() {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        children: [
          // Port
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              decoration: InputDecoration(
                labelText: l10n.t('home.port'),
                prefixIcon: const Icon(Icons.numbers),
                helperText: l10n.t('home.portHint'),
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              controller: _portController,
              onSubmitted: (_) => _saveConfig(),
              onChanged: (v) {
                final port = int.tryParse(v);
                if (port != null && port >= 1 && port <= 65535) {
                  _config.port = port;
                  // 敲"5000"会触发 4 次保存写盘；防抖 500ms，回车立即落盘
                  _portSaveDebounce?.cancel();
                  _portSaveDebounce = Timer(
                    const Duration(milliseconds: 500),
                    _saveConfig,
                  );
                }
              },
            ),
          ),
          const SizedBox(height: 8),
          // Auth
          SwitchListTile(
            title: Text(l10n.t('home.enableAuth')),
            value: _enableAuth,
            onChanged: (v) {
              setState(() => _enableAuth = v);
              _saveConfig();
            },
          ),
          if (_enableAuth) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _usernameController,
                // dufs parses --auth as user:pass@path:perms, so ':' and '@'
                // in the username would corrupt the credential/path split.
                inputFormatters: [
                  FilteringTextInputFormatter.deny(RegExp(r'[:@]')),
                ],
                decoration: InputDecoration(
                  labelText: l10n.t('home.username'),
                  prefixIcon: const Icon(Icons.person),
                ),
                onChanged: (_) => _saveConfig(),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                // '@' separates the credential from the path in dufs --auth, so
                // deny it in the password to avoid corrupting the rule parse.
                inputFormatters: [
                  FilteringTextInputFormatter.deny(RegExp('@')),
                ],
                decoration: InputDecoration(
                  labelText: l10n.t('home.password'),
                  prefixIcon: const Icon(Icons.lock),
                  suffixIcon: IconButton(
                    tooltip: l10n.t(
                      _obscurePassword
                          ? 'home.showPassword'
                          : 'home.hidePassword',
                    ),
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off
                          : Icons.visibility,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
                onChanged: (_) => _saveConfig(),
              ),
            ),
          ],
          // CORS
          SwitchListTile(
            title: Text(l10n.t('home.cors')),
            subtitle: Text(
              l10n.t('home.corsHint'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            value: _config.cors,
            onChanged: (v) async {
              setState(() => _config.cors = v);
              await _saveConfig();
            },
          ),
          // Hide system files
          SwitchListTile(
            title: Text(l10n.t('home.hideSystemFiles')),
            subtitle: Text(
              l10n.t('home.hideSystemFilesHint'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            value: _config.hideSystemFiles,
            onChanged: (v) async {
              setState(() => _config.hideSystemFiles = v);
              await _saveConfig();
            },
          ),
          // Render try index
          SwitchListTile(
            title: Text(l10n.t('home.renderTryIndex')),
            subtitle: Text(
              l10n.t('home.renderTryIndexHint'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            value: _config.renderTryIndex,
            onChanged: (v) async {
              setState(() => _config.renderTryIndex = v);
              await _saveConfig();
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // ==================== Main Content ====================

  // ==================== Drop Handler ====================
  Widget _buildDropWrapper({required Widget child}) {
    // Only enable on desktop platforms
    final isDesktop =
        Theme.of(context).platform == TargetPlatform.windows ||
        Theme.of(context).platform == TargetPlatform.linux ||
        Theme.of(context).platform == TargetPlatform.macOS;
    if (!isDesktop) return child;

    return DropTarget(
      onDragDone: (detail) async {
        if (detail.files.isNotEmpty) {
          final file = detail.files.first;
          final filePath = file.path;
          bool isFile = false;
          String dirPath;
          try {
            final entityType = await FileSystemEntity.type(filePath);
            if (entityType == FileSystemEntityType.directory) {
              dirPath = filePath;
            } else {
              dirPath = File(filePath).parent.path;
              isFile = true;
            }
          } catch (_) {
            dirPath = File(filePath).parent.path;
            isFile = true;
          }
          setState(() {
            _config.path = isFile ? filePath : dirPath;
            _config.shareSingleFile = isFile;
            _isDragOver = false;
          });
          final displayName = (isFile ? filePath : dirPath)
              .split(Platform.pathSeparator)
              .last;
          await _saveConfig();
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${l10n.t(isFile ? 'home.dropFileSet' : 'home.dropSet')}: $displayName',
              ),
            ),
          );
        }
      },
      onDragEntered: (_) => setState(() => _isDragOver = true),
      onDragExited: (_) => setState(() => _isDragOver = false),
      child: child,
    );
  }

  Widget _buildHomeContent() {
    final service = context.watch<DufsService>();
    return _buildDropWrapper(
      child: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Title
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                  child: Column(
                    children: [
                      Text(
                        l10n.t('app.name'),
                        style: Theme.of(context).textTheme.headlineLarge
                            ?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                      ),
                      Text(
                        l10n.t('app.slogan'),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                // Preset dirs (Android)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _buildPresetDirs(),
                ),
                const SizedBox(height: 4),
                // Dir picker
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _buildDirPicker(),
                ),
                const SizedBox(height: 8),
                // Permission presets
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    l10n.t('home.permissionPreset'),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _buildPermPresets(service),
                ),
                // Custom permissions (collapsible)
                ExpansionTile(
                  title: Text(
                    l10n.t('home.customPerm'),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                  initiallyExpanded: false,
                  clipBehavior: Clip.hardEdge,
                  children: [_buildCustomPerms(service)],
                ),
                const SizedBox(height: 4),
                // Error
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _buildError(service),
                ),
                if (service.error != null) const SizedBox(height: 4),
                // Android 可读性警告（非阻断）：服务已启动但目录可能不可读
                if (service.androidReadableWarning != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _buildReadableWarning(service),
                  ),
                // Start/Stop
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _buildControlButton(service),
                ),
                _buildServerTransitionIndicator(),
                // Restart hint
                if (!service.isRunning && !_isServerTransitioning)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 2,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 14,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            l10n.t('home.restartHint'),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                // Running card (QR) - appears between button and advanced
                RepaintBoundary(child: _buildRunningCard(service)),
                // Multi-NIC address list
                _buildAddressList(service),
                const SizedBox(height: 4),
                // Advanced options (always at bottom)
                ExpansionTile(
                  title: Text(l10n.t('home.advanced')),
                  initiallyExpanded: _showAdvanced,
                  onExpansionChanged: (v) => setState(() => _showAdvanced = v),
                  clipBehavior: Clip.hardEdge,
                  children: [_buildAdvancedOptions()],
                ),
              ],
            ),
          ),
          // Drag & drop overlay
          if (_isDragOver)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.08),
                    border: Border.all(
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.5),
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  margin: const EdgeInsets.all(8),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.file_download_outlined,
                          size: 48,
                          color: Theme.of(
                            context,
                          ).colorScheme.primary.withValues(alpha: 0.6),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          l10n.t('home.dropHint'),
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ==================== Build ====================

  DateTime? _lastBackPress;

  @override
  Widget build(BuildContext context) {
    final pages = [
      _buildHomeContent(),
      SettingsPage(
        config: _config,
        onConfigChanged: _saveConfig,
        themeMode: widget.themeMode,
        onThemeModeChanged: widget.onThemeModeChanged,
        onColorChanged: widget.onColorChanged,
        onLanguageChanged: widget.onLanguageChanged,
      ),
    ];

    final scaffold = Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            if (Theme.of(context).platform == TargetPlatform.windows ||
                Theme.of(context).platform == TargetPlatform.linux ||
                Theme.of(context).platform == TargetPlatform.macOS)
              _buildTitleBar(),
            Expanded(
              child: AnimatedSwitcher(
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 150),
                child: KeyedSubtree(
                  key: ValueKey(_navIndex),
                  child: pages[_navIndex],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _navIndex,
        onDestinationSelected: (i) => setState(() => _navIndex = i),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(Icons.home),
            label: l10n.t('nav.home'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings),
            label: l10n.t('nav.settings'),
          ),
        ],
      ),
    );

    // Android: back button behavior
    if (Theme.of(context).platform == TargetPlatform.android) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          final service = context.read<DufsService>();
          if (service.isRunning) {
            // Server running: ask if user wants to stop and exit
            final confirmed = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Text(l10n.t('home.exitWhileRunning')),
                content: Text(l10n.t('home.exitWhileRunningMsg')),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: Text(
                      MaterialLocalizations.of(ctx).cancelButtonLabel,
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: Text(l10n.t('home.exitAndStop')),
                  ),
                ],
              ),
            );
            if (confirmed == true) {
              await _exitApp(service);
            }
          } else {
            // Server not running: double-press to exit
            final now = DateTime.now();
            if (_lastBackPress == null ||
                now.difference(_lastBackPress!) > const Duration(seconds: 2)) {
              _lastBackPress = now;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(l10n.t('home.exitConfirm')),
                  duration: const Duration(seconds: 2),
                ),
              );
            } else {
              SystemNavigator.pop();
            }
          }
        },
        child: scaffold,
      );
    }
    return scaffold;
  }
}

// Title bar button widget
class _TitleBarButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool isClose;
  const _TitleBarButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.isClose = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 48,
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            hoverColor: isClose
                ? Colors.red.withValues(alpha: 0.8)
                : Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.08),
            child: Icon(
              icon,
              size: 16,
              color: isClose
                  ? null
                  : Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ),
      ),
    );
  }
}

// Lightweight loading indicator for in-button use. Three dots animate via
// Transform.translate + Opacity only — no Canvas redraw per frame, so it
// stays smooth on devices where the Material CircularProgressIndicator
// stutters (notably 120Hz Android in debug).
class _BouncingDots extends StatefulWidget {
  final double size;
  final Color color;
  const _BouncingDots({required this.size, required this.color});

  @override
  State<_BouncingDots> createState() => _BouncingDotsState();
}

class _BouncingDotsState extends State<_BouncingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _ctrl.stop();
      _ctrl.value = 0.5;
    } else if (!_ctrl.isAnimating) {
      _ctrl.repeat();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dotSize = widget.size / 4.5;
    final amp = widget.size / 5;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: List.generate(3, (i) {
              final phase = (_ctrl.value - i * 0.18) % 1.0;
              // Parabolic hop in the first half of each cycle, rest in second.
              final t = (phase * 2.0).clamp(0.0, 1.0);
              final y = -amp * 4 * t * (1 - t);
              final alpha = 0.55 + 0.45 * (1 - (t - 0.5).abs() * 2);
              return Transform.translate(
                offset: Offset(0, y),
                child: Container(
                  width: dotSize,
                  height: dotSize,
                  decoration: BoxDecoration(
                    color: widget.color.withValues(alpha: alpha),
                    shape: BoxShape.circle,
                  ),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}
