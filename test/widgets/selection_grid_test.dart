import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:we_repkg/widgets/selection_grid.dart';

void main() {
  testWidgets(
    'grouped grids share marquee selection and empty-space clearing',
    (tester) async {
      Set<String> selected = <String>{};
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SelectionGrid(
              id: 'grouped-grid',
              itemCount: 4,
              sections: const <SelectionGridSection>[
                SelectionGridSection(
                  itemCount: 2,
                  header: SizedBox.expand(),
                  headerExtent: 60,
                  headerPinned: true,
                ),
                SelectionGridSection(
                  itemCount: 2,
                  header: SizedBox.expand(),
                  headerExtent: 60,
                  headerPinned: true,
                ),
              ],
              idAt: (int index) => '$index',
              currentSelection: () => selected,
              onSelectionChanged: (Set<String> ids) => selected = ids,
              entranceOnMount: false,
              itemBuilder: (context, index, geometry) => ColoredBox(
                key: ValueKey<String>('tile-$index'),
                color: Colors.blue,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final Rect firstTile = tester.getRect(
        find.byKey(const ValueKey<String>('tile-0')),
      );
      final TestGesture mouse = await tester.startGesture(
        Offset(firstTile.center.dx, firstTile.top - 4),
        kind: PointerDeviceKind.mouse,
      );
      await mouse.moveTo(firstTile.center);
      await tester.pump();
      await mouse.up();
      await mouse.removePointer();
      await tester.pump();

      expect(selected, contains('0'));

      await tester.tapAt(Offset(firstTile.center.dx, firstTile.top - 10));
      await tester.pump();
      expect(selected, isEmpty);
    },
  );
  testWidgets(
    'section counts fail safely when they do not match the flat list',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SelectionGrid(
            id: 'invalid-grouped-grid',
            itemCount: 2,
            sections: const <SelectionGridSection>[
              SelectionGridSection(itemCount: 1),
            ],
            idAt: (int index) => '$index',
            currentSelection: () => <String>{},
            onSelectionChanged: (_) {},
            entranceOnMount: false,
            itemBuilder: (context, index, geometry) => const SizedBox.expand(),
          ),
        ),
      );

      expect(tester.takeException(), isA<FlutterError>());
    },
  );
}
