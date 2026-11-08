import 'package:file_infra/pages/splash_page.dart';
import 'package:file_infra/widgets/color_picker_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('reduced motion skips the animated splash overlay', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: const SplashPage(child: Scaffold(body: Text('Ready'))),
        ),
      ),
    );
    expect(find.text('Ready'), findsOneWidget);
    expect(find.text('FileInfra'), findsNothing);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('color picker fits a short viewport and has a 48dp hue target', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<Color>(
                context: context,
                builder: (_) => const ColorPickerDialog(
                  initialColor: Colors.red,
                  title: 'Pick a Color',
                  doneLabel: 'Done',
                  cancelLabel: 'Cancel',
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final dragTargets = find.byWidgetPredicate(
      (widget) => widget is GestureDetector && widget.onPanUpdate != null,
    );
    expect(dragTargets, findsNWidgets(2));
    for (final element in dragTargets.evaluate()) {
      expect(
        tester.getSize(find.byWidget(element.widget)).height,
        greaterThanOrEqualTo(48),
      );
    }
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(ColorPickerDialog), findsNothing);
  });

  testWidgets('hue target padding responds to touch', (tester) async {
    Color? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                picked = await showDialog<Color>(
                  context: context,
                  builder: (_) => const ColorPickerDialog(
                    initialColor: Colors.red,
                    title: 'Pick a Color',
                    doneLabel: 'Done',
                    cancelLabel: 'Cancel',
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final hue = find
        .byWidgetPredicate(
          (widget) => widget is GestureDetector && widget.onPanUpdate != null,
        )
        .last;
    final rect = tester.getRect(hue);
    await tester.tapAt(Offset(rect.center.dx, rect.top + 1));
    await tester.pump();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(picked, HSVColor.fromColor(Colors.red).withHue(180).toColor());
  });
}
