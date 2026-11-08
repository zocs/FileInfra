import 'dart:io';

import 'package:file_infra/services/clipboard_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('served tools page supports old browsers and exact clipboard copies',
      () async {
    final service = ClipboardService();
    addTearDown(service.stop);
    // A port of zero avoids depending on the host's ephemeral-port range.
    await service.start(0);
    final result = await Process.run('node', [
      'test/browser/tools_page.cjs',
      'http://127.0.0.1:${service.port}/',
    ]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  },
      timeout: const Timeout(Duration(seconds: 60)),
      skip: !Directory('test/browser/node_modules/puppeteer-core').existsSync()
          ? 'Run npm ci --prefix test/browser and set FILEINFRA_CHROMIUM to a Chromium binary'
          : false);
}
