import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../constants.dart';
import '../l10n/app_localizations.dart';
import '../models/server_config.dart';
import '../app.dart' show presetColors, appVersion;
import '../widgets/color_picker_dialog.dart';

class SettingsPage extends StatefulWidget {
  final ServerConfig config;
  final VoidCallback onConfigChanged;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final ValueChanged<String> onColorChanged;
  final ValueChanged<String> onLanguageChanged;

  const SettingsPage({
    super.key,
    required this.config,
    required this.onConfigChanged,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.onColorChanged,
    required this.onLanguageChanged,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  AppLocalizations get l10n => AppLocalizations(widget.config.language);

  static const _ch = MethodChannel(kMethodChannel);
  // Cache permission state across page rebuilds
  bool? _cachedStorageGranted;

  bool get _isCustomColor => widget.config.colorScheme == 'custom';

  final _languages = [
    {'code': 'zh', 'name': '简体中文'},
    {'code': 'zhTW', 'name': '繁體中文'},
    {'code': 'en', 'name': 'English'},
  ];

  @override
  void initState() {
    super.initState();
    // Reset static cache on each app lifecycle start
    _cachedStorageGranted = null;
    _checkStorage();
  }

  /// 打开色盘选择自定义主题色
  Future<void> _showColorPicker() async {
    final picked = await showDialog<Color>(
      context: context,
      builder: (_) => ColorPickerDialog(
        initialColor: Color(widget.config.customColor),
        title: l10n.t('settings.colorPickerTitle'),
        doneLabel: l10n.t('settings.colorPickerDone'),
        cancelLabel: l10n.t('settings.colorPickerCancel'),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      widget.config.colorScheme = 'custom';
      widget.config.customColor = picked.toARGB32();
    });
    widget.config.save();
    widget.onColorChanged('custom');
  }

  Future<void> _checkStorage() async {
    try {
      final granted = await _ch.invokeMethod<bool>('isStorageGranted') ?? false;
      if (!mounted) return;
      setState(() => _cachedStorageGranted = granted);
    } catch (_) {}
  }

  Future<void> _requestStorage() async {
    await _ch.invokeMethod('requestStorage');
    await Future.delayed(const Duration(seconds: 2));
    _checkStorage();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ========== About Header ==========
          Container(
            width: double.infinity,
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.primaryContainer.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.2),
              ),
            ),
            child: Column(
              children: [
                Text(
                  'FILEINFRA',
                  style: TextStyle(
                    fontFamily: 'PressStart2P',
                    fontSize: 24,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'v$appVersion',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.t('about.description'),
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(height: 1.5),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => launchUrl(
                    Uri.parse('https://github.com/zocs/fileinfra'),
                    mode: LaunchMode.externalApplication,
                  ),
                  child: Text(
                    'github.com/zocs/fileinfra',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w500,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  alignment: WrapAlignment.center,
                  children: [
                    TextButton.icon(
                      icon: const Icon(Icons.privacy_tip_outlined, size: 16),
                      label: Text(
                        l10n.t('about.privacy'),
                        style: const TextStyle(fontSize: 12),
                      ),
                      onPressed: () => _showPrivacyPolicy(context),
                    ),
                    const SizedBox(width: 12),
                    TextButton.icon(
                      icon: const Icon(Icons.article_outlined, size: 16),
                      label: Text(
                        l10n.t('about.license'),
                        style: const TextStyle(fontSize: 12),
                      ),
                      onPressed: () => showLicensePage(
                        context: context,
                        applicationName: 'FileInfra',
                        applicationVersion: 'v$appVersion',
                        applicationLegalese:
                            'Copyright (c) 2026 zocs\nMIT License',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // ========== Help ==========
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              l10n.t('settings.help'),
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _helpStep(context, '1', l10n.t('help.step1')),
                  _helpStep(context, '2', l10n.t('help.step2')),
                  _helpStep(context, '3', l10n.t('help.step3')),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.primaryContainer.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 16,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            l10n.t('help.tip'),
                            style: Theme.of(
                              context,
                            ).textTheme.bodySmall?.copyWith(height: 1.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.pinkAccent.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.favorite, size: 16, color: Colors.pink),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            l10n.t('help.tip2'),
                            style: Theme.of(
                              context,
                            ).textTheme.bodySmall?.copyWith(height: 1.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const Divider(height: 24),

          // ========== Storage Permission (Android) ==========
          if (Theme.of(context).platform == TargetPlatform.android) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Text(
                l10n.t('settings.permissions'),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: (_cachedStorageGranted ?? false)
                      ? Colors.green.withValues(alpha: 0.08)
                      : (_cachedStorageGranted == null
                            ? Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest
                            : Theme.of(context).colorScheme.errorContainer
                                  .withValues(alpha: 0.3)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      (_cachedStorageGranted ?? false)
                          ? Icons.check_circle
                          : (_cachedStorageGranted == null
                                ? Icons.hourglass_empty
                                : Icons.warning_amber),
                      color: (_cachedStorageGranted ?? false)
                          ? Colors.green
                          : (_cachedStorageGranted == null
                                ? Theme.of(context).colorScheme.outline
                                : Theme.of(context).colorScheme.error),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        (_cachedStorageGranted ?? false)
                            ? l10n.t('settings.permGranted')
                            : (_cachedStorageGranted == null
                                  ? l10n.t('settings.permChecking')
                                  : l10n.t('settings.permHint')),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (!(_cachedStorageGranted ?? false))
                      FilledButton.tonal(
                        onPressed: (_cachedStorageGranted == null)
                            ? _checkStorage
                            : _requestStorage,
                        child: Text(
                          (_cachedStorageGranted == null)
                              ? l10n.t('settings.checkPerm')
                              : l10n.t('settings.grantPerm'),
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    if (_cachedStorageGranted ?? false)
                      IconButton(
                        icon: const Icon(Icons.refresh, size: 18),
                        onPressed: _checkStorage,
                        tooltip: l10n.t('settings.checkPerm'),
                      ),
                  ],
                ),
              ),
            ),
            const Divider(height: 24),
          ],

          // ========== Theme Mode (compact) ==========
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              l10n.t('settings.themeMode'),
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _compactTheme(
                  ThemeMode.system,
                  Icons.brightness_auto,
                  l10n.t('settings.themeSystem'),
                ),
                const SizedBox(width: 8),
                _compactTheme(
                  ThemeMode.light,
                  Icons.light_mode,
                  l10n.t('settings.themeLight'),
                ),
                const SizedBox(width: 8),
                _compactTheme(
                  ThemeMode.dark,
                  Icons.dark_mode,
                  l10n.t('settings.themeDark'),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ========== Color Scheme (compact) ==========
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.t('settings.colorScheme'),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ...presetColors.entries.map((entry) {
                      final sel = widget.config.colorScheme == entry.key;
                      return _colorOption(
                        label: l10n.t('settings.color.${entry.key}'),
                        selected: sel,
                        onTap: () {
                          setState(() => widget.config.colorScheme = entry.key);
                          widget.config.save();
                          widget.onColorChanged(entry.key);
                        },
                        swatch: Container(
                          width: sel ? 32 : 28,
                          height: sel ? 32 : 28,
                          decoration: BoxDecoration(
                            color: entry.value,
                            shape: BoxShape.circle,
                            border: sel
                                ? Border.all(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface,
                                    width: 2,
                                  )
                                : null,
                          ),
                          child: sel
                              ? const Icon(
                                  Icons.check,
                                  size: 16,
                                  color: Colors.white,
                                )
                              : null,
                        ),
                      );
                    }),
                    _colorOption(
                      label: l10n.t('settings.customColor'),
                      selected: _isCustomColor,
                      onTap: _showColorPicker,
                      swatch: Container(
                        width: _isCustomColor ? 32 : 28,
                        height: _isCustomColor ? 32 : 28,
                        decoration: BoxDecoration(
                          color: _isCustomColor
                              ? Color(widget.config.customColor)
                              : null,
                          gradient: _isCustomColor
                              ? null
                              : const SweepGradient(
                                  colors: [
                                    Color(0xFFFF0000),
                                    Color(0xFFFFFF00),
                                    Color(0xFF00FF00),
                                    Color(0xFF00FFFF),
                                    Color(0xFF0000FF),
                                    Color(0xFFFF00FF),
                                    Color(0xFFFF0000),
                                  ],
                                ),
                          shape: BoxShape.circle,
                          border: _isCustomColor
                              ? Border.all(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface,
                                  width: 2,
                                )
                              : null,
                        ),
                        child: Icon(
                          _isCustomColor ? Icons.check : Icons.palette_outlined,
                          size: 16,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ========== Language ==========
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Text(
              l10n.t('settings.language'),
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
          ..._languages.map((lang) {
            final sel = widget.config.language == lang['code'];
            return ListTile(
              dense: true,
              title: Text(lang['name']!),
              trailing: sel
                  ? Icon(
                      Icons.check,
                      color: Theme.of(context).colorScheme.primary,
                    )
                  : null,
              onTap: () {
                // Defer to the parent so MaterialApp's locale rebuilds
                // immediately; the parent handler also persists the change.
                widget.onLanguageChanged(lang['code']!);
                setState(() {});
              },
            );
          }),

          // ========== Notification Clipboard Buttons (Android only) ==========
          if (Theme.of(context).platform == TargetPlatform.android) ...[
            const Divider(height: 24),
            SwitchListTile(
              dense: true,
              title: Text(l10n.t('settings.notifClipboard')),
              subtitle: Text(l10n.t('settings.notifClipboardHint')),
              value: widget.config.notifClipboard,
              onChanged: (v) async {
                setState(() => widget.config.notifClipboard = v);
                await widget.config.save();
                // 服务运行中即时重建通知栏按钮（Android 侧持久化并刷新）；
                // 非 Android / 未运行时 Kotlin 只存 prefs，下次启动生效。
                try {
                  await _ch.invokeMethod('updateNotificationClipboard', {
                    'enabled': v,
                  });
                } catch (_) {}
              },
            ),
          ],

          // ========== Close Behavior (Desktop only) ==========
          if (Theme.of(context).platform == TargetPlatform.windows ||
              Theme.of(context).platform == TargetPlatform.linux ||
              Theme.of(context).platform == TargetPlatform.macOS) ...[
            const Divider(height: 24),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Text(
                l10n.t('settings.closeBehavior'),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
            ...['ask', 'tray', 'exit'].map((action) {
              final labels = {
                'ask': l10n.t('settings.closeAsk'),
                'tray': l10n.t('settings.closeTray'),
                'exit': l10n.t('settings.closeExit'),
              };
              final icons = {
                'ask': Icons.help_outline,
                'tray': Icons.minimize,
                'exit': Icons.exit_to_app,
              };
              final sel = widget.config.closeAction == action;
              return ListTile(
                dense: true,
                leading: Icon(icons[action], size: 20),
                title: Text(labels[action]!),
                trailing: sel
                    ? Icon(
                        Icons.check,
                        color: Theme.of(context).colorScheme.primary,
                      )
                    : null,
                onTap: () async {
                  setState(() => widget.config.closeAction = action);
                  await widget.config.save();
                },
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _colorOption({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    required Widget swatch,
  }) {
    return Semantics(
      selected: selected,
      child: SizedBox(
        width: 48,
        height: 48,
        child: IconButton(
          tooltip: label,
          onPressed: onTap,
          padding: EdgeInsets.zero,
          icon: swatch,
        ),
      ),
    );
  }

  Widget _compactTheme(ThemeMode mode, IconData icon, String label) {
    final sel = widget.themeMode == mode;
    return Expanded(
      child: Semantics(
        selected: sel,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            widget.onThemeModeChanged(mode);
            widget.config.themeMode = mode.name;
            widget.config.save();
            setState(() {});
          },
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: sel
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(
                        context,
                      ).colorScheme.outline.withValues(alpha: 0.3),
                width: sel ? 2 : 1,
              ),
              color: sel
                  ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)
                  : null,
            ),
            child: Column(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: sel ? Theme.of(context).colorScheme.primary : null,
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    color: sel ? Theme.of(context).colorScheme.primary : null,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _helpStep(BuildContext context, String num, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                num,
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onPrimary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontSize: 13, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  void _showPrivacyPolicy(BuildContext context) {
    final l10n = AppLocalizations(widget.config.language);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.privacy_tip_outlined, size: 20),
            const SizedBox(width: 8),
            Text(l10n.t('about.privacy')),
          ],
        ),
        content: SingleChildScrollView(
          child: Text(
            l10n.t('privacy.content'),
            style: const TextStyle(height: 1.6),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(MaterialLocalizations.of(ctx).okButtonLabel),
          ),
        ],
      ),
    );
  }
}
