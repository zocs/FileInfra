import 'package:flutter/material.dart';
import '../models/server_config.dart';
import '../l10n/app_localizations.dart';
import '../app.dart' show presetColors;

class SetupWizardPage extends StatefulWidget {
  final ServerConfig config;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final ValueChanged<String> onColorChanged;
  final VoidCallback onSetupDone;

  const SetupWizardPage({
    super.key,
    required this.config,
    required this.onThemeModeChanged,
    required this.onColorChanged,
    required this.onSetupDone,
  });

  @override
  State<SetupWizardPage> createState() => _SetupWizardPageState();
}

class _SetupWizardPageState extends State<SetupWizardPage> {
  String _selectedLang = 'zh';
  String _selectedColor = 'coral';
  ThemeMode _selectedTheme = ThemeMode.system;

  final _languages = [
    {'code': 'zh', 'name': '简体中文'},
    {'code': 'zhTW', 'name': '繁體中文'},
    {'code': 'en', 'name': 'English'},
  ];

  String get _lang => _selectedLang;

  String _label(String zh, String zhTW, String en) {
    switch (_lang) {
      case 'zhTW':
        return zhTW;
      case 'en':
        return en;
      default:
        return zh;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: MediaQuery.of(context).size.height -
                  MediaQuery.of(context).padding.top -
                  MediaQuery.of(context).padding.bottom,
            ),
            child: IntrinsicHeight(
              child: Column(
                children: [
                const SizedBox(height: 40),

                  Icon(
                    Icons.swap_horiz,
                    size: 64,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'FileInfra',
                    style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  Text(
                    _label(
                      '轻点一下，文件分享即刻在线。',
                      '輕點一下，檔案分享即刻在線。',
                      'One tap, and your files are online.',
                    ),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Language
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _label('语言', '語言', 'Language'),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: _languages.map((lang) {
                      final isSelected = _selectedLang == lang['code'];
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: ChoiceChip(
                            label: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                lang['name']!,
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                            labelPadding: const EdgeInsets.symmetric(
                              horizontal: 8,
                            ),
                            selected: isSelected,
                            onSelected: (_) =>
                                setState(() => _selectedLang = lang['code']!),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),

                  // Theme
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _label('主题', '主題', 'Theme'),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _buildThemeOption(
                        ThemeMode.system,
                        Icons.brightness_auto,
                        _label('跟随系统', '跟隨系統', 'System'),
                      ),
                      const SizedBox(width: 8),
                      _buildThemeOption(
                        ThemeMode.light,
                        Icons.light_mode,
                        _label('浅色', '淺色', 'Light'),
                      ),
                      const SizedBox(width: 8),
                      _buildThemeOption(
                        ThemeMode.dark,
                        Icons.dark_mode,
                        _label('深色', '深色', 'Dark'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Color
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _label('配色', '配色', 'Color'),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: presetColors.entries.map((entry) {
                      final isSelected = _selectedColor == entry.key;
                      return Semantics(
                        selected: isSelected,
                        child: SizedBox(
                          width: 48,
                          height: 48,
                          child: IconButton(
                            tooltip: AppLocalizations(
                              _lang,
                            ).t('settings.color.${entry.key}'),
                            padding: EdgeInsets.zero,
                            onPressed: () {
                              setState(() => _selectedColor = entry.key);
                              widget.onColorChanged(entry.key);
                            },
                            icon: Ink(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: entry.value,
                                shape: BoxShape.circle,
                                border: isSelected
                                    ? Border.all(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurface,
                                        width: 3,
                                      )
                                    : null,
                              ),
                              child: isSelected
                                  ? const Icon(Icons.check, color: Colors.white)
                                  : null,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const Spacer(),

                  // Start
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton(
                      onPressed: _onStart,
                      child: Text(
                        _label('开始使用', '開始使用', 'Get Started'),
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildThemeOption(ThemeMode mode, IconData icon, String label) {
    final isSelected = _selectedTheme == mode;
    return Expanded(
      child: Semantics(
        selected: isSelected,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            setState(() => _selectedTheme = mode);
            widget.onThemeModeChanged(mode);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(
                        context,
                      ).colorScheme.outline.withValues(alpha: 0.3),
                width: isSelected ? 2 : 1,
              ),
              color: isSelected
                  ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)
                  : null,
            ),
            child: Column(
              children: [
                Icon(
                  icon,
                  color: isSelected
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _onStart() async {
    widget.config.language = _selectedLang;
    widget.config.colorScheme = _selectedColor;
    widget.config.themeMode = _selectedTheme.name;
    widget.config.setupDone = true;
    await widget.config.save();
    widget.onSetupDone();
  }
}
