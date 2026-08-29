import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:we_repkg/widgets/file_tree_panel.dart';

void main() {
  test('file comparison selection follows visible tree order', () {
    const List<FileTreeCompareCandidate> candidates =
        <FileTreeCompareCandidate>[
          FileTreeCompareCandidate(id: 'a', path: 'a.txt', label: 'A'),
          FileTreeCompareCandidate(id: 'b', path: 'b.txt', label: 'B'),
          FileTreeCompareCandidate(id: 'c', path: 'c.txt', label: 'C'),
        ];
    final FileTreeCompareSelection selection = FileTreeCompareSelection();

    selection.click(candidates, candidates[0], control: false, shift: false);
    selection.click(candidates, candidates[2], control: false, shift: true);

    expect(selection.selected, <String>{'a', 'b', 'c'});
    selection.clear();
    expect(selection.selected, isEmpty);
    expect(selection.anchor, isNull);
  });

  testWidgets('file comparison bar opens only the current two-file pair', (
    tester,
  ) async {
    const List<FileTreeCompareCandidate> candidates =
        <FileTreeCompareCandidate>[
          FileTreeCompareCandidate(id: 'stale', path: 'old.txt', label: 'Old'),
          FileTreeCompareCandidate(id: 'a', path: 'a.txt', label: 'A'),
          FileTreeCompareCandidate(id: 'b', path: 'b.txt', label: 'B'),
        ];
    final FileTreeCompareSelection selection = FileTreeCompareSelection()
      ..selected = <String>{'stale', 'a', 'b'};
    FileTreeCompareCandidate? openedFirst;
    FileTreeCompareCandidate? openedSecond;
    bool cleared = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FileTreeCompareBar(
            keyBase: 'manual-compare',
            candidates: candidates.sublist(1),
            selection: selection,
            foreground: Colors.black,
            label: 'Selected for comparison',
            clearTooltip: 'Clear selection',
            onClear: () => cleared = true,
            actionBuilder:
                (
                  Key key,
                  FileTreeCompareCandidate first,
                  FileTreeCompareCandidate second,
                ) => IconButton(
                  key: key,
                  onPressed: () {
                    openedFirst = first;
                    openedSecond = second;
                  },
                  icon: const Icon(Icons.compare_rounded),
                ),
          ),
        ),
      ),
    );

    expect(find.text('2 / 2'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey<String>('manual-compare-action')),
    );
    expect(openedFirst?.id, 'a');
    expect(openedSecond?.id, 'b');
    await tester.tap(
      find.byKey(const ValueKey<String>('manual-compare-clear')),
    );
    expect(cleared, isTrue);
  });

  testWidgets('file tree hover repaints without rebuilding row semantics', (
    tester,
  ) async {
    int trailingBuilds = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FileTreeRow(
            key: const ValueKey<String>('hover-file-row'),
            depth: 1,
            icon: Icons.insert_drive_file_outlined,
            label: 'preview.jpg',
            foreground: Colors.black,
            trailing: Builder(
              builder: (BuildContext context) {
                trailingBuilds++;
                return const Icon(Icons.compare_rounded, size: 17);
              },
            ),
            contextActions: <FileTreeContextAction>[
              FileTreeContextAction(label: 'Compare files', onSelected: (_) {}),
            ],
          ),
        ),
      ),
    );

    final Finder row = find.byKey(const ValueKey<String>('hover-file-row'));
    final SemanticsHandle semantics = tester.ensureSemantics();
    final int buildsBeforeHover = trailingBuilds;
    final Element rowElementBeforeHover = row.evaluate().single;
    final SemanticsNode semanticsBeforeHover = tester.getSemantics(row);
    final Finder paint = find.descendant(
      of: row,
      matching: find.byType(CustomPaint),
    );
    expect(paint, findsOneWidget);
    expect(
      find.descendant(of: row, matching: find.byType(InkWell)),
      findsNothing,
      reason: 'InkWell changes Material state when the pointer enters a row',
    );
    final CustomPaint before = tester.widget<CustomPaint>(paint);

    final TestGesture mouse = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
    );
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(row));
    await tester.pump(const Duration(milliseconds: 100));

    final CustomPaint after = tester.widget<CustomPaint>(paint);
    expect(identical(after.painter, before.painter), isTrue);
    expect(trailingBuilds, buildsBeforeHover);
    expect(row.evaluate().single, same(rowElementBeforeHover));
    final SemanticsNode semanticsAfterHover = tester.getSemantics(row);
    expect(semanticsAfterHover.id, semanticsBeforeHover.id);
    expect(
      semanticsAfterHover.getSemanticsData(),
      semanticsBeforeHover.getSemanticsData(),
    );
    await mouse.removePointer();
    semantics.dispose();
  });

  testWidgets('hover-inert file rows register no pointer hover callbacks', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FileTreeRow(
            key: const ValueKey<String>('hover-inert-file-row'),
            depth: 4,
            icon: Icons.image_outlined,
            label: 'materials  ›  effect.png',
            foreground: Colors.black,
            hoverHighlight: false,
            contextActions: <FileTreeContextAction>[
              FileTreeContextAction(label: 'Compare files', onSelected: (_) {}),
            ],
          ),
        ),
      ),
    );

    final Finder row = find.byKey(
      const ValueKey<String>('hover-inert-file-row'),
    );
    final SemanticsHandle semantics = tester.ensureSemantics();
    final Element rowElementBeforeHover = row.evaluate().single;
    final SemanticsData semanticsBeforeHover = tester
        .getSemantics(row)
        .getSemanticsData();
    expect(
      find.descendant(
        of: row,
        matching: find.byWidgetPredicate(
          (Widget widget) =>
              widget is MouseRegion &&
              (widget.onEnter != null || widget.onExit != null),
        ),
      ),
      findsNothing,
    );

    final TestGesture mouse = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
    );
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(row));
    await tester.pump(const Duration(milliseconds: 100));

    expect(row.evaluate().single, same(rowElementBeforeHover));
    expect(tester.getSemantics(row).getSemanticsData(), semanticsBeforeHover);
    await mouse.removePointer();
    semantics.dispose();
  });

  testWidgets('file tree avoids a custom dynamic semantics root', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            height: 180,
            child: FileTreeScrollView(
              foreground: Colors.black,
              semanticLabel: 'Dynamic file changes',
              child: FileTreeRow(
                depth: 0,
                icon: Icons.insert_drive_file_outlined,
                label: 'one.txt',
                foreground: Colors.black,
              ),
            ),
          ),
        ),
      ),
    );

    final Finder treeRoot = find.byKey(
      const ValueKey<String>('file-tree-semantics-Dynamic file changes'),
    );
    expect(treeRoot, findsOneWidget);
    expect(tester.widget(treeRoot), isA<KeyedSubtree>());
  });

  testWidgets(
    'Windows file trees suppress tooltip overlays but retain semantics',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 320,
              height: 180,
              child: FileTreeScrollView(
                foreground: Colors.black,
                child: FileTreeTooltip(
                  message: 'Compare files',
                  child: IconButton(
                    onPressed: () {},
                    icon: const Icon(Icons.compare_rounded),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      final SemanticsHandle semantics = tester.ensureSemantics();
      final Finder action = find.byType(IconButton);
      final Finder semanticDescription = find.byWidgetPredicate(
        (Widget widget) =>
            widget is Semantics && widget.properties.tooltip == 'Compare files',
        description: 'stable Compare files semantics',
      );
      expect(semanticDescription, findsOneWidget);
      expect(
        tester.getSemantics(semanticDescription).getSemanticsData().tooltip,
        'Compare files',
      );

      final TestGesture mouse = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
      );
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(action));
      await tester.pump();

      expect(find.text('Compare files'), findsNothing);
      expect(semanticDescription, findsOneWidget);
      await mouse.removePointer();
      semantics.dispose();
    },
    skip: !Platform.isWindows,
  );

  testWidgets('file tree rows expose app-standard right-click actions', (
    tester,
  ) async {
    bool compared = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FileTreeRow(
            key: const ValueKey<String>('context-file-row'),
            depth: 1,
            icon: Icons.insert_drive_file_outlined,
            label: 'project.json',
            foreground: Colors.black,
            contextActions: <FileTreeContextAction>[
              FileTreeContextAction(
                label: 'Compare files',
                onSelected: (_) {
                  compared = true;
                },
              ),
            ],
          ),
        ),
      ),
    );

    final Finder row = find.byKey(const ValueKey<String>('context-file-row'));
    final TestGesture secondary = await tester.startGesture(
      tester.getCenter(row),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryButton,
    );
    await secondary.up();
    await tester.pumpAndSettle();

    expect(find.text('Compare files'), findsOneWidget);
    await tester.tap(find.text('Compare files'));
    await tester.pumpAndSettle();
    expect(compared, isTrue);
  });

  testWidgets('file tree rows remain keyboard activatable without InkWell', (
    tester,
  ) async {
    int activations = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FileTreeRow(
            key: const ValueKey<String>('keyboard-file-row'),
            depth: 1,
            icon: Icons.insert_drive_file_outlined,
            label: 'scene.json',
            foreground: Colors.black,
            onTap: () => activations++,
          ),
        ),
      ),
    );

    final Finder row = find.byKey(const ValueKey<String>('keyboard-file-row'));
    expect(
      find.descendant(of: row, matching: find.byType(InkWell)),
      findsNothing,
    );
    await tester.tap(row);
    expect(activations, 1);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'File tree row');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(activations, 2);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(activations, 3);
  });
}
