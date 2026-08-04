import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:we_repkg/widgets/folder_input.dart';

void main() {
  Widget wrap(String? text) => MaterialApp(
    home: Scaffold(
      body: FolderInput(text: text, hintText: 'pick one', onPressed: () {}),
    ),
  );

  TextEditingController controllerOf(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField)).controller!;

  // Choosing a folder changes the path, which rebuilds this. Handing the
  // TextField a new controller each time throws away its editable subtree and
  // the accessibility nodes under it, which is what upsets the Windows bridge.
  testWidgets('a new path reuses the field instead of replacing it', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(r'C:\before'));
    final TextEditingController first = controllerOf(tester);

    await tester.pumpWidget(wrap(r'C:\after'));

    expect(controllerOf(tester), same(first));
    expect(first.text, r'C:\after');
  });

  testWidgets('an unset path shows the hint rather than "null"', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(null));

    expect(controllerOf(tester).text, isEmpty);
    expect(find.text('pick one'), findsOneWidget);
  });

  // Nothing disposed the per-build controllers before, one per frame.
  testWidgets('the controller is disposed with the widget', (tester) async {
    await tester.pumpWidget(wrap(r'C:\gone'));
    final TextEditingController controller = controllerOf(tester);

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));

    expect(() => controller.addListener(() {}), throwsFlutterError);
  });
}
