// Layout regressions: real screens, translations, large text and QR sheets.
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:file_infra/models/server_config.dart';
import 'package:file_infra/pages/home_page.dart';
import 'package:file_infra/pages/settings_page.dart';
import 'package:file_infra/pages/setup_wizard_page.dart';
import 'package:file_infra/services/dufs_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class FakeRunning extends DufsService {
  @override
  bool get isRunning => true;
  @override
  String? get serverUrl => 'http://192.168.100.200:5000';
  @override
  String? get clipboardUrl => 'http://[fe80::1234:5678:9abc:def0]:7000';
  @override
  String? get preferredAddress => '192.168.100.200';
  @override
  String? get localIp => '192.168.100.200';
  @override
  List<String> get allAddresses => [
    '192.168.100.200',
    'fe80::1234:5678:9abc:def0',
    '10.0.0.5',
  ];
  @override
  List<String> get allInterfaceNames => [
    'WiFi',
    'vEthernet (Default Switch)',
    'rmnet_data0',
  ];
  @override
  int get activePort => 5000;
}

ThemeData _theme(Brightness b) => ThemeData(
  useMaterial3: true,
  fontFamily: 'Roboto',
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xFFFF6B5A),
    brightness: b,
  ),
);

Future<List<String>> _probe(
  WidgetTester tester, {
  required Size size,
  required double scale,
  required Widget Function() home,
  DufsService? service,
  Future<void> Function()? after,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  final errors = <String>[];
  final old = FlutterError.onError;
  FlutterError.onError = (d) {
    final s = d.exceptionAsString().split('\n').first;
    final m = RegExp(r'(\w+\.dart):(\d+)').firstMatch(d.toString());
    errors.add("$s @${m?.group(0)}");
  };
  try {
    await tester.pumpWidget(
      ChangeNotifierProvider<DufsService>.value(
        value: service ?? DufsService(),
        child: MaterialApp(
          theme: _theme(Brightness.light),
          builder: (c, child) => MediaQuery(
            data: MediaQuery.of(
              c,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: home(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    if (after != null) await after();
  } finally {
    FlutterError.onError = old;
  }
  return errors;
}

void main() {
  setUpAll(() async {
    final loader = FontLoader('Roboto');
    for (final f in ['Regular', 'Medium', 'Bold']) {
      loader.addFont(
        File(
          '${File(Platform.resolvedExecutable).parent.parent.parent.path}/material_fonts/Roboto-$f.ttf',
        ).readAsBytes().then(
          (b) => ByteData.view(Uint8List.fromList(b).buffer),
        ),
      );
    }
    await loader.load();
  });
  for (final lang in ['en', 'zh', 'zhTW']) {
    for (final scale in [1.0, 1.3]) {
      testWidgets('settings 360 $lang x$scale', (tester) async {
        final cfg = ServerConfig.defaultConfig()..language = lang;
        final errs = await _probe(
          tester,
          size: const Size(360, 740),
          scale: scale,
          home: () => Scaffold(
            body: SettingsPage(
              config: cfg,
              onConfigChanged: () {},
              themeMode: ThemeMode.system,
              onThemeModeChanged: (_) {},
              onColorChanged: (_) {},
              onLanguageChanged: (_) {},
            ),
          ),
        );
        expect(errs, isEmpty);
        tester.view.reset();
      });

      testWidgets('home idle 360 $lang x$scale', (tester) async {
        final cfg = ServerConfig.defaultConfig()..language = lang;
        final errs = await _probe(
          tester,
          size: const Size(360, 740),
          scale: scale,
          home: () => HomePage(
            config: cfg,
            themeMode: ThemeMode.system,
            onThemeModeChanged: (_) {},
            onColorChanged: (_) {},
            onLanguageChanged: (_) {},
          ),
        );
        expect(errs, isEmpty);
        tester.view.reset();
      });

      testWidgets('home running 360 $lang x$scale', (tester) async {
        final cfg = ServerConfig.defaultConfig()..language = lang;
        final errs = await _probe(
          tester,
          size: const Size(360, 740),
          scale: scale,
          service: FakeRunning(),
          home: () => HomePage(
            config: cfg,
            themeMode: ThemeMode.system,
            onThemeModeChanged: (_) {},
            onColorChanged: (_) {},
            onLanguageChanged: (_) {},
          ),
          after: () async {
            final t = find.byIcon(Icons.lan);
            await tester.ensureVisible(t);
            await tester.tap(t);
            await tester.pumpAndSettle();
          },
        );
        expect(errs, isEmpty);
        tester.view.reset();
      });

      testWidgets('wizard 360x600 $lang x$scale', (tester) async {
        final cfg = ServerConfig.defaultConfig()..language = lang;
        final errs = await _probe(
          tester,
          size: const Size(360, 600),
          scale: scale,
          home: () => SetupWizardPage(
            config: cfg,
            onThemeModeChanged: (_) {},
            onColorChanged: (_) {},
            onSetupDone: () {},
          ),
          after: () async {
            final label = {
              'en': 'English',
              'zh': '简体中文',
              'zhTW': '繁體中文',
            }[lang]!;
            final chip = find.widgetWithText(ChoiceChip, label);
            await tester.ensureVisible(chip);
            await tester.tap(chip);
            await tester.pumpAndSettle();
            expect(
              find.text(
                {
                  'en': 'One tap, and your files are online.',
                  'zh': '轻点一下，文件分享即刻在线。',
                  'zhTW': '輕點一下，檔案分享即刻在線。',
                }[lang]!,
              ),
              findsOneWidget,
            );
          },
        );
        expect(errs, isEmpty);
        tester.view.reset();
      });
    }
  }

  for (final size in [
    const Size(360, 640),
    const Size(960, 600),
    const Size(740, 360),
  ]) {
    testWidgets('real QR sheet $size', (tester) async {
      final cfg = ServerConfig.defaultConfig()..language = 'en';
      final errs = await _probe(
        tester,
        size: size,
        scale: 1.3,
        service: FakeRunning(),
        home: () => HomePage(
          config: cfg,
          themeMode: ThemeMode.system,
          onThemeModeChanged: (_) {},
          onColorChanged: (_) {},
          onLanguageChanged: (_) {},
        ),
        after: () async {
          final button = find.byTooltip('QR Code').first;
          await tester.ensureVisible(button);
          await tester.tap(button);
          await tester.pumpAndSettle();
        },
      );
      expect(errs, isEmpty);
      expect(find.byType(BottomSheet), findsOneWidget);
      tester.view.reset();
    });
  }
}
