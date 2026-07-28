import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:we_repkg/widgets/scroll_edge_controls.dart';

/// Mounts the button over a scrollable long enough for both edges to be off
/// screen, mirroring how content.dart places it in a fixed 112x80 hot zone.
Future<ScrollController> _pumpButton(
  WidgetTester tester,
  ValueNotifier<bool> active,
) async {
  final ScrollController controller = ScrollController();
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Stack(
          children: [
            ListView.builder(
              controller: controller,
              itemCount: 200,
              itemBuilder: (_, index) => SizedBox(height: 50),
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: SizedBox(
                width: 112,
                height: 80,
                child: Center(
                  child: ScrollEdgeButton(
                    controller: controller,
                    active: active,
                    edge: ScrollEdge.top,
                    tooltip: 'top',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  // Away from both edges, so only `active` decides whether the button shows.
  controller.jumpTo(500);
  await tester.pump();
  return controller;
}

void main() {
  testWidgets('survives the pointer crossing faster than the fade', (
    tester,
  ) async {
    final ValueNotifier<bool> active = ValueNotifier<bool>(false);
    addTearDown(active.dispose);
    await _pumpButton(tester, active);

    // MouseRegion drives `active` from onEnter/onExit, so a mouse swept across
    // the hot zone toggles it well inside the 180ms fade. Reversing a fade
    // still in flight is the case that used to throw.
    for (int i = 0; i < 6; i++) {
      active.value = !active.value;
      await tester.pump(const Duration(milliseconds: 40));
      expect(tester.takeException(), isNull, reason: 'toggle $i');
    }

    await tester.pumpAndSettle();
  });

  testWidgets('fades in and takes pointers only while active', (tester) async {
    final ValueNotifier<bool> active = ValueNotifier<bool>(false);
    addTearDown(active.dispose);
    await _pumpButton(tester, active);

    final Finder gate = find.descendant(
      of: find.byType(ScrollEdgeButton),
      matching: find.byType(IgnorePointer),
    );
    final Finder fade = find.descendant(
      of: find.byType(ScrollEdgeButton),
      matching: find.byType(AnimatedOpacity),
    );

    expect(tester.widget<IgnorePointer>(gate).ignoring, isTrue);
    expect(tester.widget<AnimatedOpacity>(fade).opacity, 0);

    active.value = true;
    await tester.pumpAndSettle();

    expect(tester.widget<IgnorePointer>(gate).ignoring, isFalse);
    expect(tester.widget<AnimatedOpacity>(fade).opacity, 1);
    expect(find.byKey(ScrollEdgeButton.topButtonKey), findsOneWidget);
  });
}
