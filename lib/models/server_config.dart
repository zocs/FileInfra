import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 服务器配置数据模型
/// 包含 dufs 服务启动所需的全部参数
class ServerConfig {
  static const _secureStorage = FlutterSecureStorage();
  static const _authStorageKey = 'server_auth';

  /// 分享目录路径
  String path;

  /// 监听端口，默认 5000
  int port;

  /// 允许上传
  bool allowUpload;

  /// 允许删除
  bool allowDelete;

  /// 允许搜索
  bool allowSearch;

  /// 允许归档 (zip/tar 下载)
  bool allowArchive;

  /// 允许符号链接
  bool allowSymlink;

  /// 只读模式
  bool readonly;

  /// 认证信息，格式: "user:pass"
  String? auth;

  /// 启用 CORS
  bool cors;

  /// 语言设置 (zh / en / zhTW)
  String language;

  /// 主题模式 (system / light / dark)
  String themeMode;

  /// 配色方案 (coral / teal / violet / ocean / sunset / forest)
  String colorScheme;

  /// 是否已完成首次设置
  bool setupDone;

  /// 关闭行为: 'ask'(询问), 'tray'(最小化到托盘), 'exit'(直接退出)
  String closeAction;

  /// 是否在分享单文件模式（dufs 指定单文件）
  bool shareSingleFile;

  /// 隐藏系统文件（.git, .DS_Store, Thumbs.db 等）
  bool hideSystemFiles;

  /// 目录有 index.html 时自动渲染
  bool renderTryIndex;

  /// 优先展示的网络地址（IP），为空则用列表第一个
  String? preferredAddress;

  /// 自定义主题色（ARGB），colorScheme == 'custom' 时生效
  int customColor;

  /// 通知栏是否显示「发送剪贴板 / 拉取剪贴板」按钮
  bool notifClipboard;

  ServerConfig({
    this.path = '',
    this.port = 5000,
    this.allowUpload = false,
    this.allowDelete = false,
    this.allowSearch = false,
    this.allowArchive = false,
    this.allowSymlink = false,
    this.readonly = true,
    this.auth,
    this.cors = false,
    this.language = 'zh',
    this.themeMode = 'system',
    this.colorScheme = 'coral',
    this.setupDone = false,
    this.closeAction = 'ask',
    this.shareSingleFile = false,
    this.hideSystemFiles = true,
    this.renderTryIndex = false,
    this.preferredAddress,
    this.customColor = 0xFFFF6B5A,
    this.notifClipboard = true,
  });

  /// 转为 JSON Map
  Map<String, dynamic> toJson() => {
    'path': path,
    'port': port,
    'allowUpload': allowUpload,
    'allowDelete': allowDelete,
    'allowSearch': allowSearch,
    'allowArchive': allowArchive,
    'allowSymlink': allowSymlink,
    'readonly': readonly,
    'cors': cors,
    'language': language,
    'themeMode': themeMode,
    'colorScheme': colorScheme,
    'setupDone': setupDone,
    'closeAction': closeAction,
    'shareSingleFile': shareSingleFile,
    'hideSystemFiles': hideSystemFiles,
    'renderTryIndex': renderTryIndex,
    'preferredAddress': preferredAddress,
    'customColor': customColor,
    'notifClipboard': notifClipboard,
  };

  /// 从 JSON Map 创建实例
  factory ServerConfig.fromJson(Map<String, dynamic> json) => ServerConfig(
    path: _jsonValue(json, 'path', ''),
    port: _jsonPort(json),
    allowUpload: _jsonValue(json, 'allowUpload', false),
    allowDelete: _jsonValue(json, 'allowDelete', false),
    allowSearch: _jsonValue(json, 'allowSearch', false),
    allowArchive: _jsonValue(json, 'allowArchive', false),
    allowSymlink: _jsonValue(json, 'allowSymlink', false),
    readonly: _jsonValue(json, 'readonly', true),
    cors: _jsonValue(json, 'cors', false),
    language: _jsonValue(json, 'language', 'zh'),
    themeMode: _jsonValue(json, 'themeMode', 'system'),
    colorScheme: _jsonValue(json, 'colorScheme', 'coral'),
    setupDone: _jsonValue(json, 'setupDone', false),
    closeAction: _jsonValue(json, 'closeAction', 'ask'),
    shareSingleFile: _jsonValue(json, 'shareSingleFile', false),
    hideSystemFiles: _jsonValue(json, 'hideSystemFiles', true),
    renderTryIndex: _jsonValue(json, 'renderTryIndex', false),
    preferredAddress: _jsonValue<String?>(json, 'preferredAddress', null),
    customColor: _jsonValue(json, 'customColor', 0xFFFF6B5A),
    notifClipboard: _jsonValue(json, 'notifClipboard', true),
  );

