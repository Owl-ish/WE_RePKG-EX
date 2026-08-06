import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:we_repkg/constants/i10n.dart';
import 'package:we_repkg/constants/keys.dart';
import 'package:we_repkg/models/enums.dart';
import 'package:we_repkg/utils/storage.dart';
import 'package:we_repkg/views/top/sort_dropdown.dart';
import 'package:we_repkg/widgets/pill_dropdown.dart';

// Untranslated, so `tr` hands back the key and each option is still distinct.
void main() {
  Future<ProviderContainer> show(
    WidgetTester tester,
    Map<String, Object> settings,
    Widget child,
  ) async {
    // runAsync, because seeding awaits a real platform-channel reply that the
    // fake clock inside testWidgets never delivers.
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues(settings);
      await StorageUtil.init();
    });
    final ProviderContainer container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(body: Center(child: child)),
        ),
      ),
    );
    return container;
  }

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.byType(InkWell));
    await tester.pumpAndSettle();
  }

  // Switching library rescans ~2100 folders, so picking the one already on
  // screen has to do nothing at all.
  testWidgets('picking the current value changes nothing', (tester) async {
    final List<String> picked = <String>[];
    await show(
      tester,
      <String, Object>{},
      PillDropdown<String>(
        value: 'one',
        items: const <String>['one', 'two'],
        labelOf: (String value) => value,
        onChanged: picked.add,
      ),
    );

    await open(tester);
    await tester.tap(find.text('one').last);
    await tester.pumpAndSettle();

    expect(picked, isEmpty);

    await open(tester);
    await tester.tap(find.text('two').last);
    await tester.pumpAndSettle();

    expect(picked, <String>['two']);
  });

  testWidgets('the update sort is offered while the acf is read', (
    tester,
  ) async {
    await show(tester, <String, Object>{
      AppKeys.useAcfInfo: true,
    }, const SortDropdown());

    await open(tester);

    expect(find.text(AppI10n.homeSortUpdate), findsOneWidget);
  });

  // The option goes, not just the value: an option that cannot be honoured
  // still looks like a choice.
  testWidgets('the update sort is not offered while the acf is not read', (
    tester,
  ) async {
    await show(tester, <String, Object>{
      AppKeys.useAcfInfo: false,
      AppKeys.sortType: SortType.size.index,
    }, const SortDropdown());

    await open(tester);

    expect(find.text(AppI10n.homeSortUpdate), findsNothing);
    expect(find.text(AppI10n.homeSortDate), findsOneWidget);
  });
}
