import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_infra/constants.dart';
import 'package:file_infra/services/dufs_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(kMethodChannel);
  late Directory temporary;
  late HttpServer nativeServer;
  late DufsService service;
  late Map<String, Object> nativeInfo;
  final previousHttpOverrides = HttpOverrides.current;
  final addressUpdates = <Map<dynamic, dynamic>>[];

  Future<void> nativeStopped(int generation) async {
    final response = Completer<void>();
    binding.defaultBinaryMessenger.handlePlatformMessage(
      kMethodChannel,
      const StandardMethodCodec().encodeMethodCall(
        MethodCall('serviceStopped', {'generation': generation}),
      ),
      (_) => response.complete(),
    );
    await response.future;
  }

  Future<void> expectToolsClosed(String url) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 1);
    try {
      await expectLater(
        client.getUrl(Uri.parse('$url/api/clipboard')),
        throwsA(isA<SocketException>()),
      );
    } finally {
      client.close(force: true);
    }
  }

  setUp(() async {
    HttpOverrides.global = null;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    temporary = await Directory.systemTemp.createTemp('fi-android-lifecycle-');
    nativeServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    nativeServer.listen((request) => request.response.close());
    nativeInfo = {
      'isRunning': true,
      'port': nativeServer.port,
      'path': temporary.path,
      'address': 'http://127.0.0.1:${nativeServer.port}',
      'clipboardAddress': '',
      'generation': 1,
      'error': '',
    };
    addressUpdates.clear();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      switch (call.method) {
        case 'getServiceInfo':
          return Map<String, Object>.of(nativeInfo);
        case 'updateNotificationAddress':
          addressUpdates.add(call.arguments as Map);
          return true;
        case 'stopForegroundService':
          nativeInfo['isRunning'] = false;
          return true;
        case 'log':
          return null;
        default:
          throw MissingPluginException(call.method);
      }
    });
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => temporary.path,
    );
    service = DufsService();
  });

  tearDown(() async {
    await service.stopServer();
    service.dispose();
    await nativeServer.close(force: true);
    await temporary.delete(recursive: true);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    debugDefaultTargetPlatformOverride = null;
    HttpOverrides.global = previousHttpOverrides;
  });

  test(
    'restoring a native share starts a reachable tools page and advertises it',
    () async {
      await service.restoreFromService();
      expect(service.isRunning, isTrue);
      expect(service.clipboardUrl, isNotNull);
      expect(addressUpdates.single['clipboardAddress'], service.clipboardUrl);
      final client = HttpClient();
      try {
        final request = await client.getUrl(
          Uri.parse('${service.clipboardUrl}/api/clipboard'),
        );
        final response = await request.close();
        expect(response.statusCode, HttpStatus.ok);
        expect(
          jsonDecode(await utf8.decoder.bind(response).join())['text'],
          '',
        );
      } finally {
        client.close(force: true);
      }
    },
  );

  test(
    'native Stop closes the tools listener and connected clients without resume',
    () async {
      await service.restoreFromService();
      final url = service.clipboardUrl;
      expect(url, isNotNull);
      final websocket = await WebSocket.connect(
        url!.replaceFirst('http:', 'ws:'),
      );
      final closed = Completer<void>();
      websocket.listen((_) {}, onDone: () => closed.complete());
      nativeInfo['isRunning'] = false;
      await nativeStopped(1);
      expect(service.isRunning, isFalse);
      expect(service.clipboardUrl, isNull);
      await closed.future.timeout(const Duration(seconds: 2));
      await expectToolsClosed(url);
    },
  );

  test('a delayed stop callback cannot close a newer native run', () async {
    await service.restoreFromService();
    nativeInfo['generation'] = 2;
    await service.restoreFromService();
    final url = service.clipboardUrl;
    expect(url, isNotNull);
    await nativeStopped(1);
    expect(service.isRunning, isTrue);
    expect(service.clipboardUrl, url);
    await nativeStopped(2);
    expect(service.isRunning, isFalse);
    await expectToolsClosed(url!);
  });

  test(
    'dispose releases the tools listener even when native sharing continues',
    () async {
      await service.restoreFromService();
      final url = service.clipboardUrl;
      expect(url, isNotNull);
      service.dispose();
      // Replace the disposed instance so tearDown remains an ordinary owner cleanup.
      service = DufsService();
      await Future<void>.delayed(Duration.zero);
      await expectToolsClosed(url!);
    },
  );

  test(
    'resume reconciliation clears a stopped native share without sending another stop',
    () async {
      await service.restoreFromService();
      final url = service.clipboardUrl;
      expect(url, isNotNull);
      nativeInfo['isRunning'] = false;
      await service.restoreFromService();
      expect(service.isRunning, isFalse);
      await expectToolsClosed(url!);
    },
  );

  test(
    'a stop received while querying native state cannot restore a stale snapshot',
    () async {
      final snapshot = Map<String, Object>.of(nativeInfo);
      final queryStarted = Completer<void>();
      final reply = Completer<Map<String, Object>>();
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'getServiceInfo') {
          queryStarted.complete();
          return reply.future;
        }
        if (call.method == 'log') return null;
        if (call.method == 'updateNotificationAddress') return true;
        throw MissingPluginException(call.method);
      });
      final restoring = service.restoreFromService();
      await queryStarted.future;
      await nativeStopped(1);
      reply.complete(snapshot);
      await restoring;
      expect(service.isRunning, isFalse);
      expect(service.clipboardUrl, isNull);
    },
  );

  test(
    'a delayed stopped snapshot cannot clear a newer restored share',
    () async {
      await service.restoreFromService();
      final stoppedSnapshot = Map<String, Object>.of(nativeInfo)
        ..['isRunning'] = false;
      final queryStarted = Completer<void>();
      final staleReply = Completer<Map<String, Object>>();
      var queried = false;
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'getServiceInfo') {
          if (!queried) {
            queried = true;
            queryStarted.complete();
            return staleReply.future;
          }
          return Map<String, Object>.of(nativeInfo);
        }
        if (call.method == 'log') return null;
        if (call.method == 'updateNotificationAddress' ||
            call.method == 'stopForegroundService') {
          return true;
        }
        throw MissingPluginException(call.method);
      });
      final staleRestore = service.restoreFromService();
      await queryStarted.future;
      nativeInfo['generation'] = 2;
      await service.restoreFromService();
      final newUrl = service.clipboardUrl;
      staleReply.complete(stoppedSnapshot);
      await staleRestore;
      expect(service.isRunning, isTrue);
      expect(service.clipboardUrl, newUrl);
    },
  );

  test(
    'resume during an explicit stop cannot restart the tools listener',
    () async {
      await service.restoreFromService();
      final stopRequested = Completer<void>();
      final stopReply = Completer<bool>();
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'getServiceInfo') {
          return Map<String, Object>.of(nativeInfo);
        }
        if (call.method == 'stopForegroundService') {
          stopRequested.complete();
          return stopReply.future;
        }
        if (call.method == 'log') return null;
        if (call.method == 'updateNotificationAddress') return true;
        throw MissingPluginException(call.method);
      });
      final stopping = service.stopServer();
      await stopRequested.future;
      await service.restoreFromService();
      final runningDuringStop = service.isRunning;
      final toolsDuringStop = service.clipboardUrl;
      stopReply.complete(true);
      await stopping;
      expect(runningDuringStop, isFalse);
      expect(toolsDuringStop, isNull);
    },
  );

  test(
    'a restore paused in log preparation cannot overwrite a newer running share',
    () async {
      final firstPrepare = Completer<void>();
      final firstPathReply = Completer<String>();
      var prepares = 0;
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (_) async {
          if (prepares++ == 0) {
            firstPrepare.complete();
            return firstPathReply.future;
          }
          return temporary.path;
        },
      );
      final newerServer = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      newerServer.listen((request) => request.response.close());
      try {
        final oldRestore = service.restoreFromService();
        await firstPrepare.future;
        nativeInfo['generation'] = 2;
        nativeInfo['port'] = newerServer.port;
        nativeInfo['address'] = 'http://127.0.0.1:${newerServer.port}';
        await service.restoreFromService();
        final newTools = service.clipboardUrl;
        firstPathReply.complete(temporary.path);
        await oldRestore;
        expect(service.activePort, newerServer.port);
        expect(Uri.parse(service.serverUrl!).port, newerServer.port);
        expect(service.clipboardUrl, newTools);
        expect(addressUpdates.last['generation'], 2);
        expect(
          Uri.parse(addressUpdates.last['address'] as String).port,
          newerServer.port,
        );
      } finally {
        if (!firstPathReply.isCompleted) {
          firstPathReply.complete(temporary.path);
        }
        await newerServer.close(force: true);
      }
    },
  );

  test(
    'restoring the same native run preserves ingested log history',
    () async {
      Future<void> waitForRequestCount(int count) async {
        if (service.totalRequests == count) return;
        final observed = Completer<void>();
        void checkCount() {
          if (service.totalRequests == count && !observed.isCompleted) {
            observed.complete();
          }
        }

        service.addListener(checkCount);
        try {
          await observed.future.timeout(const Duration(seconds: 4));
        } finally {
          service.removeListener(checkCount);
        }
      }

      await service.restoreFromService();
      final logFile = File('${temporary.path}/fileinfra_dufs.log');
      await logFile.writeAsString(
        '2026-11-09T04:00:00+08:00 INFO - 127.0.0.1 "GET /first.txt" 200\n',
        mode: FileMode.append,
      );
      await waitForRequestCount(1);
      expect(service.transferLogs.single.path, '/first.txt');
      final lastActivity = service.lastActivity;
      expect(lastActivity, isNotNull);

      await service.restoreFromService();
      expect(service.totalRequests, 1);
      expect(service.transferLogs.single.path, '/first.txt');
      expect(service.lastActivity, lastActivity);
      expect(service.timeSinceLastActivity, isNotNull);

      await logFile.writeAsString(
        '2026-11-09T04:00:01+08:00 INFO - 127.0.0.1 "GET /second.txt" 200\n',
        mode: FileMode.append,
      );
      await waitForRequestCount(2);
      expect(service.transferLogs.map((entry) => entry.path), [
        '/second.txt',
        '/first.txt',
      ]);

      nativeInfo['generation'] = 2;
      await service.restoreFromService();
      expect(service.totalRequests, 0);
      expect(service.transferLogs, isEmpty);
      expect(service.lastActivity, isNull);
      expect(service.timeSinceLastActivity, isNull);
    },
  );

  test(
    'an in-flight log read cannot restore statistics after native stop',
    () async {
      final logPath = '${temporary.path}/fileinfra_dufs.log';
      final realFile = File(logPath);
      final pending = _PendingLogFile(realFile);
      await IOOverrides.runZoned(
        () async {
          await service.restoreFromService();
          await realFile.writeAsString(
            '2026-11-09T04:00:00+08:00 INFO - 127.0.0.1 "GET /old.txt" 200\n',
          );
          await pending.started.future.timeout(const Duration(seconds: 4));
          nativeInfo['isRunning'] = false;
          await nativeStopped(1);
          pending.reply.complete(true);
          await pending.reply.future;
          await Future<void>.delayed(Duration.zero);
          if (pending.openCount != 0) await pending.closed.future;
          expect(service.isRunning, isFalse);
          expect(service.totalRequests, 0);
          expect(service.transferLogs, isEmpty);
          expect(service.lastActivity, isNull);
          expect(
            pending.openCount,
            0,
            reason: 'a stale read must stop before opening the old file',
          );
        },
        createFile: (path) => path == logPath
            ? pending
            : IOOverrides.runWithIOOverrides(() => File(path), _RealIO()),
      );
    },
  );

  test(
    'periodic log polls do not overlap while a file read is pending',
    () async {
      final logPath = '${temporary.path}/fileinfra_dufs.log';
      final pending = _PendingLogFile(File(logPath));
      await IOOverrides.runZoned(
        () async {
          await service.restoreFromService();
          await pending.started.future.timeout(const Duration(seconds: 4));
          await Future<void>.delayed(const Duration(milliseconds: 2200));
          final existsCalls = pending.existsCalls;
          await service.stopServer();
          pending.reply.complete(false);
          expect(existsCalls, 1);
        },
        createFile: (path) => path == logPath
            ? pending
            : IOOverrides.runWithIOOverrides(() => File(path), _RealIO()),
      );
    },
  );

  test('old logfile bytes cannot enter a newer restored native run', () async {
    final logPath = '${temporary.path}/fileinfra_dufs.log';
    final realFile = File(logPath);
    final pending = _PendingLogFile(realFile, holdRead: true);
    await IOOverrides.runZoned(
      () async {
        await service.restoreFromService();
        await realFile.writeAsString(
          '2026-11-09T04:00:00+08:00 INFO - 127.0.0.1 "GET /old.txt" 200\n',
        );
        await pending.started.future.timeout(const Duration(seconds: 4));
        pending.reply.complete(true);
        await pending.readStarted.future;
        nativeInfo['generation'] = 2;
        await service.restoreFromService();
        expect(service.isRunning, isTrue);
        expect(service.totalRequests, 0);
        pending.releaseRead.complete();
        await pending.closed.future;
        expect(service.totalRequests, 0);
        expect(service.transferLogs, isEmpty);
        expect(service.lastActivity, isNull);
      },
      createFile: (path) => path == logPath
          ? pending
          : IOOverrides.runWithIOOverrides(() => File(path), _RealIO()),
    );
  });

  test(
    'a delayed logfile preparation cannot erase bytes from a newer restore',
    () async {
      final logPath = '${temporary.path}/fileinfra_dufs.log';
      final realFile = File(logPath);
      final delayed = _DelayedLogPreparation(realFile);
      const newLine =
          '2026-11-09T04:00:00+08:00 INFO - 127.0.0.1 "GET /new.txt" 200\n';
      await IOOverrides.runZoned(
        () async {
          final oldRestore = service.restoreFromService();
          await delayed.started.future;
          nativeInfo['generation'] = 2;
          await service.restoreFromService();
          await realFile.writeAsString(newLine);
          delayed.resume.complete();
          await oldRestore;
          expect(service.isRunning, isTrue);
          expect(addressUpdates.last['generation'], 2);
          expect(await realFile.readAsString(), newLine);
        },
        createFile: (path) => path == logPath
            ? delayed
            : IOOverrides.runWithIOOverrides(() => File(path), _RealIO()),
      );
    },
  );
}