  // Persisted settings can come from older versions or be partially corrupted.
  // Default each invalid field without losing the remaining valid settings.
  static T _jsonValue<T>(Map<String, dynamic> json, String key, T fallback) {
    final value = json[key];
    return value is T ? value : fallback;
  }

  static int _jsonPort(Map<String, dynamic> json) {
    final port = _jsonValue(json, 'port', 5000);
    return port >= 1 && port <= 65535 ? port : 5000;
  }

  /// 从 SharedPreferences 加载配置。
  ///
  /// 此方法在 runApp 之前执行，任何异常（损坏的 JSON、Linux 无 keyring 时
  /// secure storage 抛错）都会白屏启动——所有失败路径都降级为默认值/无凭据，
  /// 而不是向上抛。
  static Future<ServerConfig> load() async {
    SharedPreferences? prefs;
    Map<String, dynamic>? json;
    try {
      prefs = await SharedPreferences.getInstance();
      final stored = prefs.get('server_config');
      if (stored is String) {
        final decoded = jsonDecode(stored);
        if (decoded is Map<String, dynamic>) json = decoded;
      }
    } catch (e) {
      debugPrint('server_config load failed, falling back to defaults: $e');
    }
    final config = json != null ? ServerConfig.fromJson(json) : ServerConfig();
    final legacyValue = json?['auth'];
    final legacyAuth = legacyValue is String ? legacyValue : null;
    String? secureAuth;
    try {
      secureAuth = await _secureStorage.read(key: _authStorageKey);
    } catch (e) {
      // secure storage 不可用（无 keyring 等）≠ 有凭据，按无凭据处理
      debugPrint('secure storage read failed: $e');
    }
    config.auth = secureAuth ?? legacyAuth;
    // Only migrate legacy → secure storage when secure storage doesn't already
    // have a value. Otherwise we'd overwrite a fresh credential set in the new
    // version with a stale one left in SharedPreferences.
    if (prefs != null &&
        secureAuth == null &&
        legacyAuth != null &&
        legacyAuth.isNotEmpty) {
      try {
        await _secureStorage.write(key: _authStorageKey, value: legacyAuth);
        // Strip the legacy 'auth' field from SharedPreferences so we don't keep
        // re-migrating on every load (and so the credential isn't double-stored).
        await prefs.setString('server_config', jsonEncode(config.toJson()));
      } catch (e) {
        debugPrint('auth migration skipped: $e');
      }
    }
    return config;
  }

  /// 保存配置到 SharedPreferences
  ///
  /// 与 [load] 对称：Linux 无 keyring / 无 secret service 时 secure storage
  /// 抛错，绝不能让它阻断整个 save（否则首次设置向导点「开始使用」时
  /// onSetupDone 不执行，UI 卡在向导，但 SharedPreferences 已写入成功 ——
  /// 表现为“重启后才进首页”）。凭据写不进去按无凭据处理，不升级为异常。
  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('server_config', jsonEncode(toJson()));
    if (auth == null || auth!.isEmpty) {
      try {
        await _secureStorage.delete(key: _authStorageKey);
      } catch (e) {
        debugPrint('secure storage delete failed: $e');
      }
      return;
    }
    try {
      await _secureStorage.write(key: _authStorageKey, value: auth!);
    } catch (e) {
      debugPrint('secure storage write failed: $e');
    }
  }

  /// 权限预设: 只读
  void applyReadonly() {
    readonly = true;
    allowUpload = false;
    allowDelete = false;
    allowSearch = false;
    allowArchive = false;
    allowSymlink = false;
  }

  /// 权限预设: 允许上传
  void applyUpload() {
    readonly = false;
    allowUpload = true;
    allowDelete = false;
    allowSearch = true;
    allowArchive = true;
    allowSymlink = false;
  }

  /// 权限预设: 完全权限
  void applyFull() {
    readonly = false;
    allowUpload = true;
    allowDelete = true;
    allowSearch = true;
    allowArchive = true;
    allowSymlink = false;
  }

  /// 校验权限字段一致性，返回冲突描述（null = 无冲突）。
  /// 文案按 UI 语言本地化（zh / zhTW / en，默认 zh）。
  String? validatePermissions([String language = 'zh']) {
    if (readonly && (allowUpload || allowDelete || allowArchive)) {
      switch (language) {
        case 'en':
          return 'Upload/delete/archive cannot be enabled in readonly mode';
        case 'zhTW':
          return '唯讀模式下不允許開啟上傳/刪除/歸檔權限';
        default:
          return 'readonly 模式下不允许开启上传/删除/归档权限';
      }
    }
    return null;
  }

  @override
  String toString() => 'ServerConfig(path: $path, port: $port)';

  /// 创建默认配置
  factory ServerConfig.defaultConfig() => ServerConfig();
}
