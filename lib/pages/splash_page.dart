import 'package:flutter/material.dart';

class SplashPage extends StatefulWidget {
  final Widget child;
  const SplashPage({super.key, required this.child});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> with TickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();

    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _ctrl.stop();
      _ctrl.value = 1;
    } else if (!_ctrl.isAnimating && !_ctrl.isCompleted) {
      _ctrl.forward();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Must match native launch_background colors exactly
    final bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF8F3FF);
    // Must match bitmap text colors: light(40,40,40,200) dark(230,230,230,200)
    final textColor = isDark ? const Color(0xC8E6E6E6) : const Color(0xC8282828);
    final barColor = Theme.of(context).colorScheme.primary;

    return Stack(
      children: [
        widget.child,
        AnimatedBuilder(
          animation: _ctrl,
          builder: (context, _) {
            if (_ctrl.isCompleted) return const SizedBox.shrink();

            final v = _ctrl.value;

            // Immediately start: text slides up + scales down, bar fades in
            // All happening together for seamless feel
            final scale = _lerp(1.0, 0.78, v);
            final offset = _lerp(0.0, -48.0, v);
            final barAlpha = (v * 2.5).clamp(0.0, 1.0); // bar appears quickly

            return Scaffold(
              backgroundColor: bgColor,
              body: Center(
                child: Transform.translate(
                  offset: Offset(0, offset),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Transform.scale(
                        scale: scale,
                        // fontSize 24 + letterSpacing 2 visually matches the
                        // native bitmap splash (186×24px @ mdpi, baseScale=3
                        // in scripts/gen_splash_bitmaps.dart). Keeping them
                        // identical removes the jarring "pop bigger" frame
                        // when Flutter takes over from the native window.
                        child: Text(
                          'FileInfra',
                          style: TextStyle(
                            fontFamily: 'PressStart2P',
                            fontSize: 24,
                            color: textColor,
                            letterSpacing: 2,
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),
                      Opacity(
                        opacity: barAlpha,
                        child: SizedBox(
                          width: 200,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: v,
                              minHeight: 4,
                              backgroundColor: barColor.withValues(alpha: 0.15),
                              valueColor: AlwaysStoppedAnimation(barColor),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  double _lerp(double a, double b, double t) => a + (b - a) * t;
}
