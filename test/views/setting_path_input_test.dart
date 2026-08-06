import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:we_repkg/views/setting/setting_path_input.dart';

void main() {
  Widget wrap({VoidCallback? onRefresh}) => MaterialApp(
    home: Scaffold(
      body: SettingPathInput(
        label: 'Backup root',
        path: null,
        hintText: 'pick one',
        onPick: () {},
        onRefresh: onRefresh,
      ),
    ),
  );

  Finder refresh() => find.byIcon(Icons.refresh_rounded);

  // The other path rows reset to a derived default; the backup root has none,
  // so a refresh button there would be permanently dead.
  testWidgets('a row with nothing to reset to shows no refresh button', (
    tester,
  ) async {
    await tester.pumpWidget(wrap());

    expect(refresh(), findsNothing);
  });

  testWidgets('a row that can reset keeps its refresh button', (tester) async {
    await tester.pumpWidget(wrap(onRefresh: () {}));

    expect(refresh(), findsOneWidget);
  });
}
