import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:qr/qr.dart';

/// 剪贴板旁路服务：同一端口同时提供 HTTP 页面 + WebSocket 实时同步。
///
/// 默认端口 = dufs 端口 + 1000（差值固定），dufs 因自动+1 变化时剪贴板也
/// 跟随+1；若自身端口被占用，独立再+1 最多 [maxBump] 步。
/// 零第三方依赖，纯 dart:io 实现。
class ClipboardService {
  /// 剪贴板端口与 dufs 端口之间的固定差值。
  /// 默认 dufs 5000 → 剪贴板 7000。避开浏览器黑名单端口（如 6000=X11）。
  static const int portOffset = 2000;

  /// 端口被占用时最多尝试 +1 的次数。
  static const int maxBump = 9;

  HttpServer? _server;
  final Set<WebSocket> _clients = {};
  String? _text;
  int _updatedAt = 0;
  bool _running = false;

  bool get isRunning => _running;

  /// 实际绑定的剪贴板端口。
  int? get port => _server?.port;

  /// 启动失败原因（成功启动时为 null）。
  String? lastError;

  /// 展示用 URL（host 由 UI 从主服务地址复用）。
  String? get url => _server != null ? 'http://<host>:${_server!.port}' : null;

  /// 启动服务，剪贴板端口 = [dufsPort] + 1000。
  /// 若端口被占用或落在浏览器不安全端口黑名单（如 6000 = X11），自动+1
  /// 最多 [maxBump] 步；全部不可用则 log warning 跳过。
  /// 失败时只 log warning，不抛异常（剪贴板是增量功能，不阻塞主服务）。
  Future<void> start(int dufsPort) async {
    lastError = null;
    int base = dufsPort + portOffset;
    if (base > 65535) base = 65535;
    final maxPort = _min(base + maxBump, 65535);

    for (var port = base; port <= maxPort; port++) {
      // 浏览器（Chrome/Firefox/Safari）不安全端口黑名单：这些端口用于
      // 系统服务（6000=X11 等），浏览器直接拒绝访问（ERR_UNSAFE_PORT），
      // 视为不可用跳过。
      if (_unsafeBrowserPorts.contains(port)) continue;
      try {
        _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
        _running = true;
        debugPrint('ClipboardService: bound on port $port (dufs $dufsPort)');
        _server!.listen(_handleRequest, onError: (e) {
          debugPrint('ClipboardService: server error: $e');
        });
        return;
      } on SocketException catch (e) {
        lastError = 'Port $port busy: $e';
        // port busy, try next
      } catch (e) {
        lastError = 'Bind failed: $e';
        debugPrint('ClipboardService: bind error: $e');
        rethrow; // 非 SocketException 的上抛，由调用方处理
      }
    }
    debugPrint('ClipboardService: all ports $base..$maxPort busy, skipping');
  }

  /// 浏览器不安全端口黑名单（Chrome/Firefox 共同禁用，含 X11 6000 等）。
  static const Set<int> _unsafeBrowserPorts = {
    1, 7, 9, 11, 13, 15, 17, 19, 20, 21, 22, 23, 25, 37, 42, 43, 53, 69,
    77, 79, 87, 95, 101, 102, 103, 104, 109, 110, 111, 113, 115, 117,
    119, 123, 135, 137, 139, 143, 161, 179, 389, 427, 465, 512, 513, 514,
    515, 526, 530, 531, 532, 540, 548, 554, 556, 563, 587, 601, 636, 989,
    990, 993, 995, 1719, 1720, 1723, 2049, 3659, 4045, 5060, 5061, 6000,
    6566, 6665, 6666, 6667, 6668, 6669, 6697, 10080,
  };

  static int _min(int a, int b) => a < b ? a : b;

  /// 停止服务，关闭所有连接。
  Future<void> stop() async {
    _running = false;
    for (final c in _clients) {
      try {
        await c.close();
      } catch (_) {}
    }
    _clients.clear();
    try {
      await _server?.close(force: true);
    } catch (_) {}
    _server = null;
    _text = null;
    _updatedAt = 0;
    debugPrint('ClipboardService: stopped');
  }

