import 'dart:async';
import 'dart:io';

import 'package:file_infra/models/server_config.dart';
import 'package:file_infra/services/dufs_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    debugDefaultTargetPlatformOverride = Platform.isMacOS
        ? TargetPlatform.macOS
        : Platform.isWindows
        ? TargetPlatform.windows
        : TargetPlatform.linux;
  });
  tearDown(() => debugDefaultTargetPlatformOverride = null);
  test(
    'stop during a failed port probe cancels further cleanup and port notices',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'fi-cancel-busy-port-',
      );
      final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = probe.port;
      final bindStarted = Completer<void>();
      final bindReply = Completer<ServerSocket>();
      var bindCalls = 0;
      final service = DufsService();
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (_) async => directory.path,
      );
      try {
        await IOOverrides.runZoned(
          () async {
            final starting = service.startServer(
              ServerConfig(path: directory.path, port: port),
            );
            await bindStarted.future;
            await service.stopServer();
            bindReply.completeError(const SocketException('port is busy'));
            await starting;
            expect(service.portInfo, isNull);
            expect(
              bindCalls,
              1,
              reason: 'canceled start must stop probing ports',
            );
          },
          serverSocketBind:
              (
                address,
                requestedPort, {
                int backlog = 0,
                bool v6Only = false,
                bool shared = false,
              }) {
                bindCalls++;
                if (bindCalls == 1) {
                  bindStarted.complete();
                  return bindReply.future;
                }
                return Future.value(probe);
              },
        );
      } finally {
        await probe.close();
        await service.stopServer();
        service.dispose();
        await directory.delete(recursive: true);
        binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
      }
    },
    skip: !(Platform.isLinux || Platform.isMacOS || Platform.isWindows),
  );
  for (final dispose in [false, true]) {
    test(
      '${dispose ? 'dispose' : 'stop'} during port resolution cancels the desktop start',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'fi-cancel-start-',
        );
        final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        final port = probe.port;
        final bindStarted = Completer<void>();
        final bindReply = Completer<ServerSocket>();
        final service = DufsService();
        binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => directory.path,
        );
        try {
          await IOOverrides.runZoned(
            () async {
              final starting = service.startServer(
                ServerConfig(path: directory.path, port: port),
              );
              await bindStarted.future;
              if (dispose) {
                service.dispose();
              } else {
                await service.stopServer();
              }
              bindReply.complete(probe);
              await starting;
              expect(service.isRunning, isFalse);
              expect(service.activePort, 0);
              expect(service.serverUrl, isNull);
              expect(service.clipboardUrl, isNull);
            },
            serverSocketBind:
                (
                  address,
                  requestedPort, {
                  int backlog = 0,
                  bool v6Only = false,
                  bool shared = false,
                }) {
                  expect(requestedPort, port);
                  if (!bindStarted.isCompleted) bindStarted.complete();
                  return bindReply.future;
                },
          );
        } finally {
          if (!bindReply.isCompleted) bindReply.complete(probe);
          await probe.close();
          if (!dispose) {
            await service.stopServer();
            service.dispose();
          }
          await directory.delete(recursive: true);
          binding.defaultBinaryMessenger.setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            null,
          );
        }
      },
      skip: !(Platform.isLinux || Platform.isMacOS || Platform.isWindows),
    );

    test(
      '${dispose ? 'dispose' : 'stop'} during a file check suppresses obsolete validation errors',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'fi-cancel-file-check-',
        );
        final target = File('${directory.path}/shared.txt');
        await target.writeAsString('shared content');
        final checkStarted = Completer<void>();
        final checkReply = Completer<bool>();
        final service = DufsService();
        binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => directory.path,
        );
        try {
          await IOOverrides.runZoned(
            () async {
              final starting = service.startServer(
                ServerConfig(path: target.path, shareSingleFile: true),
              );
              await checkStarted.future;
              if (dispose) {
                service.dispose();
              } else {
                await service.stopServer();
              }
              checkReply.complete(false);
              await starting;
              expect(service.error, isNull);
              expect(service.activePort, 0);
              expect(service.isRunning, isFalse);
            },
            createFile: (path) => path == target.path
                ? _PendingFileCheck(path, checkStarted, checkReply)
                : IOOverrides.runWithIOOverrides(() => File(path), _RealIO()),
          );
        } finally {
          if (!checkReply.isCompleted) checkReply.complete(false);
          if (!dispose) {
            await service.stopServer();
            service.dispose();
          }
          await directory.delete(recursive: true);
          binding.defaultBinaryMessenger.setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            null,
          );
        }
      },
    );
  }
}

final class _RealIO extends IOOverrides {}

class _PendingFileCheck implements File {
  @override
  final String path;
  final Completer<void> started;
  final Completer<bool> reply;

  _PendingFileCheck(this.path, this.started, this.reply);

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
