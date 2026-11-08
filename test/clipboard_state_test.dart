import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_infra/services/clipboard_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ClipboardService service;
  late HttpClient http;

  setUp(() async {
    service = ClipboardService();
    http = HttpClient();
    await service.start(0);
  });
  tearDown(() async {
    http.close(force: true);
    await service.stop();
  });

  Future<Map<String, dynamic>> getSnapshot() async {
    final request = await http.getUrl(
      Uri.parse('http://127.0.0.1:${service.port}/api/clipboard'),
    );
    final response = await request.close();
    return jsonDecode(await utf8.decoder.bind(response).join())
        as Map<String, dynamic>;
  }

  test('new WebSocket receives an empty snapshot after a restart', () async {
    service.setText('previous session');
    await service.stop();
    await service.start(0);
    final ws = await WebSocket.connect('ws://127.0.0.1:${service.port}/');
    addTearDown(ws.close);
    final message = jsonDecode(
      await ws.first.timeout(const Duration(seconds: 1)) as String,
    );
    expect(message, {'type': 'clipboard', 'text': '', 'ts': 0});
    expect(await getSnapshot(), {'text': '', 'ts': 0});
  });

  test('sender receives the authoritative clipboard value', () async {
    service.setText('old');
    final ws = await WebSocket.connect('ws://127.0.0.1:${service.port}/');
    addTearDown(ws.close);
    final messages = StreamIterator<dynamic>(ws);
    addTearDown(messages.cancel);
    expect(await messages.moveNext(), isTrue);
    expect(jsonDecode(messages.current as String)['text'], 'old');
    ws.add(jsonEncode({'type': 'set', 'text': '  new\ntext\n'}));
    expect(
      await messages.moveNext().timeout(const Duration(seconds: 1)),
      isTrue,
    );
    expect(jsonDecode(messages.current as String)['text'], '  new\ntext\n');
    expect((await getSnapshot())['text'], '  new\ntext\n');
  });

  test(
    'stop closes several WebSocket clients and clears the session',
    () async {
      final disconnected = <Future<void>>[];
      for (var i = 0; i < 3; i++) {
        final ws = await WebSocket.connect('ws://127.0.0.1:${service.port}/');
        final closed = Completer<void>();
        ws.listen((_) {}, onDone: closed.complete);
        disconnected.add(closed.future);
      }
      service.setText('session');
      await service.stop();
      await Future.wait(disconnected).timeout(const Duration(seconds: 2));
      expect(service.isRunning, isFalse);
      expect(service.port, isNull);
      expect(service.text, isNull);
    },
  );

  test('chunked multibyte POST is limited by UTF-8 bytes', () async {
    service.setText('unchanged');
    final request = await http.postUrl(
      Uri.parse('http://127.0.0.1:${service.port}/api/clipboard'),
    );
    final text = '界' * (ClipboardService.maxClipboardBodyBytes ~/ 3 + 1);
    request.add(utf8.encode(text));
    final response = await request.close();
    await response.drain<void>();
    expect(response.statusCode, HttpStatus.requestEntityTooLarge);
    expect(service.text, 'unchanged');
  });

  test(
    'oversized stream is rejected before the client finishes its body',
    () async {
      final socket = await Socket.connect('127.0.0.1', service.port!);
      addTearDown(socket.destroy);
      final bytes = List<int>.filled(
        ClipboardService.maxClipboardBodyBytes + 1,
        65,
      );
      socket.write(
        'POST /api/clipboard HTTP/1.1\r\n'
        'Host: 127.0.0.1:${service.port}\r\nTransfer-Encoding: chunked\r\n\r\n'
        '${bytes.length.toRadixString(16)}\r\n',
      );
      socket.add(bytes);
      socket.write('\r\n');
      await socket.flush();
      // Deliberately omit the final zero chunk. The server must stop reading at
      // the byte limit instead of buffering an unbounded stream with join().
      final response = await utf8.decoder
          .bind(socket)
          .first
          .timeout(const Duration(seconds: 2));
      expect(response, startsWith('HTTP/1.1 413'));
      expect(service.text, isNull);
    },
  );

  test('invalid UTF-8 POST returns 400 without changing shared text', () async {
    service.setText('unchanged');
    final request = await http.postUrl(
      Uri.parse('http://127.0.0.1:${service.port}/api/clipboard'),
    );
    request.add([0xc3, 0x28]);
    final response = await request.close().timeout(const Duration(seconds: 2));
    await response.drain<void>();
    expect(response.statusCode, HttpStatus.badRequest);
    expect(service.text, 'unchanged');
  });

  test('oversized WebSocket frame is closed without broadcasting', () async {
    service.setText('unchanged');
    final ws = await WebSocket.connect('ws://127.0.0.1:${service.port}/');
    addTearDown(ws.close);
    final messages = StreamIterator<dynamic>(ws);
    addTearDown(messages.cancel);
    expect(await messages.moveNext(), isTrue);
    ws.add(
      jsonEncode({
        'type': 'set',
        'text': '界' * (ClipboardService.maxClipboardBodyBytes ~/ 3 + 1),
      }),
    );
    expect(
      await messages.moveNext().timeout(const Duration(seconds: 2)),
      isFalse,
    );
    expect(ws.closeCode, WebSocketStatus.messageTooBig);
    expect(service.text, 'unchanged');
  });

  for (final origin in ['https://unrelated.example', 'null']) {
    test('foreign Origin $origin cannot POST or connect a WebSocket', () async {
      service.setText('unchanged');
      final request = await http.postUrl(
        Uri.parse('http://127.0.0.1:${service.port}/api/clipboard'),
      );
      request.headers.set('Origin', origin);
      request.write('injected');
      final response = await request.close();
      await response.drain<void>();
      expect(response.statusCode, HttpStatus.forbidden);
      expect(service.text, 'unchanged');
      await expectLater(
        WebSocket.connect(
          'ws://127.0.0.1:${service.port}/',
          headers: {'Origin': origin},
        ),
        throwsA(isA<WebSocketException>()),
      );
    });
  }

  test('matching Origin can POST and connect a WebSocket', () async {
    final origin = 'http://127.0.0.1:${service.port}';
    final request = await http.postUrl(Uri.parse('$origin/api/clipboard'));
    request.headers.set('Origin', origin);
    request.write('same origin');
    final response = await request.close();
    await response.drain<void>();
    expect(response.statusCode, HttpStatus.ok);
    final ws = await WebSocket.connect(
      'ws://127.0.0.1:${service.port}/',
      headers: {'Origin': origin},
    );
    addTearDown(ws.close);
    final message = jsonDecode(await ws.first as String);
    expect(message['text'], 'same origin');
  });
}
