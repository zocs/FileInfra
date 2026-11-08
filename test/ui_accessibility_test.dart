// Accessibility regressions for touch targets and semantic names.
import 'dart:io';

import 'package:file_infra/models/server_config.dart';
import 'package:file_infra/pages/home_page.dart';
import 'package:file_infra/pages/settings_page.dart';
import 'package:file_infra/pages/setup_wizard_page.dart';
import 'package:file_infra/services/dufs_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class FakeRunning extends DufsService {
  @override
  bool get isRunning => true;
  @override
  String? get serverUrl => 'http://192.168.100.200:5000';
  @override
  String? get clipboardUrl => 'http://192.168.100.200:7000';
  @override
  String? get preferredAddress => '192.168.100.200';
  @override
  String? get localIp => '192.168.100.200';
  @override
  List<String> get allAddresses => ['192.168.100.200', '10.0.0.5'];
  @override
  List<String> get allInterfaceNames => ['WiFi', 'eth0'];
  @override
  int get activePort => 5000;
}

Future<void> _report(WidgetTester tester, String name) async {
  for (final g in <AccessibilityGuideline>[
    androidTapTargetGuideline,
    labeledTapTargetGuideline,
  ]) {
    final r = await g.evaluate(tester);
    expect(r.passed, isTrue, reason: '$name: ${r.reason}');
  }
}

Widget _app(
  Widget home, {
  DufsService? service,
  Brightness b = Brightness.light,
  TargetPlatform platform = TargetPlatform.android,
}) => ChangeNotifierProvider<DufsService>.value(
  value: service ?? DufsService(),
  child: MaterialApp(
    theme: ThemeData(
      useMaterial3: true,
      platform: platform,
      fontFamily: 'Roboto',
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFFFF6B5A),
        brightness: b,
      ),
    ),
    home: home,
  ),
);

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

  final lang = Platform.environment['FI_LANG'] ?? 'en';

  testWidgets('a11y settings', (tester) async {
    final h = tester.ensureSemantics();
    tester.view.physicalSize = const Size(360, 1400);
    tester.view.devicePixelRatio = 1.0;
    final cfg = ServerConfig.defaultConfig()..language = lang;
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: SettingsPage(
            config: cfg,
            onConfigChanged: () {},
            themeMode: ThemeMode.system,
            onThemeModeChanged: (_) {},
            onColorChanged: (_) {},
            onLanguageChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _report(tester, 'settings');
    h.dispose();
    tester.view.reset();
  });

  testWidgets('a11y home running', (tester) async {
    final h = tester.ensureSemantics();
    tester.view.physicalSize = const Size(360, 1800);
    tester.view.devicePixelRatio = 1.0;
    final cfg = ServerConfig.defaultConfig()..language = lang;
    await tester.pumpWidget(
      _app(
        HomePage(
          config: cfg,
          themeMode: ThemeMode.system,
          onThemeModeChanged: (_) {},
          onColorChanged: (_) {},
          onLanguageChanged: (_) {},
        ),
        service: FakeRunning(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byIcon(Icons.lan));
    await tester.pumpAndSettle();
    final adv = find.text(
      cfg.language == 'en'
          ? 'Advanced Options'
          : (cfg.language == 'zh' ? '高级选项' : '進階選項'),
    );
    await tester.tap(adv);
    await tester.pumpAndSettle();
    final auth = find.byType(SwitchListTile).at(0);
    await tester.ensureVisible(auth);
    await _report(tester, 'home-running');
    h.dispose();
    tester.view.reset();
  });

  testWidgets('desktop window buttons have 48dp targets and labels', (
    tester,
  ) async {
    final h = tester.ensureSemantics();
    tester.view.physicalSize = const Size(360, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _app(
        HomePage(
          config: ServerConfig.defaultConfig()..language = 'en',
          themeMode: ThemeMode.system,
          onThemeModeChanged: (_) {},
          onColorChanged: (_) {},
          onLanguageChanged: (_) {},
        ),
        platform: TargetPlatform.linux,
      ),
    );
    await tester.pumpAndSettle();
    await _report(tester, 'desktop-window');
    for (final label in ['Minimize', 'Toggle maximize / restore', 'Close']) {
      expect(tester.getSize(find.byTooltip(label)), const Size(48, 48));
    }
    h.dispose();
  });

  testWidgets('a11y wizard', (tester) async {
    final h = tester.ensureSemantics();
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1.0;
    final cfg = ServerConfig.defaultConfig();
    await tester.pumpWidget(
      _app(
        SetupWizardPage(
          config: cfg,
          onThemeModeChanged: (_) {},
          onColorChanged: (_) {},
          onSetupDone: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _report(tester, 'wizard');
    h.dispose();
    tester.view.reset();
  });
}