final class _RealIO extends IOOverrides {}

class _PendingLogFile implements File {
  final File real;
  final started = Completer<void>();
  final reply = Completer<bool>();
  final closed = Completer<void>();
  final readStarted = Completer<void>();
  final releaseRead = Completer<void>();
  final bool holdRead;
  int existsCalls = 0;
  int openCount = 0;
  _PendingLogFile(this.real, {this.holdRead = false});

  @override
  String get path => real.path;

  @override
  Future<bool> exists() {
    existsCalls++;
    if (!started.isCompleted) started.complete();
    return reply.future;
  }

  @override
  Future<File> writeAsString(
    String contents, {
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) => real.writeAsString(
    contents,
    mode: mode,
    encoding: encoding,
    flush: flush,
  );

  @override
  Future<RandomAccessFile> open({FileMode mode = FileMode.read}) async {
    if (mode == FileMode.writeOnlyAppend) return real.open(mode: mode);
    openCount++;
    return _LogReadHandle(await real.open(mode: mode), this);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unexpected logfile operation: ${invocation.memberName}',
  );
}

class _LogReadHandle implements RandomAccessFile {
  final RandomAccessFile real;
  final _PendingLogFile pending;
  _LogReadHandle(this.real, this.pending);
  @override
  Future<int> length() => real.length();
  @override
  Future<RandomAccessFile> setPosition(int position) =>
      real.setPosition(position);
  @override
  Future<Uint8List> read(int count) async {
    final bytes = await real.read(count);
    if (pending.holdRead) {
      if (!pending.readStarted.isCompleted) pending.readStarted.complete();
      await pending.releaseRead.future;
    }
    return bytes;
  }

  @override
  Future<void> close() async {
    await real.close();
    if (!pending.closed.isCompleted) pending.closed.complete();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unexpected log read operation: ${invocation.memberName}',
  );
}

class _DelayedLogPreparation implements File {
  final File real;
  final started = Completer<void>();
  final resume = Completer<void>();
  int prepareCalls = 0;
  _DelayedLogPreparation(this.real);
  @override
  String get path => real.path;
  Future<void> holdFirst() async {
    if (++prepareCalls == 1) {
      started.complete();
      await resume.future;
    }
  }

  @override
  Future<File> writeAsString(
    String contents, {
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) async {
    await holdFirst();
    return real.writeAsString(
      contents,
      mode: mode,
      encoding: encoding,
      flush: flush,
    );
  }

  @override
  Future<RandomAccessFile> open({FileMode mode = FileMode.read}) async {
    if (mode == FileMode.writeOnlyAppend) await holdFirst();
    return real.open(mode: mode);
  }

  @override
  Future<bool> exists() => real.exists();
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unexpected log preparation operation: ${invocation.memberName}',
  );
}
