import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:we_repkg/widgets/image_view.dart';

// A tile whose preview has not loaded is the common case while scrolling or
// searching, and it is the one that threw when the placeholder fill was
// dropped without dropping the clip that needed it.
void main() {
  testWidgets('builds with no preview to show yet', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ImageView(size: 180, previews: '')),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(ImageView), findsOneWidget);
  });

  testWidgets('builds with a hover scale animation attached', (tester) async {
    final AnimationController controller = AnimationController(
      vsync: tester,
      duration: const Duration(milliseconds: 100),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ImageView(size: 180, previews: '', scale: controller),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });
}