  /// 当前共享文本（供 Android 原生侧拉取剪贴板用）。
  String? get text => _text;

  /// 设置剪贴板内容并广播给所有其他客户端（排除发送者自身）。
  void setText(String text, {WebSocket? source}) {
    _text = text;
    _updatedAt = DateTime.now().millisecondsSinceEpoch;
    final msg = _buildClipboardMsg();
    for (final c in _clients) {
      if (c.readyState == WebSocket.open && c != source) {
        c.add(msg);
      }
    }
  }

  // ── 请求分发 ──

  void _handleRequest(HttpRequest req) {
    if (WebSocketTransformer.isUpgradeRequest(req)) {
      _upgradeToWs(req);
    } else if (req.uri.path == '/api/clipboard') {
      _serveClipboardApi(req);
    } else if (req.uri.path == '/qr') {
      _serveQr(req);
    } else {
      _serveHtml(req);
    }
  }

  // ── WebSocket ──

  Future<void> _upgradeToWs(HttpRequest req) async {
    WebSocket? ws;
    try {
      ws = await WebSocketTransformer.upgrade(req);
    } catch (e) {
      debugPrint('ClipboardService: WS upgrade failed: $e');
      return;
    }
    _clients.add(ws);
    debugPrint('ClipboardService: WS client connected (total=${_clients.length})');

    // 连接后立即推送当前内容
    if (_text != null) {
      ws.add(_buildClipboardMsg());
    }

    ws.listen(
      (data) {
        // 二进制帧时 data 是 List<int>，仅处理文本帧，避免强转抛 TypeError
        if (data is String) {
          final msg = _parseClientMsg(data);
          if (msg != null) {
            setText(msg, source: ws);
          }
        }
      },
      onDone: () {
        _clients.remove(ws);
        debugPrint('ClipboardService: WS client disconnected (remaining=${_clients.length})');
      },
      onError: (e) {
        _clients.remove(ws);
        debugPrint('ClipboardService: WS client error: $e');
      },
    );
  }

  // ── HTTP 页面 ──

  void _serveHtml(HttpRequest req) {
    req.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType(
        'text', 'html', charset: 'utf-8',
      )
      ..write(_htmlPage())
      ..close();
  }

  // ── 剪贴板 API（供 Android 原生通知按钮读写，绕开引擎依赖） ──

  /// GET /api/clipboard → JSON 含当前文本与时间戳；
  /// POST /api/clipboard → body 为纯文本，设置并广播给所有已连接页面。
  ///
  /// POST body 上限 [maxClipboardBodyBytes]，超过返回 413（防恶意大 body
  /// 撑爆内存；剪贴板场景正常内容远小于该值）。
  static const int maxClipboardBodyBytes = 1024 * 1024;

