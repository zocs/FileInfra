import 'dart:async';
import 'dart:io';

import 'package:file_infra/models/server_config.dart';
import 'package:file_infra/services/dufs_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final previousHttpOverrides = HttpOverrides.current;

  for (final dispose in [false, true]) {
    test(
      '${dispose ? 'dispose' : 'stop'} while resolving an iOS executable clears committed startup state',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'fi-ios-cancel-',
        );
        final binaryPath = p.join(directory.path, 'dufs');
        final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        final port = probe.port;
        await probe.close();
        final checkStarted = Completer<void>();
        final checkReply = Completer<bool>();
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => directory.path,
        );
        final service = DufsService();
        try {
          await IOOverrides.runZoned(
            () async {
              final starting = service.startServer(
                ServerConfig(path: directory.path, port: port),
              );
              await checkStarted.future;
              expect(service.activePort, port);
              if (dispose) {
                service.dispose();
              } else {
                await service.stopServer();
              }
              checkReply.complete(false);
              await starting;
              expect(service.error, isNull);
              expect(service.activePort, 0);
              expect(service.serverUrl, isNull);
              expect(service.isRunning, isFalse);
            },
            createFile: (path) {
              if (path == Platform.resolvedExecutable) {
                return _ExecutableFile(path, directory);
              }
              if (path == binaryPath) {
                return _PendingExecutable(path, checkStarted, checkReply);
              }
              return IOOverrides.runWithIOOverrides(
                () => File(path),
                _RealIO(),
              );
            },
          );
        } finally {
          if (!checkReply.isCompleted) checkReply.complete(false);
          if (!dispose) {
            await service.stopServer();
            service.dispose();
          }
          debugDefaultTargetPlatformOverride = null;
          binding.defaultBinaryMessenger.setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            null,
          );
          await directory.delete(recursive: true);
        }
      },
    );
  }

  test(
    'unexpected iOS child exit closes the tools listener and its clients',
    () async {
      final directory = await Directory.systemTemp.createTemp('fi-ios-child-');
      final executable = File('${directory.path}/dufs');
      await executable.writeAsString('''#!/usr/bin/env python3
import http.server
import os
import sys
import threading
import time

port = int(sys.argv[sys.argv.index('-p') + 1])
def watch_exit():
    while not os.path.exists('exit-child'):
        time.sleep(0.02)
    os._exit(0)
threading.Thread(target=watch_exit, daemon=True).start()
http.server.HTTPServer(('127.0.0.1', port), http.server.SimpleHTTPRequestHandler).serve_forever()
''');
      await Process.run('chmod', ['700', executable.path]);
      final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = probe.port;
      await probe.close();
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      HttpOverrides.global = null;
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (_) async => directory.path,
      );
      final service = DufsService();
      WebSocket? socket;
      final stopped = Completer<void>();
      var observeExit = false;
      service.addListener(() {
        if (observeExit && !service.isRunning && !stopped.isCompleted) {
          stopped.complete();
        }
      });
      try {
        await IOOverrides.runZoned(
          () async {
            await service.startServer(
              ServerConfig(path: directory.path, port: port),
            );
            expect(service.isRunning, isTrue);
            observeExit = true;
            final toolsPort = Uri.parse(service.clipboardUrl!).port;
            socket = await WebSocket.connect('ws://127.0.0.1:$toolsPort/');
            final closed = Completer<void>();
            socket!.listen((_) {}, onDone: closed.complete);
            await File('${directory.path}/exit-child').writeAsString('exit');
            await stopped.future.timeout(const Duration(seconds: 3));
            expect(service.serverUrl, isNull);
            expect(service.clipboardUrl, isNull);
            await closed.future.timeout(const Duration(seconds: 3));
            final client = HttpClient();
            try {
              client.connectionTimeout = const Duration(milliseconds: 500);
              await expectLater(
                client.getUrl(Uri.parse('http://127.0.0.1:$toolsPort/')),
                throwsA(isA<SocketException>()),
              );
            } finally {
              client.close(force: true);
            }
          },
          createFile: (path) => path == Platform.resolvedExecutable
              ? _ExecutableFile(path, directory)
              : IOOverrides.runWithIOOverrides(() => File(path), _RealIO()),
        );
      } finally {
        await socket?.close();
        await service.stopServer();
        service.dispose();
        debugDefaultTargetPlatformOverride = null;
        HttpOverrides.global = previousHttpOverrides;
        binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
        await directory.delete(recursive: true);
      }
    },
    skip: !Platform.isLinux,
  );
}

final class _RealIO extends IOOverrides {}

class _ExecutableFile implements File {
  @override
  final String path;
  @override
  final Directory parent;
  _ExecutableFile(this.path, this.parent);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unexpected file operation: ${invocation.memberName}',
  );
}

class _PendingExecutable implements File {
  @override
  final String path;
  final Completer<void> started;
  final Completer<bool> reply;
  _PendingExecutable(this.path, this.started, this.reply);

  @override
  Future<bool> exists() {
    if (!started.isCompleted) started.complete();
    return reply.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unexpected file operation: ${invocation.memberName}',
  );
}
