import 'dart:io';

import 'package:file_infra/pages/log_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late Directory outside;

  setUp(() {
    root = Directory.systemTemp.createTempSync('fi_resolve_root');
    outside = Directory.systemTemp.createTempSync('fi_resolve_out');
    File('${root.path}/a.txt').writeAsStringSync('a');
    File('${root.path}/pic 1.png').writeAsStringSync('p');
    File('${outside.path}/secret.txt').writeAsStringSync('s');
  });

  tearDown(() {
    root.deleteSync(recursive: true);
    outside.deleteSync(recursive: true);
  });

  group('LogPage.resolveTarget 正常解析', () {
    test('根下普通文件', () {
      final t = LogPage.resolveTarget('/a.txt', root.path);
      expect(t, isNotNull);
      expect(File(t!).readAsStringSync(), 'a');
    });

    test('去 query 后命中', () {
      final t = LogPage.resolveTarget('/a.txt?download=true', root.path);
      expect(t, isNotNull);
    });

    test('URL 解码命中（空格）', () {
      final t = LogPage.resolveTarget('/pic%201.png', root.path);
      expect(t, isNotNull);
    });

    test('相对形式（无前导斜杠）', () {
      final t = LogPage.resolveTarget('a.txt', root.path);
      expect(t, isNotNull);
    });

    test('不存在的文件返回 null', () {
      expect(LogPage.resolveTarget('/nope.txt', root.path), isNull);
    });

    test('空 root 返回 null', () {
      expect(LogPage.resolveTarget('/a.txt', ''), isNull);
    });

    test('missing root returns null', () {
      expect(LogPage.resolveTarget('/a.txt', '${root.path}/missing'), isNull);
    });

    test('单文件分享：所有请求返回所选文件的真实路径', () {
      final single = '${root.path}/a.txt';
      expect(
        LogPage.resolveTarget('/anything', single),
        File(single).resolveSymbolicLinksSync(),
      );
    });
  });

  group('LogPage.resolveTarget filesystem links', () {
    test('outside directory link cannot expose a file', () {
      Link('${root.path}/link').createSync(outside.path);
      expect(LogPage.resolveTarget('/link/secret.txt', root.path), isNull);
    });

    test('outside file link cannot expose a file', () {
      Link('${root.path}/secret.txt').createSync('${outside.path}/secret.txt');
      expect(LogPage.resolveTarget('/secret.txt', root.path), isNull);
    });

    test('inside link resolves to an existing canonical target', () {
      Link('${root.path}/linked.txt').createSync('${root.path}/a.txt');
      final target = LogPage.resolveTarget('/linked.txt', root.path);
      expect(target, File('${root.path}/a.txt').resolveSymbolicLinksSync());
      expect(File(target!).readAsStringSync(), 'a');
    });

    test('symlinked selected root uses the real root for containment', () {
      final selectedRoot = Link('${outside.path}/selected');
      selectedRoot.createSync(root.path);
      expect(
        LogPage.resolveTarget('/a.txt', selectedRoot.path),
        File('${root.path}/a.txt').resolveSymbolicLinksSync(),
      );
      Link('${root.path}/escape').createSync(outside.path);
      expect(
        LogPage.resolveTarget('/escape/secret.txt', selectedRoot.path),
        isNull,
      );
    });

    test('dangling links and missing link descendants return null', () {
      Link('${root.path}/dangling').createSync('${outside.path}/missing');
      Link('${root.path}/inside').createSync(root.path);
      expect(LogPage.resolveTarget('/dangling', root.path), isNull);
      expect(LogPage.resolveTarget('/inside/missing', root.path), isNull);
    });

    test('selected single-file link resolves to the selected file', () {
      final selected = Link('${root.path}/single.txt');
      selected.createSync('${outside.path}/secret.txt');
      expect(
        LogPage.resolveTarget('/anything', selected.path),
        File('${outside.path}/secret.txt').resolveSymbolicLinksSync(),
      );
    });
  });

  group('LogPage.resolveTarget 防逃逸', () {
    test('裸 ../ 逃逸被拒', () {
      expect(LogPage.resolveTarget('/../x', root.path), isNull);
      expect(
        LogPage.resolveTarget(
          '/../${p.basename(outside.path)}/secret.txt',
          Directory.systemTemp.path,
        ),
        isNull,
      );
    });

    test('多层嵌套 ../ 逃逸被拒', () {
      expect(LogPage.resolveTarget('/a/../../b/c.txt', root.path), isNull);
    });

    test('percent 编码的 ../ 被拒（解码发生在候选生成后）', () {
      expect(LogPage.resolveTarget('/%2e%2e/x', root.path), isNull);
      expect(LogPage.resolveTarget('/%2E%2E%2Fx', root.path), isNull);
    });

    test(
      'encoded traversal is rejected even if its literal filename exists',
      () {
        Directory('${root.path}/%2e%2e').createSync();
        File('${root.path}/%2e%2e/a.txt').writeAsStringSync('literal');
        expect(LogPage.resolveTarget('/%2e%2e/a.txt', root.path), isNull);
      },
    );

    test(
      'links do not permit dot segments, encoded or backslash traversal',
      () {
        Link('${root.path}/inside').createSync(root.path);
        for (final request in [
          '/inside/../a.txt',
          '/inside/%2e%2e/a.txt',
          r'/inside/..\a.txt',
          '/inside/%2e%2e%5ca.txt',
        ]) {
          expect(
            LogPage.resolveTarget(request, root.path),
            isNull,
            reason: request,
          );
        }
      },
    );

    test('反斜杠形式的 .. 被拒', () {
      expect(LogPage.resolveTarget(r'/..\x', root.path), isNull);
    });

    test('路径中段含 .. 文件名不误伤（..x 是合法名）', () {
      File('${root.path}/..tricky.txt').writeAsStringSync('ok');
      final t = LogPage.resolveTarget('/..tricky.txt', root.path);
      expect(t, isNotNull);
    });
  });
}
