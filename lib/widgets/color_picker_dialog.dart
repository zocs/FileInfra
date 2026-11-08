import 'dart:math' as math;
import 'package:flutter/material.dart';

/// 自绘 HSV 色盘对话框：饱和度/亮度面板 + 色相条 + 实时预览。
/// 无第三方依赖，纯 Flutter 实现。返回选中颜色（Navigator.pop）或 null（取消）。
class ColorPickerDialog extends StatefulWidget {
  final Color initialColor;
  final String title;
  final String doneLabel;
  final String cancelLabel;

  const ColorPickerDialog({
    super.key,
    required this.initialColor,
    required this.title,
    required this.doneLabel,
    required this.cancelLabel,
  });

  @override
  State<ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<ColorPickerDialog> {
  late HSVColor _hsv = HSVColor.fromColor(widget.initialColor);

  void _update(HSVColor v) => setState(() => _hsv = v);

  @override
  Widget build(BuildContext context) {
    final hueColor = HSVColor.fromAHSV(1, _hsv.hue, 1, 1).toColor();
    return AlertDialog(
      // A bounded width avoids intrinsic measurement of the drag panels'
      // LayoutBuilders; parent constraints still shrink this on narrow screens.
      constraints: const BoxConstraints.tightFor(width: 348),
      scrollable: true,
      title: Text(widget.title),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SvPanel(hueColor: hueColor, hsv: _hsv, onChanged: _update),
            const SizedBox(height: 16),
            _HueBar(hsv: _hsv, onChanged: _update),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: _hsv.toColor(),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '#${_hsv.toColor().toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(widget.cancelLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _hsv.toColor()),
          child: Text(widget.doneLabel),
        ),
      ],
    );
  }
}

/// 饱和度 × 亮度二维面板
class _SvPanel extends StatelessWidget {
  final Color hueColor;
  final HSVColor hsv;
  final ValueChanged<HSVColor> onChanged;

  const _SvPanel({
    required this.hueColor,
    required this.hsv,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1.4,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;

          void update(Offset local) {
            final s = (local.dx / w).clamp(0.0, 1.0);
            final v = (1 - local.dy / h).clamp(0.0, 1.0);
            onChanged(HSVColor.fromAHSV(1, hsv.hue, s, v));
          }

          final marker = Offset(hsv.saturation * w, (1 - hsv.value) * h);
          return GestureDetector(
            onPanDown: (d) => update(d.localPosition),
            onPanUpdate: (d) => update(d.localPosition),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                children: [
                  // 层 1：横向 白 → 纯色相
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.white, hueColor],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                      ),
                    ),
                  ),
                  // 层 2：纵向 透明 → 黑
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.transparent, Colors.black],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: marker.dx - 7,
                    top: marker.dy - 7,
                    child: IgnorePointer(
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.transparent,
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: const [
                            BoxShadow(color: Colors.black45, blurRadius: 2),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 色相条
class _HueBar extends StatelessWidget {
  final HSVColor hsv;
  final ValueChanged<HSVColor> onChanged;

  const _HueBar({required this.hsv, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;

        void update(Offset local) {
          final hue = ((local.dx / w) * 360).clamp(0.0, 360.0);
          onChanged(HSVColor.fromAHSV(1, hue, hsv.saturation, hsv.value));
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanDown: (d) => update(d.localPosition),
          onPanUpdate: (d) => update(d.localPosition),
          child: SizedBox(
            height: 48,
            child: Center(
              child: SizedBox(
                height: 24,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          gradient: LinearGradient(
                            colors: [
                              for (var h = 0; h <= 360; h += 60)
                                HSVColor.fromAHSV(
                                  1,
                                  h.toDouble(),
                                  1,
                                  1,
                                ).toColor(),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: math.min((hsv.hue / 360) * w - 8, w - 16),
                      top: 4,
                      child: IgnorePointer(
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: const [
                              BoxShadow(color: Colors.black45, blurRadius: 2),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
