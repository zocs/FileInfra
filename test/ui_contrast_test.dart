import 'package:file_infra/app.dart' show presetColors;
import 'package:file_infra/l10n/app_localizations.dart';
import 'package:file_infra/models/server_config.dart';
import 'package:file_infra/pages/home_page.dart';
import 'package:file_infra/pages/settings_page.dart';
import 'package:file_infra/pages/setup_wizard_page.dart';
import 'package:file_infra/services/dufs_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _RunningService extends DufsService {
  @override
  bool get isRunning => true;
  @override
  String? get serverUrl => 'http://192.168.100.200:5000';
  @override
  String? get clipboardUrl => 'http://192.168.100.200:7000';
}

// Check actual widget foregrounds against their composited surfaces. The
// pixel guideline's modal-color heuristic can select antialiasing pixels
// instead of the text color, especially for small text or absent CJK glyphs.
double _contrast(Color foreground, Color background) {
  final a = Color.alphaBlend(foreground, background).computeLuminance();
  final b = background.computeLuminance();
  return ((a > b ? a : b) + 0.05) / ((a > b ? b : a) + 0.05);
}

void _expectContrast(String text, Color background) {
  final element = find.text(text).evaluate().first;
  final widget = element.widget as Text;
  final style = widget.style?.inherit == false
      ? widget.style!
      : DefaultTextStyle.of(element).style.merge(widget.style);
  expect(
    _contrast(style.color!, background),
    greaterThanOrEqualTo(4.5),
    reason: '$text: ${style.color} on $background',
  );
}

void main() {
  for (final seed in presetColors.entries) {
    for (final brightness in Brightness.values) {
      testWidgets('readable text ${seed.key} $brightness', (tester) async {
        tester.view.physicalSize = const Size(800, 2400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final scheme = ColorScheme.fromSeed(
          seedColor: seed.value,
          brightness: brightness,
        );
        final theme = ThemeData(useMaterial3: true, colorScheme: scheme);
        final cfg = ServerConfig.defaultConfig()..language = 'en';
        final l10n = AppLocalizations('en');
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
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
        final aboutBackground = Color.alphaBlend(
          scheme.primaryContainer.withValues(alpha: 0.4),
          scheme.surface,
        );
        _expectContrast('v0.0.0', aboutBackground);
        _expectContrast('github.com/zocs/fileinfra', aboutBackground);
        final helpBackground = Color.alphaBlend(
          scheme.surfaceContainerHighest.withValues(alpha: 0.5),
          scheme.surface,
        );
        _expectContrast(
          l10n.t('help.tip2'),
          Color.alphaBlend(
            Colors.pinkAccent.withValues(alpha: 0.08),
            helpBackground,
          ),
        );

        final service = _RunningService();
        await tester.pumpWidget(
          ChangeNotifierProvider<DufsService>.value(
            value: service,
            child: MaterialApp(
              theme: theme,
              home: HomePage(
                config: cfg,
                themeMode: ThemeMode.system,
                onThemeModeChanged: (_) {},
                onColorChanged: (_) {},
                onLanguageChanged: (_) {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        _expectContrast(service.serverUrl!, scheme.primaryContainer);
        _expectContrast(service.clipboardUrl!, scheme.primaryContainer);
        _expectContrast(l10n.t('home.scanHint'), scheme.primaryContainer);
        _expectContrast(l10n.t('app.slogan'), scheme.surface);
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: SetupWizardPage(
              config: cfg,
              onThemeModeChanged: (_) {},
              onColorChanged: (_) {},
              onSetupDone: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        _expectContrast('轻点一下，文件分享即刻在线。', scheme.surface);
        await tester.pumpWidget(const SizedBox.shrink());
        service.dispose();
      });
    }
  }
}