  void _serveClipboardApi(HttpRequest req) {
    if (req.method == 'GET') {
      req.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'text': _text ?? '', 'ts': _updatedAt}))
        ..close();
    } else if (req.method == 'POST') {
      // Content-Length 已知且超限时直接拒绝，不等 body 读完。
      final contentLength = req.contentLength;
      if (contentLength > maxClipboardBodyBytes) {
        req.response
          ..statusCode = HttpStatus.requestEntityTooLarge
          ..headers.contentType = ContentType.text
          ..write('body too large')
          ..close();
        return;
      }
      req.cast<List<int>>().transform(utf8.decoder).join().then((body) {
        // 流式读取时按解码后长度再拦一次（Content-Length 可能缺失）。
        if (body.length > maxClipboardBodyBytes) {
          req.response
            ..statusCode = HttpStatus.requestEntityTooLarge
            ..headers.contentType = ContentType.text
            ..write('body too large')
            ..close();
          return;
        }
        if (body.isEmpty) {
          req.response
            ..statusCode = HttpStatus.badRequest
            ..headers.contentType = ContentType.text
            ..write('empty body')
            ..close();
          return;
        }
        try {
          setText(body);
          req.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.text
            ..write('ok')
            ..close();
        } catch (e) {
          // 广播给 WebSocket 客户端时若连接异常，确保响应仍被关闭，不泄漏。
          debugPrint('ClipboardService: setText failed: $e');
          try {
            req.response
              ..statusCode = HttpStatus.internalServerError
              ..headers.contentType = ContentType.text
              ..write('internal error')
              ..close();
          } catch (_) {}
        }
      });
    } else {
      req.response
        ..statusCode = HttpStatus.methodNotAllowed
        ..close();
    }
  }

  // ── 二维码生成（纯 Dart，零第三方 JS/C 依赖） ──

  /// 颜色参数校验：6 位 hex（可带/不带 #）。
  static final RegExp _hexColorRe = RegExp(r'^[0-9a-fA-F]{6}$');

  /// GET /qr?text=... → image/svg+xml（离线路由，供页面 <img> 直接引用）。
  void _serveQr(HttpRequest req) {
    final qp = req.uri.queryParameters;
    final text = qp['text'] ?? '';
    if (text.isEmpty) {
      req.response
        ..statusCode = HttpStatus.badRequest
        ..headers.contentType = ContentType.text
        ..write('missing text parameter');
      req.response.close();
      return;
    }
    // 样式参数：未知值回落默认，不报错（前端下拉是白名单）。
    final style = qp['style'] ?? 'square';
    // 颜色：允许带/不带 # 的 6 位 hex，非法回落默认。
    String normColor(String? raw, String fallback) {
      if (raw == null) return fallback;
      var v = raw.trim();
      if (v.startsWith('#')) v = v.substring(1);
      return _hexColorRe.hasMatch(v) ? v : fallback;
    }

    final fg = normColor(qp['fg'], '000000');
    final bg = normColor(qp['bg'], 'ffffff');
    try {
      final svg = _qrSvg(text, style: style, fg: fg, bg: bg);
      req.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType('image', 'svg+xml', charset: 'utf-8')
        ..write(svg)
        ..close();
    } on InputTooLongException catch (e) {
      // 文本超出二维码容量（M 纠错约 2953 字节）时 qr 包抛此异常，
      // 返回 400 而非 500，前端 <img> 不会碎裂。
      debugPrint('ClipboardService: QR input too long: $e');
      req.response
        ..statusCode = HttpStatus.badRequest
        ..headers.contentType = ContentType.text
        ..write('text too long for a QR code');
      req.response.close();
    } catch (e) {
      debugPrint('ClipboardService: QR generation failed: $e');
      req.response
        ..statusCode = HttpStatus.internalServerError
        ..headers.contentType = ContentType.text
        ..write('QR generation failed');
      req.response.close();
    }
  }

  /// 用 `qr` 包生成二维码矩阵（`QrCode.fromData` → `QrImage`），遍历
  /// `isDark` 输出 SVG。全程纯 Dart，不上网、不引前端 JS 库，老 WebView /
  /// 文本浏览器都能直接显示。支持三种样式 + 前后景颜色，零体积成本。
  ///
  /// - [style]：`square`（默认，方块）/ `rounded`（圆角）/ `dots`（圆点）
  /// - [fg]/[bg]：6 位 hex，不带 #。
  String _qrSvg(
    String text, {
    int scale = 4,
    int quiet = 4,
    String style = 'square',
    String fg = '000000',
    String bg = 'ffffff',
  }) {
    final img = QrImage(QrCode.fromData(
      data: text,
      errorCorrectLevel: QrErrorCorrectLevel.M,
    ));
    final n = img.moduleCount;
    final size = (n + quiet * 2) * scale;
    final buf = StringBuffer();
    buf.write('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 $size $size">');
    buf.write('<rect width="$size" height="$size" fill="#$bg"/>');

    if (style == 'dots') {
      // 圆点：每个深色模块一个圆，直径约 0.9 模块
      final r = (scale * 0.9 / 2.0).toStringAsFixed(2);
      for (var row = 0; row < n; row++) {
        for (var col = 0; col < n; col++) {
          if (img.isDark(row, col)) {
            final cx = (col + quiet) * scale + scale / 2.0;
            final cy = (row + quiet) * scale + scale / 2.0;
            buf.write('<circle cx="$cx" cy="$cy" r="$r" fill="#$fg"/>');
          }
        }
      }
    } else if (style == 'rounded') {
      // 圆角：每个深色模块一个圆角矩形
      final rx = (scale * 0.4).toStringAsFixed(2);
      for (var row = 0; row < n; row++) {
        for (var col = 0; col < n; col++) {
          if (img.isDark(row, col)) {
            final x = (col + quiet) * scale;
            final y = (row + quiet) * scale;
            buf.write('<rect x="$x" y="$y" width="$scale" height="$scale" rx="$rx" fill="#$fg"/>');
          }
        }
      }
    } else {
      // 方块（默认）：同行连续深色模块合并成一段 path，体积最小
      buf.write('<path d="');
      for (var row = 0; row < n; row++) {
        var col = 0;
        while (col < n) {
          if (img.isDark(row, col)) {
            final start = col;
            while (col < n && img.isDark(row, col)) {
              col++;
            }
            final x = (start + quiet) * scale;
            final y = (row + quiet) * scale;
            final w = (col - start) * scale;
            buf.write('M$x $y h$w v$scale h-$w z ');
          } else {
            col++;
          }
        }
      }
      buf.write('" fill="#$fg"/>');
    }
    buf.write('</svg>');
    return buf.toString();
  }

  // ── WS 消息协议 ──

  /// 服务端 → 客户端：JSON，字段固定。
  String _buildClipboardMsg() {
    return jsonEncode({
      'type': 'clipboard',
      'text': _text ?? '',
      'ts': _updatedAt,
    });
  }

  /// 解析客户端 → 服务端消息。
  /// 客户端发送 JSON：{"type":"set","text":"..."}
  static String? _parseClientMsg(String raw) {
    try {
      final map = jsonDecode(raw) as Map;
      if (map['type'] == 'set' && map['text'] is String) {
        return map['text'] as String;
      }
    } catch (_) {}
    return null;
  }

  // ── 内联 HTML 页面 ──

  String _htmlPage() {
    return '''
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>FileInfra 工具页</title>
<style>
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:-apple-system,sans-serif;background:#f5f5f5;padding:20px;max-width:640px;margin:0 auto}
h1{font-size:20px;margin-bottom:12px;display:flex;align-items:center;gap:8px}
.tabs{display:flex;gap:4px;background:#e9e9e9;border-radius:8px;padding:4px;margin-bottom:16px}
.tab{flex:1;padding:8px 0;font-size:14px;border:none;border-radius:6px;background:transparent;cursor:pointer;font-weight:500;color:#555}
.tab.active{background:#fff;color:#1976d2;box-shadow:0 1px 3px rgba(0,0,0,.12)}
.pane{display:none}
.pane.active{display:block}
.status{font-size:13px;color:#666;margin-bottom:16px;padding:8px 12px;background:#fff;border-radius:8px;border:1px solid #ddd}
.status.connected{color:#2e7d32;background:#e8f5e9;border-color:#a5d6a7}
.status.disconnected{color:#c62828;background:#ffebee;border-color:#ef9a9a}
.tip{font-size:12px;color:#999;margin-bottom:12px}
textarea{width:100%;min-height:120px;padding:12px;font-size:15px;border:1px solid #ddd;border-radius:8px;resize:vertical;font-family:inherit}
textarea:focus{outline:none;border-color:#1976d2}
.actions{display:flex;gap:8px;margin-top:8px;flex-wrap:wrap}
.btn{padding:8px 20px;font-size:14px;border:none;border-radius:6px;cursor:pointer;font-weight:500}
.btn-primary{background:#1976d2;color:#fff}
.btn-primary:hover{background:#1565c0}
.btn-secondary{background:#e0e0e0;color:#333}
.btn-secondary:hover{background:#bdbdbd}
.btn-danger{background:#ffebee;color:#c62828}
.btn-danger:hover{background:#ffcdd2}
.clipboard-display{background:#fff;border:1px solid #ddd;border-radius:8px;padding:12px;margin-bottom:16px;min-height:60px;font-size:15px;line-height:1.5;word-break:break-all}
.clipboard-display:empty::before{content:"暂无内容";color:#bbb}
.clipboard-display .time{font-size:11px;color:#999;margin-top:8px;display:block}
.qr-opts{display:flex;gap:8px;flex-wrap:wrap;align-items:center;margin-bottom:12px;padding:10px;background:#fff;border:1px solid #ddd;border-radius:8px}
.qr-opts label{font-size:13px;color:#555;display:flex;align-items:center;gap:4px}
.qr-opts select,.qr-opts input[type=color]{border:1px solid #ddd;border-radius:6px;background:#fff;height:26px}
.qr-row{background:#fff;border:1px solid #ddd;border-radius:8px;padding:12px;margin-bottom:10px}
.qr-row .qr-input{display:flex;gap:8px;margin-bottom:10px}
.qr-row .qr-input input{flex:1;padding:10px;font-size:14px;border:1px solid #ddd;border-radius:6px;font-family:inherit;min-width:0}
.qr-row .qr-input input:focus{outline:none;border-color:#1976d2}
.qr-out{display:none;text-align:center}
.qr-out img{width:220px;height:220px;background:#fff;border:1px solid #ddd;border-radius:8px;object-fit:contain}
.qr-out .dl{display:inline-flex;align-items:center;gap:4px;margin-top:8px;padding:6px 16px;font-size:13px;border:1px solid #ddd;border-radius:6px;background:#fff;color:#333;cursor:pointer;text-decoration:none}
.qr-out .dl:hover{background:#f0f0f0}
</style>
</head>
<body>
<h1>🧰 工具页</h1>

<div class="tabs">
  <button class="tab active" id="tab-clipboard" onclick="switchTab('clipboard')">📋 剪贴板</button>
  <button class="tab" id="tab-qr" onclick="switchTab('qr')">🔳 二维码</button>
</div>

<!-- ── 剪贴板 ── -->
<div id="pane-clipboard" class="pane active">
  <div id="status" class="status disconnected">⏳ 连接中…</div>
  <div class="tip">⚠️ 剪贴板内容对内网可见，请勿粘贴敏感信息</div>
  <div id="display" class="clipboard-display"><span class="time" id="time"></span></div>
  <textarea id="input" placeholder="粘贴文本到这里…"></textarea>
  <div class="actions">
    <button class="btn btn-primary" onclick="send()">📤 发送到共享剪贴板</button>
    <button class="btn btn-secondary" onclick="copyFromDisplay()">📋 复制到本机</button>
  </div>
</div>

<!-- ── 二维码生成 ── -->
<div id="pane-qr" class="pane">
  <div class="tip">输入文字或网址，生成二维码（本机离线生成，不上传）；可添加多行同时生成</div>
  <div class="qr-opts">
    <label>样式
      <select id="qrstyle">
        <option value="square">方块</option>
        <option value="rounded">圆角</option>
        <option value="dots">圆点</option>
      </select>
    </label>
    <label>前景色 <input type="color" id="qrfg" value="#000000"></label>
    <label>背景色 <input type="color" id="qrbg" value="#ffffff"></label>
    <button class="btn btn-secondary" onclick="addQrRow()">＋ 添加一行</button>
  </div>
  <div id="qrrows"></div>
</div>

<script>
var ws = null;
var statusEl = document.getElementById('status');
var displayEl = document.getElementById('display');
var timeEl = document.getElementById('time');
var inputEl = document.getElementById('input');
var reconnectTimer = null;
var sharedText = '';

function switchTab(name) {
  var panes = document.querySelectorAll('.pane');
  for (var i = 0; i < panes.length; i++) {
    panes[i].className = 'pane' + (panes[i].id === 'pane-' + name ? ' active' : '');
  }
  var tabs = document.querySelectorAll('.tab');
  for (var j = 0; j < tabs.length; j++) {
    tabs[j].className = 'tab' + (tabs[j].id === 'tab-' + name ? ' active' : '');
  }
}

function qrUrl(text) {
  var style = document.getElementById('qrstyle').value;
  var fg = document.getElementById('qrfg').value.replace('#', '');
  var bg = document.getElementById('qrbg').value.replace('#', '');
  return '/qr?text=' + encodeURIComponent(text) + '&style=' + style + '&fg=' + fg + '&bg=' + bg;
}

function addQrRow() {
  var rows = document.getElementById('qrrows');
  var row = document.createElement('div');
  row.className = 'qr-row';
  row.innerHTML =
    '<div class="qr-input">' +
      '<input type="text" placeholder="输入文字或网址…">' +
      '<button class="btn btn-primary" onclick="genQr(this)">生成</button>' +
      '<button class="btn btn-danger" onclick="delQrRow(this)">✕</button>' +
    '</div>' +
    '<div class="qr-out"><img alt="二维码"><br><a class="dl" onclick="downloadQr(this)">⬇ 下载 SVG</a></div>';
  rows.appendChild(row);
  row.querySelector('input').focus();
}

function genQr(btn) {
  var row = btn.parentNode.parentNode;
  var input = row.querySelector('input');
  var text = input.value.trim();
  if (!text) return;
  var img = row.querySelector('.qr-out img');
  img.src = qrUrl(text);
  row.querySelector('.qr-out').style.display = 'block';
}

function delQrRow(btn) {
  btn.parentNode.parentNode.remove();
}

function downloadQr(el) {
  var row = el.parentNode.parentNode;
  var img = row.querySelector('.qr-out img');
  if (!img.src) return;
  var a = document.createElement('a');
  a.href = img.src;
  a.download = 'qrcode.svg';
  document.body.appendChild(a);
  a.click();
  a.remove();
}

function connect() {
  var proto = location.protocol === 'https:' ? 'wss:' : 'ws:';
  ws = new WebSocket(proto + '//' + location.host + '/');
  ws.onopen = function() {
    statusEl.textContent = '✅ 已连接';
    statusEl.className = 'status connected';
  };
  ws.onmessage = function(e) {
    try {
      var msg = JSON.parse(e.data);
      if (msg.type === 'clipboard') {
        sharedText = msg.text;
        displayEl.textContent = sharedText;
        if (msg.ts) {
          var d = new Date(msg.ts);
          timeEl.textContent = '同步于 ' + d.toLocaleString();
        }
        displayEl.appendChild(timeEl);
      }
    } catch(err) {}
  };
  ws.onclose = function() {
    statusEl.textContent = '❌ 已断开，正在重连…';
    statusEl.className = 'status disconnected';
    ws = null;
    reconnectTimer = setTimeout(connect, 3000);
  };
  ws.onerror = function() {};
}

function send() {
  var text = inputEl.value.trim();
  if (!text) return;
  if (ws && ws.readyState === WebSocket.OPEN) {
    ws.send(JSON.stringify({type: 'set', text: text}));
    inputEl.value = '';
  }
}

async function copyFromDisplay() {
  var text = sharedText;
  if (!text) return;
  try {
    if (navigator.clipboard && window.isSecureContext) {
      await navigator.clipboard.writeText(text);
    } else {
      var copyInput = document.createElement('textarea');
      copyInput.value = text;
      copyInput.setAttribute('readonly', '');
      copyInput.style.position = 'fixed';
      copyInput.style.opacity = '0';
      document.body.appendChild(copyInput);
      copyInput.select();
      var copied = document.execCommand('copy');
      copyInput.remove();
      if (!copied) throw new Error('Copy command failed');
    }
  } catch (err) {
    window.prompt('请手动复制共享内容：', text);
  }
}

addQrRow();
connect();
</script>
</body>
</html>
''';
  }
}
