import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_infra/services/clipboard_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// ClipboardService 单测：HTTP 页面 + WebSocket 双向同步 + 端口跟随 + 占用降级。
void main() {
  test('同一端口同时服务 HTTP 页面与 WebSocket 双向同步', () async {
    // 启动一个 dummy 服务作为"dufs"，剪贴板应绑到 dufsPort + portOffset
    final dummy = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final dufsPort = dummy.port;
    final cbPort = dufsPort + ClipboardService.portOffset;

    final svc = ClipboardService();
    await svc.start(dufsPort);
    expect(svc.isRunning, isTrue);
    expect(svc.port, cbPort);

    // 1) HTTP：根路径返回剪贴板页面
    final hc = HttpClient();
    final hreq = await hc.getUrl(Uri.parse('http://127.0.0.1:$cbPort/'));
    final hres = await hreq.close();
    expect(hres.statusCode, HttpStatus.ok);
    final hbody = await hres.transform(utf8.decoder).join();
    expect(hbody, contains('共享剪贴板'));
    expect(hbody, contains('WebSocket'));

    // 2) WS：客户端 A
    final wsA = await WebSocket.connect('ws://127.0.0.1:$cbPort/');
    final aGotB = Completer<void>();
    final aMsgs = <String>[];
    wsA.listen((d) {
      final s = d as String;
      aMsgs.add(s);
      if (s.contains('hello from B')) aGotB.complete();
    });

    // 3) WS：客户端 B
    final wsB = await WebSocket.connect('ws://127.0.0.1:$cbPort/');
    final bGotA = Completer<void>();
    final bMsgs = <String>[];
    wsB.listen((d) {
      final s = d as String;
      bMsgs.add(s);
      if (s.contains('hello from A')) bGotA.complete();
    });

    // 4) A 发送 → B 应收到
    wsA.add(jsonEncode({'type': 'set', 'text': 'hello from A'}));
    await bGotA.future.timeout(const Duration(seconds: 2));
    expect(bMsgs.any((m) => m.contains('hello from A')), isTrue);

    // 5) B 发送 → A 应收到
    wsB.add(jsonEncode({'type': 'set', 'text': 'hello from B'}));
    await aGotB.future.timeout(const Duration(seconds: 2));
    expect(aMsgs.any((m) => m.contains('hello from B')), isTrue);

    // 6) HTTP 页面仍可用
    final hreq2 = await hc.getUrl(Uri.parse('http://127.0.0.1:$cbPort/'));
    final hres2 = await hreq2.close();
    final hbody2 = await hres2.transform(utf8.decoder).join();
    expect(hbody2, contains('共享剪贴板'));

    await wsA.close();
    await wsB.close();
    await svc.stop();
    await dummy.close(force: true);
    expect(svc.isRunning, isFalse);
  });

  test('剪贴板端口被占用时自动+1 最多 9 步', () async {
    final dummy = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final dufsPort = dummy.port;

    // 占用 dufsPort + portOffset（剪贴板首选端口）
    final blocker = await HttpServer.bind(InternetAddress.loopbackIPv4, dufsPort + ClipboardService.portOffset);

    final svc = ClipboardService();
    await svc.start(dufsPort);
    // 首选端口被占，应退到 +1
    expect(svc.isRunning, isTrue);
    expect(svc.port, dufsPort + ClipboardService.portOffset + 1);

    await svc.stop();
    await blocker.close(force: true);
    await dummy.close(force: true);
  });

  test('浏览器不安全端口（6000=X11）自动跳过', () async {
    final dummy = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final dufsPort = 4000; // 剪贴板首选 = 6000（X11，浏览器禁用）
    await dummy.close(force: true);

    final svc = ClipboardService();
    await svc.start(dufsPort);
    expect(svc.isRunning, isTrue);
    expect(svc.port, 6001); // 跳过 6000 → 6001

    await svc.stop();
  });

  test('端口范围全部被占时降级跳过', () async {
    final dummy = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final dufsPort = dummy.port;

    // 占满 dufsPort+portOffset 起的全部 10 个候选端口。
    final blockers = <HttpServer>[];
    for (var i = 0; i <= ClipboardService.maxBump; i++) {
      final s = await HttpServer.bind(InternetAddress.loopbackIPv4, dufsPort + ClipboardService.portOffset + i);
      blockers.add(s);
    }

    final svc = ClipboardService();
    await svc.start(dufsPort);
    expect(svc.isRunning, isFalse);
    expect(svc.port, isNull);

    for (final s in blockers) {
      await s.close(force: true);
    }
    await dummy.close(force: true);
  });

  test('GET /qr 返回 SVG 二维码（离线路由）', () async {
    final dummy = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final svc = ClipboardService();
    await svc.start(dummy.port);
    final cbPort = svc.port!;

    final hc = HttpClient();
    final req = await hc.getUrl(Uri.parse('http://127.0.0.1:$cbPort/qr?text=hello'));
    final res = await req.close();
    expect(res.statusCode, HttpStatus.ok);
    expect(res.headers.contentType?.mimeType, 'image/svg+xml');
    final body = await res.transform(utf8.decoder).join();
    expect(body, startsWith('<svg xmlns="http://www.w3.org/2000/svg"'));
    expect(body, contains('<path d="'));
    expect(body, endsWith('</svg>'));

    await svc.stop();
    await dummy.close(force: true);
  });

  test('GET /qr 缺 text 参数返回 400', () async {
    final dummy = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final svc = ClipboardService();
    await svc.start(dummy.port);
    final cbPort = svc.port!;

    final hc = HttpClient();
    final req = await hc.getUrl(Uri.parse('http://127.0.0.1:$cbPort/qr'));
    final res = await req.close();
    expect(res.statusCode, HttpStatus.badRequest);

    await svc.stop();
    await dummy.close(force: true);
  });

  test('二维码生成是确定性的（同一文本 → 相同 SVG）', () async {
    final dummy = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final svc = ClipboardService();
    await svc.start(dummy.port);
    final cbPort = svc.port!;

    final hc = HttpClient();
    Future<String> fetch(String text) async {
      final req = await hc.getUrl(
        Uri.parse('http://127.0.0.1:$cbPort/qr?text=${Uri.encodeQueryComponent(text)}'),
      );
      final res = await req.close();
      expect(res.statusCode, HttpStatus.ok);
      return res.transform(utf8.decoder).join();
    }
    final a = await fetch('https://example.com/path?q=1');
    final b = await fetch('https://example.com/path?q=1');
    final c = await fetch('different content');
    expect(a, b);
    expect(a, isNot(c));

    await svc.stop();
    await dummy.close(force: true);
  });

  test('页面 HTML 含工具页标题 + 选项卡 + 二维码区域', () async {
    final dummy = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final svc = ClipboardService();
    await svc.start(dummy.port);
    final cbPort = svc.port!;

    final hc = HttpClient();
    final req = await hc.getUrl(Uri.parse('http://127.0.0.1:$cbPort/'));
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    expect(body, contains('工具页'));
    expect(body, contains('剪贴板'));
    expect(body, contains('生成二维码'));
    expect(body, contains('genQr'));
    expect(body, contains('/qr?text='));
    expect(body, contains('添加一行'));
    expect(body, contains('qrstyle'));
    expect(body, contains('downloadQr'));

    await svc.stop();
    await dummy.close(force: true);
  });

  test('GET /qr 支持 style=rounded 返回圆角矩形', () async {
    final dummy = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final svc = ClipboardService();
    await svc.start(dummy.port);
    final cbPort = svc.port!;

    final hc = HttpClient();
    final req = await hc.getUrl(Uri.parse('http://127.0.0.1:$cbPort/qr?text=hi&style=rounded'));
    final res = await req.close();
    expect(res.statusCode, HttpStatus.ok);
    final body = await res.transform(utf8.decoder).join();
    expect(body, contains('rx="'));
    expect(body, contains('<rect'));
    expect(body, isNot(contains('<circle')));

    await svc.stop();
    await dummy.close(force: true);
  });

  test('GET /qr 支持 style=dots 返回圆点', () async {
    final dummy = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final svc = ClipboardService();
    await svc.start(dummy.port);
    final cbPort = svc.port!;

    final hc = HttpClient();
    final req = await hc.getUrl(Uri.parse('http://127.0.0.1:$cbPort/qr?text=hi&style=dots'));
    final res = await req.close();
    expect(res.statusCode, HttpStatus.ok);
    final body = await res.transform(utf8.decoder).join();
    expect(body, contains('<circle'));
    // 圆点样式下不应有模块级 <rect>（仅背景色 rect）
    expect(body, isNot(contains('<rect x=')));

    await svc.stop();
    await dummy.close(force: true);
  });

  test('GET /qr 支持 fg/bg 颜色参数', () async {
    final dummy = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final svc = ClipboardService();
    await svc.start(dummy.port);
    final cbPort = svc.port!;

    final hc = HttpClient();
    final req = await hc.getUrl(Uri.parse('http://127.0.0.1:$cbPort/qr?text=hi&fg=ff0000&bg=00ff00'));
    final res = await req.close();
    expect(res.statusCode, HttpStatus.ok);
    final body = await res.transform(utf8.decoder).join();
    expect(body, contains('fill="#ff0000"'));
    expect(body, contains('fill="#00ff00"'));

    await svc.stop();
    await dummy.close(force: true);
  });

  test('GET /qr 未知 style 回落方形', () async {
    final dummy = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final svc = ClipboardService();
    await svc.start(dummy.port);
    final cbPort = svc.port!;

    final hc = HttpClient();
    final req = await hc.getUrl(Uri.parse('http://127.0.0.1:$cbPort/qr?text=hi&style=invalid'));
    final res = await req.close();
    expect(res.statusCode, HttpStatus.ok);
    final body = await res.transform(utf8.decoder).join();
    expect(body, contains('<path d="'));

    await svc.stop();
    await dummy.close(force: true);
  });

  test('GET /qr 非法颜色回落默认', () async {
    final dummy = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final svc = ClipboardService();
    await svc.start(dummy.port);
    final cbPort = svc.port!;

    final hc = HttpClient();
    final req = await hc.getUrl(Uri.parse('http://127.0.0.1:$cbPort/qr?text=hi&fg=zzz&bg=12'));
    final res = await req.close();
    expect(res.statusCode, HttpStatus.ok);
    final body = await res.transform(utf8.decoder).join();
    expect(body, contains('fill="#000000"'));
    expect(body, contains('fill="#ffffff"'));

    await svc.stop();
    await dummy.close(force: true);
  });

  test('GET /api/clipboard 返回当前共享文本（JSON）', () async {
    final dummy = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final svc = ClipboardService();
    await svc.start(dummy.port);
    final cbPort = svc.port!;

    final hc = HttpClient();
    // 先 POST 写入，再 GET 读取
    final post = await hc.postUrl(Uri.parse('http://127.0.0.1:$cbPort/api/clipboard'));
    post.headers.contentType = ContentType.text;
    post.write('hello from api');
    final postRes = await post.close();
    expect(postRes.statusCode, HttpStatus.ok);

    final req = await hc.getUrl(Uri.parse('http://127.0.0.1:$cbPort/api/clipboard'));
    final res = await req.close();
    expect(res.statusCode, HttpStatus.ok);
    expect(res.headers.contentType?.mimeType, 'application/json');
    final body = await res.transform(utf8.decoder).join();
    final json = jsonDecode(body) as Map;
    expect(json['text'], 'hello from api');
    expect(json['ts'], isA<int>());

    await svc.stop();
    await dummy.close(force: true);
  });

  test('POST /api/clipboard 广播给 WebSocket 客户端', () async {
    final dummy = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final svc = ClipboardService();
    await svc.start(dummy.port);
    final cbPort = svc.port!;

    final ws = await WebSocket.connect('ws://127.0.0.1:$cbPort/');
    final gotMsg = Completer<String>();
    ws.listen((d) {
      final s = d as String;
      if (s.contains('broadcast me')) gotMsg.complete(s);
    });

    final hc = HttpClient();
    final post = await hc.postUrl(Uri.parse('http://127.0.0.1:$cbPort/api/clipboard'));
    post.headers.contentType = ContentType.text;
    post.write('broadcast me');
    final postRes = await post.close();
    expect(postRes.statusCode, HttpStatus.ok);

    final msg = await gotMsg.future.timeout(const Duration(seconds: 2));
    expect(msg, contains('broadcast me'));

    await ws.close();
    await svc.stop();
    await dummy.close(force: true);
  });

  test('POST /api/clipboard 空 body 返回 400', () async {
    final dummy = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final svc = ClipboardService();
    await svc.start(dummy.port);
    final cbPort = svc.port!;

    final hc = HttpClient();
    final post = await hc.postUrl(Uri.parse('http://127.0.0.1:$cbPort/api/clipboard'));
    post.headers.contentType = ContentType.text;
    final postRes = await post.close();
    expect(postRes.statusCode, HttpStatus.badRequest);

    await svc.stop();
    await dummy.close(force: true);
  });

  test('GET /qr 超长文本返回 400 不崩溃（防 InputTooLongException）', () async {
    final dummy = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final svc = ClipboardService();
    await svc.start(dummy.port);
    final cbPort = svc.port!;

    // M 纠错容量约 2953 字节，远超则抛 InputTooLongException，应回落 400。
    final longText = 'x' * 10000;
    final hc = HttpClient();
    final get = await hc.getUrl(
      Uri.parse('http://127.0.0.1:$cbPort/qr?text=${Uri.encodeQueryComponent(longText)}'),
    );
    final res = await get.close();
    expect(res.statusCode, HttpStatus.badRequest);
    final body = await res.transform(utf8.decoder).join();
    expect(body, contains('too long'));

    // 服务仍存活，正常文本可继续生成。
    final ok = await hc.getUrl(
      Uri.parse('http://127.0.0.1:$cbPort/qr?text=hello'),
    );
    final okRes = await ok.close();
    expect(okRes.statusCode, HttpStatus.ok);

    hc.close(force: true);
    await svc.stop();
    await dummy.close(force: true);
  });

  test('POST /api/clipboard 超大 body 返回 413', () async {
    final dummy = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final svc = ClipboardService();
    await svc.start(dummy.port);
    final cbPort = svc.port!;

    // 显式 Content-Length 超限 → 直接 413（不走流式读取）。
    final big = List.filled(ClipboardService.maxClipboardBodyBytes + 1, 0x61); // 'a'
    final hc = HttpClient();
    final post = await hc.postUrl(Uri.parse('http://127.0.0.1:$cbPort/api/clipboard'));
    post.headers.contentType = ContentType.text;
    post.add(big);
    final res = await post.close();
    expect(res.statusCode, HttpStatus.requestEntityTooLarge);
    await res.drain<void>();

    hc.close(force: true);
    await svc.stop();
    await dummy.close(force: true);
  });

  test('WebSocket 收到二进制帧不崩溃（仅处理文本帧）', () async {
    final dummy = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final svc = ClipboardService();
    await svc.start(dummy.port);
    final cbPort = svc.port!;

    // 发送者：先发二进制帧，再发文本帧。
    final sender = await WebSocket.connect('ws://127.0.0.1:$cbPort/');
    // 另开接收连接，验证二进制帧之后的文本仍可同步。
    final receiver = await WebSocket.connect('ws://127.0.0.1:$cbPort/');
    final received = Completer<String>();
    receiver.listen((data) {
      if (data is String && !received.isCompleted &&
          jsonDecode(data)['text'] == 'after-binary') {
        received.complete(data);
      }
    });

    // 二进制帧应被忽略（服务端仅处理文本帧），不崩溃。
    sender.add(utf8.encode('ignored-binary'));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    // 文本帧仍正常广播。
    sender.add(jsonEncode({'type': 'set', 'text': 'after-binary'}));
    final msg = jsonDecode(await received.future.timeout(const Duration(seconds: 2)));
    expect(msg['text'], 'after-binary');

    await sender.close();
    await receiver.close();
    await svc.stop();
    await dummy.close(force: true);
  });
}
