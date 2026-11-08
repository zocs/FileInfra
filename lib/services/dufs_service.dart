import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../constants.dart';
import '../l10n/app_localizations.dart';
import '../models/server_config.dart';
import '../models/transfer_log.dart';
import 'dufs_ffi.dart';
import 'clipboard_service.dart';

/// Whether to use FFI (in-process) instead of spawning dufs as child process.
/// Desktop platforms (Linux/macOS/Windows) use FFI to avoid AppImage sandbox,
/// antivirus interception, and orphan process issues.
bool get _isAndroid =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

bool get _isIOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

bool get _useFfi =>
    !_isAndroid &&
    !_isIOS &&
    (Platform.isLinux || Platform.isMacOS || Platform.isWindows);

class DufsService extends ChangeNotifier {
  static const _ch = MethodChannel(kMethodChannel);
  static DufsService? _nativeChannelOwner;
  bool _disposed = false;
  int? _nativeGeneration;
  int _lastStoppedNativeGeneration = -1;
  int _restoreGeneration = 0;
  Future<void> _toolsTransition = Future<void>.value();
  Future<void>? _stopTransition;

  DufsService() {
    if (_isAndroid) {
      _nativeChannelOwner = this;
      _ch.setMethodCallHandler(_handleNativeCall);
    }
  }

  Future<void> _handleNativeCall(MethodCall call) async {
    if (call.method != 'serviceStopped' || _disposed) return;
    final generation = (call.arguments as Map?)?['generation'] as int?;
    if (generation == null) return;
    if (generation > _lastStoppedNativeGeneration) {
      _lastStoppedNativeGeneration = generation;
    }
    if (generation != _nativeGeneration) return;
    ++_startGeneration;
    _clearRunningState();
    await _stopTools();
    _notifyState();
  }

  void _notifyState() {
    if (!_disposed) notifyListeners();
  }

  bool _nativeRunWasStopped(int? generation) =>
      generation != null && generation <= _lastStoppedNativeGeneration;

  bool _operationIsCurrent(int generation, {int? restoreGeneration}) =>
      !_disposed &&
      generation == _startGeneration &&
      (restoreGeneration == null || restoreGeneration == _restoreGeneration);

