import 'package:file_infra/main.dart';
import 'package:file_infra/models/server_config.dart';
import 'package:file_infra/pages/home_page.dart';
import 'package:file_infra/pages/setup_wizard_page.dart';
import 'package:file_infra/services/dufs_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The real app handles unavailable desktop tray assets. Keep OS tray setup out
// of these widget tests while retaining the real setup, persistence and app.
class _NoTrayAssets extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) {
    if (key == 'assets/icon/tray_icon.ico' ||
        key == 'assets/icon/app_icon.png') {
      return Future.error(
        StateError('Desktop tray unavailable in widget test'),
      );
    }
    return rootBundle.load(key);
  }
}

Future<void> _pumpApp(WidgetTester tester, ServerConfig config) async {
  await tester.pumpWidget(
    DefaultAssetBundle(
      bundle: _NoTrayAssets(),
      child: ChangeNotifierProvider(
        create: (_) => DufsService(),
        child: FileInfraApp(config: config),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(find.byType(SetupWizardPage), findsOneWidget);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets('completing setup applies the chosen locale to MaterialApp', (
    tester,
  ) async {
    final config = ServerConfig();
    await _pumpApp(tester, config);
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Teal'));
    await tester.pumpAndSettle();
    final start = find.text('Get Started');
    await tester.ensureVisible(start);
    await tester.tap(start);
    await tester.pumpAndSettle();

    expect(find.byType(SetupWizardPage), findsNothing);
    expect(find.byType(HomePage), findsOneWidget);
    expect(config.language, 'en');
    expect(config.themeMode, 'dark');
    expect(config.colorScheme, 'teal');
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.locale, const Locale('en'));
    expect(app.themeMode, ThemeMode.dark);
    final theme = Theme.of(tester.element(find.byType(HomePage)));
    expect(theme.brightness, Brightness.dark);
    expect(
      theme.colorScheme.primary,
      ColorScheme.fromSeed(
        seedColor: const Color(0xFF00BFA6),
        brightness: Brightness.dark,
      ).primary,
    );
  });

  testWidgets(
    'setup completion resyncs saved appearance after accepting defaults',
    (tester) async {
      final config = ServerConfig(
        language: 'en',
        themeMode: 'dark',
        colorScheme: 'teal',
      );
      await _pumpApp(tester, config);
      final start = find.text('开始使用');
      await tester.ensureVisible(start);
      await tester.tap(start);
      await tester.pumpAndSettle();

      expect(find.byType(HomePage), findsOneWidget);
      expect(config.language, 'zh');
      expect(config.themeMode, 'system');
      expect(config.colorScheme, 'coral');
      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.locale, const Locale('zh'));
      expect(app.themeMode, ThemeMode.system);
      expect(
        app.theme!.colorScheme.primary,
        ColorScheme.fromSeed(seedColor: const Color(0xFFFF6B5A)).primary,
      );
    },
  );
}
