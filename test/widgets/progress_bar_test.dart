import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:we_repkg/widgets/progress_bar.dart';

void main() {
  double? shown(WidgetTester tester) => tester
      .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
      .value;

  Future<void> pump(WidgetTester tester, double? value) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ProgressBar(
          value: value,
          step: const Duration(milliseconds: 100),
        ),
      ),
    ),
  );

  // The scan reports about a hundred times, so a bar that restarts its ease
  // from a standstill each time trails the count it sits under.
  testWidgets('a new value is moved to, not jumped to', (tester) async {
    await pump(tester, 0.2);
    await tester.pump(const Duration(milliseconds: 200));
    expect(shown(tester), 0.2);

    await pump(tester, 0.9);
    await tester.pump(const Duration(milliseconds: 50));

    final double? part = shown(tester);
    expect(part, greaterThan(0.2));
    expect(part, lessThan(0.9));

    await tester.pump(const Duration(milliseconds: 100));
    expect(shown(tester), 0.9);
  });

  testWidgets('no value at all sweeps rather than sitting at zero', (
    tester,
  ) async {
    await pump(tester, null);

    expect(shown(tester), isNull);
    await tester.pump(const Duration(milliseconds: 100));
  });
}