  Future<void> _stopTools() {
    final operation = _toolsTransition.then((_) => _clipboard.stop());
    _toolsTransition = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> _startTools(int generation, int port, {int? restoreGeneration}) {
    final operation = _toolsTransition.then((_) async {
      if (!_operationIsCurrent(
            generation,
            restoreGeneration: restoreGeneration,
          ) ||
          !_isRunning) {
        return;
      }
      if (!_clipboard.isRunning) await _clipboard.start(port);
      if (!_operationIsCurrent(
            generation,
            restoreGeneration: restoreGeneration,
          ) ||
          !_isRunning) {
        await _clipboard.stop();
      }
    });
    _toolsTransition = operation.catchError((Object _) {});
    return operation;
  }

  /// --log-file 轮转上限：超限即在读取后截断（内容已入 UI），防长会话
  /// 无界增长（F3 的 Dart 侧缓解；dufs 以追加模式写，截断后继续从 0 写）。
  static const _kMaxLogBytes = 16 * 1024 * 1024;

  final DufsFfi _dufsFfi = DufsFfi();
  Process? _process;

  /// iOS 子进程退出码；startServer 的 300ms 等待后非空即视为启动失败。
  int? _processExitCode;
  bool _isRunning = false;

  /// 重入守卫：_isRunning 要到启动链尾段才置位，resume 恢复与用户点击
  /// 可并发触发两次启动（UI 的 _isServerTransitioning 只护住按钮）。
  bool _isStarting = false;
  final ClipboardService _clipboard = ClipboardService();

  /// 当前 UI 语言，用于服务层错误/提示文案。
  String _lang = 'zh';
  String? _serverUrl;
  String? _localIp;
  String? _error;

  /// 启动时由 _probeReadable 设置的 Android 目录可读性警告（非阻断），
  /// 在服务启动后由 UI 展示，告知用户 dufs 可能无法读取该目录下的文件。
  String? _androidReadableWarning;
  int _totalRequests = 0;
  String? _lastActivity;
  DateTime? _lastActivityAt;
  List<String> _allAddresses = [];

  /// 网卡名称列表，与 allAddresses 一一对应
  List<String> _allInterfaceNames = [];

  /// 用户选定的优先展示地址（默认地址）；null = 列表第一个
  String? _preferredAddress;
  String? get preferredAddress => _preferredAddress;

  /// 实际绑定的端口（可能因冲突自动 +1，与 ServerConfig.port 解耦）
  int _activePort = 0;

  /// 传输日志（最新的在前）
  final List<TransferLog> _transferLogs = [];

  bool get isRunning => _isRunning;
  String? get serverUrl => _serverUrl;

  /// 剪贴板旁路服务展示地址（host 复用主服务地址，端口 = dufs 端口 + 2000）。
  /// 服务未启动或剪贴板服务未绑定成功时返回 null。
  String? get clipboardUrl {
    if (!_isRunning || _serverUrl == null) return null;
    final host = Uri.parse(_serverUrl!).host;
    final cbPort = _clipboard.port;
    if (cbPort == null) return null;
    final h = host.contains(':') ? '[$host]' : host;
    return 'http://$h:$cbPort';
  }

  /// 剪贴板服务启动失败原因（成功启动时为 null）。
  String? get clipboardError => _clipboard.lastError;
  String? get localIp => _localIp;
  String? get error => _error;

  /// 服务启动时探测目录不可读的警告（Android 非阻断场景）。
  String? get androidReadableWarning => _androidReadableWarning;
  String? get portInfo => _portInfo;

  /// Port the running server is actually bound to. Differs from the
  /// user-configured `ServerConfig.port` when `_resolvePort` had to bump
  /// the port to find a free one. UI should prefer this for URLs while
  /// keeping ServerConfig.port as the user's stored preference.
  int get activePort => _activePort;
  int get totalRequests => _totalRequests;
  String? get lastActivity => _lastActivity;

  /// Time since the last parsed request, or null if none yet. Lets the UI
  /// tell "transfer likely in progress" from "idle after a past request".
  Duration? get timeSinceLastActivity => _lastActivityAt == null
      ? null
      : DateTime.now().difference(_lastActivityAt!);
  List<String> get allAddresses => _allAddresses;
  List<String> get allInterfaceNames => _allInterfaceNames;
  List<TransferLog> get transferLogs => List.unmodifiable(_transferLogs);

  /// Transient one-shot notice ("原端口 5000 被占用，已切到 5001"). UI consumes
  /// via [portInfo] then calls [clearPortInfo] to dismiss.
  String? _portInfo;
  void clearPortInfo() {
    _portInfo = null;
  }

  void _log(String msg) {
    debugPrint(msg);
    // ignore: body_might_complete_normally_catch_error
    if (_isAndroid) {
      _ch.invokeMethod('log', {'msg': msg}).catchError((_) {});
    }
  }

  AppLocalizations get _l10n => AppLocalizations(_lang);

  String _t(String key, Map<String, String> params) {
    var s = _l10n.t(key);
    params.forEach((k, v) => s = s.replaceAll('{$k}', v));
    return s;
  }

  Future<String?> _getWifiIP() async {
    try {
      return await NetworkInfo().getWifiIP();
    } catch (_) {
      return null;
    }
  }

  /// IPv6 地址加方括号：http://[fe80::1]:5000
  static String _formatHost(String ip) => ip.contains(':') ? '[$ip]' : ip;

  /// 切换优先展示的地址（默认地址）并更新 serverUrl。
  /// ip 不在当前地址列表时忽略（保留原默认）。
  void setPreferredAddress(String? ip) {
    if (ip == null || !_allAddresses.contains(ip)) return;
    _preferredAddress = ip;
    _serverUrl = 'http://${_formatHost(ip)}:$_activePort';
    _notifyState();
    // 服务运行中则同步通知栏地址（Kotlin 侧 no-op if 未运行）。
    if (_isAndroid && _isRunning) {
      final cbUrl = _clipboard.port != null
          ? 'http://${_formatHost(ip)}:${_clipboard.port}'
          : '';
      _ch
          .invokeMethod('updateNotificationAddress', {
            'address': _serverUrl!,
            'clipboardAddress': cbUrl,
            'generation': _nativeGeneration,
          })
          .catchError((_) {});
    }
  }

  /// 获取所有可用网络接口的 IPv4 地址及网卡名称
  Future<Map<String, List<String>>> _getAllAddresses() async {
    final addresses = <String>[];
    final names = <String>[];
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (addr.address != '127.0.0.1' &&
              !addresses.contains(addr.address)) {
            addresses.add(addr.address);
            names.add(iface.name);
          }
        }
      }
    } catch (_) {}
    return {'addresses': addresses, 'names': names};
  }

  Future<bool> _isPortAvailable(int port) async {
    try {
      final socket = await ServerSocket.bind(InternetAddress.anyIPv4, port);
      await socket.close();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 检查端口是否被占用（公共方法，用于恢复状态检测）
  Future<bool> isPortInUse(int port) async => !(await _isPortAvailable(port));

  /// Resolve the actually-bindable port given a requested one.
  ///
  /// Strategy:
  ///   1. Try the requested port. If free, use it.
  ///   2. If busy, try to identify and stop a leftover dufs process
  ///      that is holding it (same user only). Re-probe.
  ///   3. If still busy, scan +1, +2, ... up to +9. Return the first free.
  ///   4. None free in range → throw.
  ///
  /// Sets [_portInfo] with a user-facing message when an automatic decision
  /// was made (orphan killed, port bumped). UI is expected to surface and
  /// then [clearPortInfo].
  Future<int> _resolvePort(int requestedPort, int generation) async {
    const maxBump = 9;
    final requestedAvailable = await _isPortAvailable(requestedPort);
    if (!_operationIsCurrent(generation) || requestedAvailable) {
      return requestedPort;
    }

    _log('Port $requestedPort in use, attempting orphan cleanup...');
    await _killOrphanDufs(requestedPort);
    if (!_operationIsCurrent(generation)) return requestedPort;
    await Future.delayed(const Duration(milliseconds: 400));
    if (!_operationIsCurrent(generation)) return requestedPort;
    final cleanedPortAvailable = await _isPortAvailable(requestedPort);
    if (!_operationIsCurrent(generation)) return requestedPort;
    if (cleanedPortAvailable) {
      _portInfo = _t('srv.orphanKilled', {'port': '$requestedPort'});
      return requestedPort;
    }

    for (var bump = 1; bump <= maxBump; bump++) {
      final candidate = requestedPort + bump;
      final candidateAvailable = await _isPortAvailable(candidate);
      if (!_operationIsCurrent(generation)) return requestedPort;
      if (candidateAvailable) {
        _portInfo = _t('srv.portBumped', {
          'from': '$requestedPort',
          'to': '$candidate',
        });
        return candidate;
      }
    }
    throw Exception(
      _t('srv.portsExhausted', {
        'range': '$requestedPort..${requestedPort + maxBump}',
      }),
    );
  }

  /// 强制清理占用端口的 dufs 孤儿进程。
  ///
  /// Android 限制：没有 root 拿不到端口→PID 映射（lsof/ss 不可用），只能
  /// 按 cmdline 匹配杀所有 libdufs.so 进程——多个 FileInfra 实例并存的
  /// 场景会误杀，接受此权衡（桌面走 FFI 进程内无孤儿，iOS 无从下手）。
  Future<void> killOrphanOnPort(int port) async {
    try {
      await Process.run('pkill', [
        '-f',
        'libdufs.so',
      ]).catchError((_) => ProcessResult(0, 1, '', ''));
      _log('Cleaned up orphan dufs (pkill libdufs.so), port hint=$port');
    } catch (e) {
      _log('Failed to clean orphan on port $port: $e');
    }
  }

  /// 清理可能残留的 dufs 孤儿进程（占用了目标端口的）。
  /// 仅 Android 有意义：桌面走 FFI（进程内，无孤儿进程），iOS 无法这样杀子进程。
  /// (The old Windows/macOS/Linux branches were dead: `_useFfi` covers all three
  /// desktop platforms and returns above, so only the Android path ever ran.)
  Future<void> _killOrphanDufs(int port) async {
    if (_useFfi) return; // desktop: dufs runs in-process, no orphan to kill
    if (!_isAndroid) return; // iOS: can't kill the child this way
    try {
      await Process.run('pkill', [
        '-f',
        'libdufs.so',
      ]).catchError((_) => ProcessResult(0, 1, '', ''));
      _log('Cleaned up orphan dufs on port $port');
    } catch (e) {
      _log('Failed to kill orphan dufs: $e');
    }
  }

  Future<bool> _prepareLogFile(int generation, {int? restoreGeneration}) async {
    final tmpDir = await getTemporaryDirectory();
    if (!_operationIsCurrent(
      generation,
      restoreGeneration: restoreGeneration,
    )) {
      return false;
    }
    final logFilePath = '${tmpDir.path}/fileinfra_dufs.log';
    try {
      final logFile = await File(
        logFilePath,
      ).open(mode: FileMode.writeOnlyAppend);
      try {
        if (!_operationIsCurrent(
          generation,
          restoreGeneration: restoreGeneration,
        )) {
          return false;
        }
        logFile.truncateSync(0);
      } finally {
        await logFile.close();
      }
    } catch (_) {}
    if (!_operationIsCurrent(
      generation,
      restoreGeneration: restoreGeneration,
    )) {
      return false;
    }
    _logFilePath = logFilePath;
    _logFilePosition = 0;
    _logFileRemainder = '';
    return true;
  }

  Future<void> startServer(ServerConfig config) async {
    if (_disposed || _isRunning || _isStarting || _stopTransition != null) {
      return;
    }
    _isStarting = true;
    final generation = ++_startGeneration;
    try {
      await _startServerLocked(config, generation);
    } finally {
      _isStarting = false;
    }
  }

  Future<void> _startServerLocked(ServerConfig config, int generation) async {
    _lang = config.language;
    // 重置上轮残留的可读性警告：它只应在“服务真的启动成功”时展示，
    // 否则启动中任一后续失败（权限/端口/服务拉起）会让 UI 同时显示
    // 错误 + “已启动但目录不可读”的矛盾警告。
    _androidReadableWarning = null;
    if (!await _prepareLogFile(generation)) return;
    if (config.path.isEmpty) {
      _error = _l10n.t('srv.noDir');
      _notifyState();
      return;
    }
    // 单文件模式检查文件是否存在，目录模式检查目录是否存在
    if (config.shareSingleFile) {
      final fileExists = await File(config.path).exists();
      if (!_operationIsCurrent(generation)) return;
      if (!fileExists) {
        _error = _l10n.t('srv.fileGone');
        _notifyState();
        return;
      }
      final parentDir = p.dirname(config.path);
      final parentExists = await Directory(parentDir).exists();
      if (!_operationIsCurrent(generation)) return;
      if (!parentExists) {
        _error = _l10n.t('srv.parentGone');
        _notifyState();
        return;
      }
    } else {
      final directoryExists = await Directory(config.path).exists();
      if (!_operationIsCurrent(generation)) return;
      if (!directoryExists) {
        _error = _l10n.t('srv.dirGone');
        _notifyState();
        return;
      }
    }
    // exists() 通过不代表 dufs 读得了：能 stat 不能 opendir 的目录（Android 10
    // 分区存储、内存卡、Android/data 下）会让 dufs 对每个请求回 403 Forbidden
    // （server.rs handle_list_dir ← fs::read_dir 报错），而 UI 照样把二维码和
    // URL 递出去。启动前先按 dufs 的读法探一次。
    //
    // 平台差异：桌面（Linux/macOS/Windows）探测失败 = 权限位/网络盘真的读不了，
    // 直接拒绝启动（否则启动一个必然 403 的服务）。Android 10/EMUI 在
    // targetSdk≥30 时 scoped storage 生效，即使 READ_EXTERNAL_STORAGE 已授予，
    // 某些目录（根目录 / 内存卡 / Android/data）直接路径仍不可读；此时若硬阻
    // 断用户会陷入“给了权限也启动不了”。Android 上改为：保留错误文案但**不
    // 阻断**，让 dufs 尝试绑定，能读到什么是什么（传输记录里 403 会留痕）。
    final readableError = await _probeReadable(config);
    if (!_operationIsCurrent(generation)) return;
    // Android 上的目录可读性警告先放本地变量，服务真正启动成功后
    // 才落字段展示（见下），避免启动中途失败时残留“已启动”矛盾警告。
    String? androidReadableWarning;
    if (readableError != null) {
      if (_isAndroid) {
        // 非阻断：先缓存该警告，启动成功后由_serveUrls区域继续展示，
        // 用户可据此判断是否需要换目录。
        _log('readability warning (non-blocking on Android): $readableError');
        androidReadableWarning = readableError;
      } else {
        _error = readableError;
        _notifyState();
        return;
      }
    }
    // Validate permission consistency
    final permError = config.validatePermissions(config.language);
    if (permError != null) {
      _error = permError;
      _notifyState();
      return;
    }
    // Resolve port: kill orphan dufs, fall back to next free port if needed.
    // _resolvePort returns the actually-bindable port WITHOUT mutating
    // config.port, so the user's preference survives across runs.
    _portInfo = null;
    final int actualPort;
    try {
      actualPort = await _resolvePort(config.port, generation);
    } catch (e) {
      if (!_operationIsCurrent(generation)) return;
      _error = e.toString().replaceFirst('Exception: ', '');
      _notifyState();
      return;
    }
    if (!_operationIsCurrent(generation)) return;
    _activePort = actualPort;
    if (_portInfo != null) {
      _log(_portInfo!);
      _notifyState();
    }
    try {
      _error = null;
      _notifyState();
      if (_isAndroid) {
        final granted =
            await _ch.invokeMethod<bool>('isStorageGranted') ?? false;
        if (!_operationIsCurrent(generation)) return;
        _log('MANAGE_EXTERNAL_STORAGE granted: $granted');
        if (!granted) {
          _error = _l10n.t('srv.storagePermNeeded');
          _notifyState();
          await _ch.invokeMethod('requestStorage');
          return;
        }
      }
      if (_isAndroid) {
        // Android: start dufs via Native Service (process lives in Service, not Dart)
        final args = _buildArgs(config, actualPort);
        if (_disposed || generation != _startGeneration) return;
        await _ch.invokeMethod('startForegroundService', {
          'port': actualPort,
          'path': config.path,
          'args': args,
          'lang': config.language,
          'address': _serverUrl ?? '',
          'notifClipboard': config.notifClipboard,
        });
        // Poll service status. Kotlin side runs a TCP-connect probe that can
        // take up to ~5s on slow devices; a fixed 500ms wait races with that
        // and falsely reports failure. Poll every 200ms up to 6s.
        Map? info;
        var serviceFailed = false;
        for (var i = 0; i < 30; i++) {
          await Future.delayed(const Duration(milliseconds: 200));
          info = await _ch.invokeMethod<Map>('getServiceInfo');
          if (_disposed || generation != _startGeneration) return;
          if (_nativeRunWasStopped(info?['generation'] as int?)) {
            _clearRunningState();
            await _stopTools();
            _notifyState();
            return;
          }
          if (info?['isRunning'] == true) break;
          final svcError = (info?['error'] as String?) ?? '';
          if (svcError.isNotEmpty) {
            // Kotlin reported a definitive failure — fail fast.
            serviceFailed = true;
            break;
          }
        }
        if (serviceFailed || info == null || info['isRunning'] != true) {
          final svcError = (info?['error'] as String?) ?? '';
          _error =
              '${_l10n.t('srv.startFailed')}'
              '${svcError.isNotEmpty ? ': $svcError' : ''}';
          _isRunning = false;
          _activePort = 0;
          _notifyState();
          return;
        }
        _nativeGeneration = info['generation'] as int?;
      } else if (_isIOS) {
        // iOS: start dufs as child process (not signed for FFI)
        await _startDufsProcess(config, actualPort, generation);
      } else {
        // Desktop (Linux/macOS/Windows): use FFI
        await _startDufsFfi(config, actualPort, generation);
      }

      if (_disposed || generation != _startGeneration) return;
      _isRunning = true;
      final gen = generation;
      // 立即通知 UI 翻转（「启动服务」→「停止服务」），让用户感知服务已启动。
      // TCP + HTTP 长验证稍后在 _startServerLocked 收尾后由后台
      // [_verifyServerAsync] 完成，失败再回滚（见下方 try 块末尾）。
      _notifyState();
      // 服务确认跑起来了才把可读性警告挂上 UI。
      if (androidReadableWarning != null) {
        _androidReadableWarning = androidReadableWarning;
      }
      final localIp = await _getWifiIP();
      if (!_operationIsCurrent(gen) || !_isRunning) return;
      final allNet = await _getAllAddresses();
      if (_disposed || gen != _startGeneration || !_isRunning) return;
      _localIp = localIp;
      _allAddresses = allNet['addresses'] ?? [];
      _allInterfaceNames = allNet['names'] ?? [];
      // 确保默认 WiFi IP 在列表首位
      if (_localIp != null && _allAddresses.contains(_localIp)) {
        final idx = _allAddresses.indexOf(_localIp!);
        _allAddresses.removeAt(idx);
        _allInterfaceNames.removeAt(idx);
        _allAddresses.insert(0, _localIp!);
        _allInterfaceNames.insert(0, 'WiFi');
      } else if (_localIp != null && !_allAddresses.contains(_localIp)) {
        _allAddresses.insert(0, _localIp!);
        _allInterfaceNames.insert(0, 'WiFi');
      }
      if (_allAddresses.isEmpty) {
        _allAddresses.add('127.0.0.1');
        _allInterfaceNames.add('Local');
      }
      // 默认地址跟随用户选择；网络变化后旧地址失效时回退到列表第一个
      final preferred =
          config.preferredAddress != null &&
              _allAddresses.contains(config.preferredAddress)
          ? config.preferredAddress!
          : _allAddresses.first;
      _preferredAddress = preferred;
      _serverUrl = 'http://${_formatHost(preferred)}:$actualPort';
      _log('server: $_serverUrl, all: $_allAddresses');
      // Start polling log file for transfer records
      _startLogFilePolling();
      // 剪贴板旁路服务：端口 = dufs 最终解析端口 + 2000（默认 5000→7000，
      // dufs 自动+1 时跟随），与 dufs 同生同死；自身被占或落在浏览器黑名单
      // 端口再+1 最多 9 步，全不可用则降级跳过。
      await _startTools(gen, actualPort);
      if (_disposed || gen != _startGeneration || !_isRunning) return;
      // 通知栏更新：地址 + 剪贴板地址（startForegroundService 时 _serverUrl 尚未
      // 确定，传的是空串，导致之前通知栏不显示地址——此处推送纠正）。
      if (_isAndroid) {
        final cbUrl = _clipboard.port != null
            ? 'http://${_formatHost(preferred)}:${_clipboard.port}'
            : '';
        _ch
            .invokeMethod('updateNotificationAddress', {
              'address': _serverUrl!,
              'clipboardAddress': cbUrl,
              'generation': _nativeGeneration,
            })
            .catchError((_) {});
      }
      _notifyState();
      // _startServerLocked 已收尾（地址/剪贴板/日志轮询就绪）后才启动后台
      // 验证，避免与回滚的 stopServer() 并发竞态。Android 由 Kotlin 侧
      // waitForServerReady 完成同等验证，无需重复。
      if (!_isAndroid) {
        unawaited(_verifyServerAsync(gen, actualPort));
      }
    } catch (e) {
      if (_disposed || generation != _startGeneration) return;
      // FFI 已起来的情况下不能只清状态：stopServer 会因 !_isRunning 拒停，
      // 服务器会占着端口滞留到进程退出。
      if (_useFfi && _dufsFfi.isLoaded && _dufsFfi.isRunning()) {
        try {
          _dufsFfi.stop();
        } catch (_) {}
      }
      _error = 'Start failed: $e';
      _isRunning = false;
      _activePort = 0;
      await _stopTools();
      _notifyState();
      _log('failed: $e');
    }
  }

  // ==================== Build dufs CLI args ====================
  List<String> _buildArgs(ServerConfig c, int port) {
    final args = <String>['-b', '0.0.0.0', '-p', '$port'];
    if (!c.readonly) {
      if (c.allowUpload) args.add('--allow-upload');
      if (c.allowDelete) args.add('--allow-delete');
      if (c.allowSearch) args.add('--allow-search');
      if (c.allowArchive) args.add('--allow-archive');
      if (c.allowSymlink) args.add('--allow-symlink');
    }
    if (c.auth != null && c.auth!.isNotEmpty) {
      args.addAll(['--auth', '${c.auth!}@/:rw']);
    }
    if (c.cors) args.add('--enable-cors');
    if (c.hideSystemFiles) {
      args.addAll([
        '--hidden',
        '.git,.DS_Store,Thumbs.db,.env,.idea,.vscode,__pycache__,.svn,.hg',
      ]);
    }
    if (c.renderTryIndex) args.add('--render-try-index');
    // Write HTTP logs to a temp file so we can read them on all platforms
    if (_logFilePath != null) args.addAll(['--log-file', _logFilePath!]);
    // dufs supports serving a single file directly.
    args.add(c.path);
    return args;
  }

  /// Path to the dufs log file (set before start, cleared on stop)
  String? _logFilePath;

  /// Timer to poll the log file for new entries (Android/workaround)
  Timer? _logFileTimer;

  /// Last position read in the log file
  int _logFilePosition = 0;

  /// Partial line buffered between incremental reads
  String _logFileRemainder = '';
  int _logPollGeneration = 0;
  Object? _activeLogRead;

  /// Redact the value following any `--auth` flag so credentials (user:pass)
  /// do not leak into logcat / debugPrint. Kotlin-side already redacted in
  /// v0.3.4; this is the missing Dart half (C1).
  List<String> _redactedArgs(List<String> args) {
    final out = <String>[];
    for (var i = 0; i < args.length; i++) {
      out.add(args[i]);
      if (args[i] == '--auth' && i + 1 < args.length) {
        out.add('***@/:rw');
        i++;
      }
    }
    return out;
  }

  // ==================== Start dufs via FFI (desktop) ====================
  /// 启动代数，用于区分先后台验证的归属。每次 start 递增，后台验证
  /// 持有启动时的代数，回滚前检查是否仍为当前代数——防止验证完成时
  /// 用户已停止又重启了服务，误杀/误报新实例。
  int _startGeneration = 0;

  Future<void> _startDufsFfi(
    ServerConfig config,
    int port,
    int generation,
  ) async {
    if (!_operationIsCurrent(generation)) return;
    if (!_dufsFfi.isLoaded) {
      final libPath = await resolveDufsLibPath();
      if (!_operationIsCurrent(generation)) {
        await discardResolvedDufsLibPath(libPath);
        return;
      }
      _log('Loading dufs FFI library: $libPath');
      _dufsFfi.load(libPath);
    }
    final args = _buildArgs(config, port);
    final argv = ['dufs', ...args];
    _log('dufs ffi start: ${_redactedArgs(args).join(' ')}');
    final ret = _dufsFfi.start(argv);
    if (ret != 0) {
      _log('dufs FFI start returned $ret (failure)');
      throw Exception('dufs FFI start returned $ret');
    }
    _log('dufs FFI start returned 0 (success)');
    // 立即检查进程是否活着（启动失败/秒死会被 _startDufsFfi 拦截），
    // 长轮询验证（TCP + HTTP）交给后台 [_verifyServerAsync] 在
    // UI 翻转后执行，不阻塞「停止服务」按钮展示。
    if (!_dufsFfi.isRunning()) {
      throw Exception(_t('srv.notListening', {'port': '$port'}));
    }
  }

  /// 单次 HTTP 探测：GET / 任意响应码都算存活（dufs 活着才能回 HTTP）。
  /// 拿到响应头即成功，不读 body。超时/拒绝连接/异常返回 false。
  /// 不引入长轮询——启动路径已用 [_waitPortReady] 保证端口可连，
  /// 这里只补应用层确认（孤儿进程占端口、绑定成功但服务未就绪等）。
  Future<bool> _waitHttpReady(int port) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      final client = HttpClient();
      try {
        client.connectionTimeout = const Duration(milliseconds: 500);
        final req = await client
            .getUrl(Uri.parse('http://127.0.0.1:$port/'))
            .timeout(const Duration(milliseconds: 500));
        await req.close().timeout(const Duration(milliseconds: 500));
        return true;
      } catch (_) {
        // 重试一次覆盖首个请求排队/慢启动窗口
      } finally {
        client.close();
      }
    }
    return false;
  }

  /// 后台服务验证（UI 翻转后 fire-and-forget 执行）。
  /// 先等端口可连，再探测 HTTP 响应。任一失败且服务仍属于本次启动
  /// （代数未变）则回滚：停止服务并展示错误，避免 UI 显示在线但
  /// 实际不可访问（孤儿进程占端口等）。
  Future<void> _verifyServerAsync(int gen, int port) async {
    var tcpOk = false;
    var httpOk = false;
    try {
      tcpOk = await _waitPortReady(port);
      if (tcpOk) httpOk = await _waitHttpReady(port);
    } catch (_) {}
    if (tcpOk && httpOk) return;
    if (gen != _startGeneration || !_isRunning) return;
    _log('Server verify failed (tcp=$tcpOk http=$httpOk), rolling back');
    await stopServer();
    _error = _t(tcpOk ? 'srv.notResponding' : 'srv.notListening', {
      'port': '$port',
    });
    _notifyState();
  }

  /// 轮询本机端口直到可连接。返回 false 即超时（默认 3s）。
  Future<bool> _waitPortReady(
    int port, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      try {
        final s = await Socket.connect(
          InternetAddress.loopbackIPv4,
          port,
          timeout: const Duration(milliseconds: 300),
        );
        s.destroy();
        return true;
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 200));
    }
    return false;
  }

  // ==================== Start dufs process (iOS) ====================
  Future<void> _startDufsProcess(
    ServerConfig config,
    int port,
    int generation,
  ) async {
    if (!_operationIsCurrent(generation)) return;
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final binPath = p.join(exeDir, 'dufs');
    if (!await File(binPath).exists()) {
      if (!_operationIsCurrent(generation)) return;
      throw Exception(_t('srv.dufsMissing', {'path': binPath}));
    }
    if (!_operationIsCurrent(generation)) return;
    final args = _buildArgs(config, port);
    final workDir = config.shareSingleFile
        ? p.dirname(config.path)
        : config.path;
    _log('dufs: $binPath ${_redactedArgs(args).join(' ')}');
    final proc = await Process.start(binPath, args, workingDirectory: workDir);
    if (!_operationIsCurrent(generation)) {
      proc.kill();
      try {
        await proc.exitCode.timeout(const Duration(seconds: 2));
      } catch (_) {
        proc.kill(ProcessSignal.sigkill);
      }
      return;
    }
    _process = proc;
    _processExitCode = null;
    // 监听子进程退出：秒死（参数错/端口被抢）要在 UI 标记失败，运行中死掉
    // 要收回"运行中"状态——否则界面对着一个死 URL 显示在线。
    proc.exitCode.then((code) => _onProcessDied(proc, code));
    proc.stdout.listen((d) {
      final line = String.fromCharCodes(d).trim();
      _log('out: $line');
      _trackActivity(line);
    });
    proc.stderr.listen((d) {
      final line = String.fromCharCodes(d).trim();
      _log('err: $line');
      _trackActivity(line);
    });
    await Future.delayed(const Duration(milliseconds: 300));
    if (!_operationIsCurrent(generation)) return;
    if (_processExitCode != null) {
      throw Exception(
        _t('srv.exitedDuringStart', {'code': '$_processExitCode'}),
      );
    }
    // 长验证（TCP + HTTP）不在启动路径阻塞——UI 已翻转，由后台
    // [_verifyServerAsync] 完成，失败再回滚。这里只兜底秒死。
  }

  void _onProcessDied(Process proc, int code) {
    if (_process != proc) return;
    _process = null;
    _processExitCode = code;
    if (!_isRunning) return;
    _error = _t('srv.exitedUnexpectedly', {'code': '$code'});
    ++_startGeneration;
    _clearRunningState();
    unawaited(_stopTools());
    _log('dufs process died unexpectedly (code $code)');
    _notifyState();
  }

  /// 解析 dufs 输出行，更新请求计数和日志列表。
  ///
  /// Returns true if state changed but does NOT notify — callers batch a single
  /// [notifyListeners] after ingesting a whole chunk. A busy transfer logs
  /// hundreds of lines per 2s poll; notifying per line rebuilt the entire home
  /// page (QR matrix included) hundreds of times per frame — the main source of
  /// desktop UI jank under load.
  bool _ingestLine(String line) {
    final entry = TransferLog.parse(line);
    if (entry == null) return false;
    _totalRequests++;
    final now = DateTime.now();
    _lastActivityAt = now;
    _lastActivity = now.toIso8601String().substring(11, 19);
    if (showInLog(entry)) {
      _transferLogs.insert(0, entry);
      if (_transferLogs.length > 200) {
        _transferLogs.removeRange(200, _transferLogs.length);
      }
    }
    return true;
  }

  /// Ingest one line and notify immediately. Used by the iOS stdout/stderr
  /// stream path, where lines arrive one at a time anyway.
  void _trackActivity(String line) {
    if (_ingestLine(line)) _notifyState();
  }

  Future<String?> _probeReadable(ServerConfig c) =>
      probeReadableError(c, _l10n, log: _log);

  /// 可读性探测：以 dufs 实际使用的方式（opendir / open）试读一次。
  /// 返回 null 表示可读，否则返回可直接展示的本地化错误。
  ///
  /// 只取第一条目录项：`Stream.isEmpty` 收到首个事件即取消订阅，不会为
  /// 十万文件的目录做完整 readdir（那会卡住启动）。
  @visibleForTesting
  static Future<String?> probeReadableError(
    ServerConfig c,
    AppLocalizations l10n, {
    void Function(String)? log,
  }) async {
    final say = log ?? _noopLog;
    try {
      if (c.shareSingleFile) {
        final raf = await File(c.path).open();
        await raf.close();
      } else {
        await Directory(c.path).list(followLinks: false).isEmpty;
      }
      return null;
    } on FileSystemException catch (e) {
      final key = c.shareSingleFile
          ? 'srv.fileNotReadable'
          : 'srv.dirNotReadable';
      final reason = e.osError?.message ?? e.message;
      say('readability probe failed for ${c.path}: $reason');
      // 分区存储那段建议只对 Android 有意义：桌面走到这里通常是权限位、
      // SELinux 或断开的网络盘，照抄 Android 文案会把人带偏。
      final hint = !c.shareSingleFile && _isAndroid
          ? ' ${l10n.t('srv.dirNotReadableAndroid')}'
          : '';
      return '${l10n.t(key)}（$reason）$hint';
    } catch (e) {
      // 探测本身失败（超时等）≠ 目录不可读：放行，让 dufs 自己决定。
      // 真出现 403 时现在能在传输记录里看到（showInLog 保留失败请求）。
      say('readability probe inconclusive for ${c.path}: $e');
      return null;
    }
  }

  static void _noopLog(String _) {}

  /// 该请求是否值得进「传输记录」。
  @visibleForTesting
  static bool showInLog(TransferLog entry) {
    final path = entry.path;
    // 失败请求必须留痕：用户报「浏览器只显示 Forbidden」时，证据就是这条
    // `GET / 403`，而旧过滤规则恰好把 path=='/' 全丢了。
    if (entry.status >= 400) {
      if (path.contains('/dufs-assets/')) return false;
      if (path.endsWith('.ico') ||
          path.endsWith('.css') ||
          path.endsWith('.js')) {
        return false;
      }
      return true;
    }
    if (path == '/' || path.isEmpty) return false;
    if (path.endsWith('/')) return false;
    if (path.endsWith('.css') ||
        path.endsWith('.js') ||
        path.endsWith('.ico')) {
      return false;
    }
    if (path.contains('/dufs-assets/')) return false;
    if (entry.method == 'MKCOL' ||
        entry.method == 'OPTIONS' ||
        entry.method == 'PROPFIND') {
      return false;
    }
    if (entry.isDownload && !path.contains('.')) return false;
    return entry.isDownload || entry.isUpload || entry.isDelete;
  }

  void clearLogs() {
    _transferLogs.clear();
    _notifyState();
  }

  void _startLogFilePolling() {
    _logFileTimer?.cancel();
    ++_logPollGeneration;
    _activeLogRead = null;
    _logFileTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _readLogFile(),
    );
  }

  Future<void> _readLogFile() async {
    final logPath = _logFilePath;
    if (logPath == null || !_isRunning || _disposed || _activeLogRead != null) {
      return;
    }
    final generation = _startGeneration;
    final pollGeneration = _logPollGeneration;
    final readToken = Object();
    _activeLogRead = readToken;
    bool current() =>
        _operationIsCurrent(generation) &&
        _isRunning &&
        pollGeneration == _logPollGeneration &&
        logPath == _logFilePath;
    try {
      final file = File(logPath);
      final exists = await file.exists();
      if (!current() || !exists) return;
      final raf = await file.open();
      var truncateAfterRead = false;
      try {
        if (!current()) return;
        final length = await raf.length();
        if (!current()) return;
        var position = _logFilePosition;
        var remainder = _logFileRemainder;
        if (length < position) {
          position = 0;
          remainder = '';
        }
        if (length == position) {
          _logFilePosition = position;
          _logFileRemainder = remainder;
          return;
        }

        await raf.setPosition(position);
        if (!current()) return;
        final bytes = await raf.read(length - position);
        if (!current()) return;

        final chunk = utf8.decode(bytes, allowMalformed: true);
        final merged = remainder + chunk;
        final endsWithNewline = merged.endsWith('\n');
        final lines = merged.split('\n');
        _logFilePosition = length;
        _logFileRemainder = endsWithNewline ? '' : lines.removeLast();

        var changed = false;
        for (final line in lines) {
          final trimmed = line.trim();
          if (trimmed.isNotEmpty && _ingestLine(trimmed)) changed = true;
        }
        if (changed) _notifyState();
        // F3 缓解：内容已消化，超过上限即截断（dufs 追加写会从 0 续写），
        // 防单个长分享会话把临时目录写爆。
        truncateAfterRead = length > _kMaxLogBytes;
      } finally {
        await raf.close();
      }
      if (!current()) return;
      if (truncateAfterRead) {
        final w = await file.open(mode: FileMode.writeOnlyAppend);
        try {
          if (!current()) return;
          // Keep the generation check and file mutation in one event-loop
          // turn; a delayed truncation must not clear a replacement run.
          w.truncateSync(0);
          _logFilePosition = 0;
          _logFileRemainder = '';
        } finally {
          await w.close();
        }
      }
    } catch (_) {
      // Log polling is best effort; child/service lifecycle owns errors.
    } finally {
      if (identical(_activeLogRead, readToken)) _activeLogRead = null;
    }
  }

  Future<void> stopServer() {
    if (_disposed) return Future<void>.value();
    final pending = _stopTransition;
    if (pending != null) return pending;
    final operation = _stopServerLocked();
    _stopTransition = operation;
    return operation.whenComplete(() => _stopTransition = null);
  }

  Future<void> _stopServerLocked() async {
    if (_disposed) return;
    ++_startGeneration;
    final nativeGeneration = _nativeGeneration;
    final wasRunning = _isRunning;
    _clearRunningState();
    // Close the tools endpoint before waiting for the native/process shutdown.
    // A notification stop callback can arrive while that shutdown is pending.
    await _stopTools();
    if (!wasRunning && !_isStarting) return;
    if (_useFfi && _dufsFfi.isLoaded) {
      // FFI mode: stop the in-process server
      _dufsFfi.stop();
      // dufs_stop is non-blocking (sets flag + shutdown_background), so
      // isRunning() returns false immediately. Poll only if the flag
      // somehow didn't take (accept() may still be blocking).
      if (_dufsFfi.isRunning()) {
        for (int i = 0; i < 20; i++) {
          await Future.delayed(const Duration(milliseconds: 200));
          if (!_dufsFfi.isRunning()) break;
        }
      }
      // Short settle for the port to be released by the background
      // shutdown. _resolvePort on next start handles any leftover
      // TIME_WAIT gracefully.
      await Future.delayed(const Duration(milliseconds: 100));
    } else if (_process != null) {
      // Process mode (iOS): kill child process
      _process!.kill();
      try {
        await _process!.exitCode.timeout(const Duration(seconds: 2));
      } catch (_) {}
      _process = null;
      _processExitCode = null;
    }
    if (_isAndroid) {
      await _ch
          .invokeMethod('stopForegroundService', {
            'generation': nativeGeneration,
          })
          .catchError((_) {});
    }
    _notifyState();
  }

  void _clearRunningState() {
    _isRunning = false;
    _nativeGeneration = null;
    _serverUrl = null;
    _activePort = 0;
    _totalRequests = 0;
    _lastActivity = null;
    _lastActivityAt = null;
    _allAddresses = [];
    _allInterfaceNames = [];
    _transferLogs.clear();
    _logFileTimer?.cancel();
    _logFileTimer = null;
    ++_logPollGeneration;
    _activeLogRead = null;
    _logFilePath = null;
    _logFilePosition = 0;
    _logFileRemainder = '';
    _androidReadableWarning = null;
  }

  /// 恢复到 Native Service 管理的 dufs 进程状态（Activity 重建后查询 Service）
  Future<void> restoreFromService() async {
    if (!_isAndroid || _disposed || _isStarting || _stopTransition != null) {
      return;
    }
    final generation = _startGeneration;
    final restoreGeneration = ++_restoreGeneration;
    try {
      final info = await _ch.invokeMethod<Map>('getServiceInfo');
      if (!_operationIsCurrent(
        generation,
        restoreGeneration: restoreGeneration,
      )) {
        return;
      }
      final infoGeneration = info?['generation'] as int?;
      if (infoGeneration != null &&
          _nativeGeneration != null &&
          infoGeneration < _nativeGeneration!) {
        return;
      }
      if (info != null && info['isRunning'] == true) {
        final port = info['port'] as int? ?? 0;
        if (port < 1 || port > 65535) return;
        final nativeGeneration = info['generation'] as int?;
        if (_nativeRunWasStopped(nativeGeneration)) {
          _clearRunningState();
          await _stopTools();
          _notifyState();
          return;
        }
        final sameRun =
            _isRunning &&
            _nativeGeneration == nativeGeneration &&
            _activePort == port;
        if (!sameRun) {
          ++_logPollGeneration;
          _activeLogRead = null;
          _logFileTimer?.cancel();
          _logFileTimer = null;
          await _stopTools();
        }
        if (!_operationIsCurrent(
          generation,
          restoreGeneration: restoreGeneration,
        )) {
          return;
        }
        _nativeGeneration = nativeGeneration;
        _activePort = port;
        if (!sameRun &&
            !await _prepareLogFile(
              generation,
              restoreGeneration: restoreGeneration,
            )) {
          return;
        }
        if (!sameRun) {
          _totalRequests = 0;
          _lastActivity = null;
          _lastActivityAt = null;
          _transferLogs.clear();
        }
        final localIp = await _getWifiIP();
        if (!_operationIsCurrent(
          generation,
          restoreGeneration: restoreGeneration,
        )) {
          return;
        }
        final allNet = await _getAllAddresses();
        if (!_operationIsCurrent(
          generation,
          restoreGeneration: restoreGeneration,
        )) {
          return;
        }
        _localIp = localIp;
        _allAddresses = allNet['addresses'] ?? [];
        _allInterfaceNames = allNet['names'] ?? [];
        if (_localIp != null && _allAddresses.contains(_localIp)) {
          final idx = _allAddresses.indexOf(_localIp!);
          _allAddresses.removeAt(idx);
          _allInterfaceNames.removeAt(idx);
          _allAddresses.insert(0, _localIp!);
          _allInterfaceNames.insert(0, 'WiFi');
        } else if (_localIp != null && !_allAddresses.contains(_localIp)) {
          _allAddresses.insert(0, _localIp!);
          _allInterfaceNames.insert(0, 'WiFi');
        }
        if (_allAddresses.isEmpty) {
          _allAddresses.add('127.0.0.1');
          _allInterfaceNames.add('Local');
        }
        final savedAddress = info['address'] as String?;
        final savedHost = savedAddress == null
            ? null
            : Uri.tryParse(savedAddress)?.host;
        final preferred = _allAddresses.contains(savedHost)
            ? savedHost!
            : _allAddresses.first;
        _preferredAddress = preferred;
        _serverUrl = 'http://${_formatHost(preferred)}:$port';
        _isRunning = true;
        _startLogFilePolling();
        await _startTools(
          generation,
          port,
          restoreGeneration: restoreGeneration,
        );
        if (!_operationIsCurrent(
              generation,
              restoreGeneration: restoreGeneration,
            ) ||
            !_isRunning) {
          return;
        }
        await _ch.invokeMethod('updateNotificationAddress', {
          'address': _serverUrl!,
          'clipboardAddress': clipboardUrl ?? '',
          'generation': _nativeGeneration,
        });
        if (!_operationIsCurrent(
          generation,
          restoreGeneration: restoreGeneration,
        )) {
          return;
        }
        _log('restored from native service: $_serverUrl');
        _notifyState();
      } else {
        ++_startGeneration;
        _clearRunningState();
        await _stopTools();
        _notifyState();
      }
    } catch (e) {
      _log('Failed to restore from service: $e');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    ++_startGeneration;
    if (_nativeChannelOwner == this) {
      _nativeChannelOwner = null;
      _ch.setMethodCallHandler(null);
    }
    // Cancel the log-file poll timer before anything else: otherwise it can
    // fire after dispose and call notifyListeners() on a disposed
    // ChangeNotifier ("A ChangeNotifier was used after being disposed").
    // stopServer() cancels it too, but dispose() can run without a prior stop.
    _logFileTimer?.cancel();
    _logFileTimer = null;
    if (_useFfi && _dufsFfi.isLoaded) {
      try {
        _dufsFfi.stop();
      } catch (_) {}
    }
    try {
      _process?.kill();
    } catch (_) {}
    _process = null;
    _clearRunningState();
    unawaited(_stopTools());
    super.dispose();
  }
}
