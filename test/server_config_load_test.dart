import 'dart:convert';

import 'package:file_infra/models/server_config.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final credentials = <String, String>{};
  var failRead = false;
  var failWrite = false;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    credentials.clear();
    failRead = false;
    failWrite = false;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      final args = call.arguments as Map;
      final key = args['key'] as String;
      switch (call.method) {
        case 'read':
          if (failRead) throw PlatformException(code: 'keyring_unavailable');
          return credentials[key];
        case 'write':
          if (failWrite) throw PlatformException(code: 'keyring_unavailable');
          credentials[key] = args['value'] as String;
          return null;
        default:
          throw StateError('Unexpected secure-storage method ${call.method}');
      }
    });
  });

  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  test(
    'wrong field type defaults that field and preserves valid settings',
    () async {
      SharedPreferences.setMockInitialValues({
        'server_config': '{"port":"5000","path":"/share","setupDone":true}',
      });
      final config = await ServerConfig.load();
      expect(config.port, 5000);
      expect(config.path, '/share');
      expect(config.setupDone, isTrue);
    },
  );

  test('all persisted fields tolerate mismatched JSON types', () async {
    final cases = <String, (Object, Object?)>{
      'path': (42, ''),
      'port': (true, 5000),
      'allowUpload': ('true', false),
      'allowDelete': (1, false),
      'allowSearch': ([], false),
      'allowArchive': ({}, false),
      'allowSymlink': ('yes', false),
      'readonly': ('false', true),
      'cors': (1, false),
      'language': (false, 'zh'),
      'themeMode': (1, 'system'),
      'colorScheme': ([], 'coral'),
      'setupDone': ('true', false),
      'closeAction': (false, 'ask'),
      'shareSingleFile': (1, false),
      'hideSystemFiles': ('false', true),
      'renderTryIndex': (1, false),
      'preferredAddress': (123, null),
      'customColor': ('red', 0xFFFF6B5A),
      'notifClipboard': ('false', true),
    };
    for (final entry in cases.entries) {
      SharedPreferences.setMockInitialValues({
        'server_config': jsonEncode({entry.key: entry.value.$1}),
      });
      final config = await ServerConfig.load();
      expect(config.toJson()[entry.key], entry.value.$2, reason: entry.key);
    }
  });

  test(
    'invalid port ranges default while valid boundary ports survive',
    () async {
      for (final (port, expected) in [
        (-1, 5000),
        (0, 5000),
        (65536, 5000),
        (1, 1),
        (65535, 65535),
      ]) {
        SharedPreferences.setMockInitialValues({
          'server_config': jsonEncode({'port': port}),
        });
        final config = await ServerConfig.load();
        expect(config.port, expected);
      }
    },
  );

  test('corrupt preference types and JSON retain secure credentials', () async {
    credentials['server_auth'] = 'secure:password';
    for (final stored in [
      42,
      true,
      ['unexpected'],
      '{broken',
      '[]',
      'null',
    ]) {
      SharedPreferences.setMockInitialValues({'server_config': stored});
      final config = await ServerConfig.load();
      expect(config.port, 5000);
      expect(config.setupDone, isFalse);
      expect(config.auth, 'secure:password');
    }
  });

  test(
    'non-string legacy auth is ignored without discarding valid settings',
    () async {
      SharedPreferences.setMockInitialValues({
        'server_config': '{"auth":42,"port":6000,"setupDone":true}',
      });
      final config = await ServerConfig.load();
      expect(config.auth, isNull);
      expect(config.port, 6000);
      expect(config.setupDone, isTrue);
    },
  );

  test('secure auth takes priority over stale legacy auth', () async {
    credentials['server_auth'] = 'current:password';
    SharedPreferences.setMockInitialValues({
      'server_config': '{"auth":"stale:password","port":6000}',
    });
    final config = await ServerConfig.load();
    expect(config.auth, 'current:password');
    expect(
      await const FlutterSecureStorage().read(key: 'server_auth'),
      'current:password',
    );
  });

  test(
    'legacy auth migrates despite malformed noncredential settings',
    () async {
      SharedPreferences.setMockInitialValues({
        'server_config':
            '{"auth":"legacy:password","port":"bad","setupDone":true}',
      });
      final config = await ServerConfig.load();
      expect(config.auth, 'legacy:password');
      expect(config.setupDone, isTrue);
      expect(
        await const FlutterSecureStorage().read(key: 'server_auth'),
        'legacy:password',
      );
      final prefs = await SharedPreferences.getInstance();
      final saved = jsonDecode(prefs.getString('server_config')!) as Map;
      expect(saved.containsKey('auth'), isFalse);
      expect(saved['setupDone'], isTrue);
    },
  );

  test(
    'unavailable keyring retains legacy auth for this load and retry',
    () async {
      failRead = true;
      failWrite = true;
      const saved = '{"auth":"legacy:password","port":6000}';
      SharedPreferences.setMockInitialValues({'server_config': saved});
      final config = await ServerConfig.load();
      expect(config.auth, 'legacy:password');
      expect(config.port, 6000);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('server_config'), saved);
    },
  );

  test(
    'unavailable keyring without legacy auth loads settings safely',
    () async {
      failRead = true;
      SharedPreferences.setMockInitialValues({
        'server_config': '{"port":6000}',
      });
      final config = await ServerConfig.load();
      expect(config.auth, isNull);
      expect(config.port, 6000);
    },
  );
}
