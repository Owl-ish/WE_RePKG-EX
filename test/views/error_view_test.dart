import 'package:bot_toast/bot_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:we_repkg/cores/toast.dart';
import 'package:we_repkg/models/error.dart';
import 'package:we_repkg/views/states/error.dart';

void main() {
  // LookupBoundary stops the ancestor lookup where debugCheckHasOverlay does,
  // reproducing BotToast's layer without booting it.
  testWidgets('builds where no Overlay ancestor is reachable', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LookupBoundary(
          child: ErrorView([
            ErrorInfo(wallpaper: null, message: 'Extract failed: boom'),
          ], () {}),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('boom'), findsOneWidget);
  });

  // The real call site, so the dialog also meets BotToast's own constraints.
  testWidgets('shows through the real BotToast layer', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: BotToastInit(),
        navigatorObservers: [BotToastNavigatorObserver()],
        home: const Scaffold(),
      ),
    );

    showErrorView([
      ErrorInfo(wallpaper: null, message: 'Extract failed: boom'),
    ]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.takeException(), isNull);
    expect(find.byType(ErrorView), findsOneWidget);
    expect(find.text('boom'), findsOneWidget);

    BotToast.cleanAll();
    await tester.pump(const Duration(milliseconds: 400));
  });
}
