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

  testWidgets('file tree route banners tolerate horizontal scrolling', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 120,
            child: FileTreeScrollView(
              foreground: Colors.black,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const <Widget>[
                  FileTreeRouteBanner(
                    source:
                        'Workshop / a deliberately long wallpaper folder name',
                    destination:
                        'Backup Workshop / another deliberately long folder name',
                    foreground: Colors.black,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    expect(find.byType(FileTreeRouteBanner), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('file tree trailing controls fit inside the horizontal viewport', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 120,
            child: FileTreeScrollView(
              foreground: Colors.black,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  FileTreeRow(
                    depth: 1,
                    icon: Icons.inventory_2_outlined,
                    label:
                        'scene.pkg with a deliberately long changed-package label',
                    foreground: Colors.black,
                    trailing: TextButton(
                      onPressed: () {},
                      child: const Text('Inspect contents'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    expect(find.text('Inspect contents'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'file tree rows with trailing actions show a compact hover background',
    (tester) async {
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
                FileTreeContextAction(
                  label: 'Compare files',
                  onSelected: (_) {},
                ),
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
        reason: 'InkWell updates Material hover state even with no hover paint',
      );
      expect(tester.getSize(paint).height, lessThanOrEqualTo(32));
      final CustomPaint before = tester.widget<CustomPaint>(paint);
      expect(before.painter, isNotNull);

      final TestGesture mouse = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
      );
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(row));
      await tester.pump(const Duration(milliseconds: 100));

      final CustomPaint after = tester.widget<CustomPaint>(paint);
      expect(
        identical(after.painter, before.painter),
        isTrue,
        reason:
            'hover should drive the existing painter instead of rebuilding it',
      );
      expect(
        trailingBuilds,
        buildsBeforeHover,
        reason:
            'hover must repaint only the background, not rebuild the accessibility-bearing row subtree',
      );
      expect(row.evaluate().single, same(rowElementBeforeHover));
      final SemanticsNode semanticsAfterHover = tester.getSemantics(row);
      expect(semanticsAfterHover.id, semanticsBeforeHover.id);
      expect(
        semanticsAfterHover.getSemanticsData(),
        semanticsBeforeHover.getSemanticsData(),
        reason: 'hover must not publish a changed accessibility row',
      );
      await mouse.removePointer();
      semantics.dispose();
    },
  );

  testWidgets(
    'package-style file rows do not register pointer hover callbacks',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FileTreeRow(
              key: const ValueKey<String>('package-file-row'),
              depth: 4,
              icon: Icons.image_outlined,
              label: 'materials  ›  effect.png',
              foreground: Colors.black,
              hoverHighlight: false,
              choice: FileTreeRowChoice(
                selected: true,
                onChanged: (_) {},
                rejectTooltip: 'Keep old',
                acceptTooltip: 'Apply change',
                disabledTooltip: 'Repacking coming soon',
                enabled: false,
                foreground: Colors.black,
              ),
              contextActions: <FileTreeContextAction>[
                FileTreeContextAction(
                  label: 'Compare files',
                  onSelected: (_) {},
                ),
              ],
            ),
          ),
        ),
      );

      final Finder row = find.byKey(const ValueKey<String>('package-file-row'));
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
      expect(
        tester.getSemantics(row).getSemanticsData(),
        semanticsBeforeHover,
        reason: 'package filename hover must be inert for the Windows AX tree',
      );
      await mouse.removePointer();
      semantics.dispose();
    },
  );

  testWidgets('file tree avoids a custom dynamic semantics root on Windows', (
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
              child: Column(
                children: <Widget>[
                  FileTreeRow(
                    depth: 0,
                    icon: Icons.insert_drive_file_outlined,
                    label: 'one.txt',
                    foreground: Colors.black,
                  ),
                ],
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
    expect(
      tester.widget(treeRoot),
      isA<KeyedSubtree>(),
      reason:
          'dynamic file trees must not create a custom AX parent above the scrollables',
    );
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
                child: FileTreeAction(
                  icon: Icons.copy_rounded,
                  tooltip: 'Copy path',
                  foreground: Colors.black,
                  onPressed: () {},
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
            widget is Semantics && widget.properties.tooltip == 'Copy path',
        description: 'stable Copy path semantics',
      );
      expect(semanticDescription, findsOneWidget);
      expect(
        tester.getSemantics(semanticDescription).getSemanticsData().tooltip,
        'Copy path',
      );

      final TestGesture mouse = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
      );
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(action));
      await tester.pump();

      expect(find.text('Copy path'), findsNothing);
      expect(semanticDescription, findsOneWidget);
      expect(
        tester.getSemantics(semanticDescription).getSemanticsData().tooltip,
        'Copy path',
      );
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
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'File tree row',
      reason: 'pointer activation keeps the row available to keyboard users',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(activations, 2);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(activations, 3);
  });

  testWidgets('file tree choices can be disabled by a consumer', (
    tester,
  ) async {
    bool changed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FileTreeRowChoice(
            selected: true,
            onChanged: (bool value) => changed = true,
            rejectTooltip: 'Reject',
            acceptTooltip: 'Accept',
            disabledTooltip: 'Repacking coming soon',
            enabled: false,
            foreground: Colors.black,
            rejectKey: const ValueKey<String>('disabled-choice-reject'),
            acceptKey: const ValueKey<String>('disabled-choice-accept'),
          ),
        ),
      ),
    );

    final Finder reject = find.byKey(
      const ValueKey<String>('disabled-choice-reject'),
    );
    final Finder accept = find.byKey(
      const ValueKey<String>('disabled-choice-accept'),
    );
    expect(
      tester.widget<Semantics>(reject).properties.label,
      'Repacking coming soon',
    );
    expect(
      tester.widget<Semantics>(accept).properties.label,
      'Repacking coming soon',
    );
    expect(tester.widget<Semantics>(reject).properties.enabled, isFalse);
    expect(tester.widget<Semantics>(accept).properties.enabled, isFalse);
    expect(find.byTooltip('Repacking coming soon'), findsNothing);
    expect(find.byType(IconButton), findsNothing);

    await tester.tap(reject);
    await tester.tap(accept);
    expect(changed, isFalse);
  });

  testWidgets('file tree path controls stay usable in narrow viewports', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 120,
            child: FileTreeScrollView(
              foreground: Colors.black,
              child: FileTreePathControl(
                depth: 1,
                label: 'Temporary folder',
                path:
                    r'C:\Users\George\AppData\Local\Temp\WeRePKG\pkg-diff\very-long-session-folder',
                foreground: Colors.black,
                copyTooltip: 'Copy path',
                openTooltip: 'Open in Explorer',
                onOpen: () {},
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    expect(find.byType(SelectableText), findsOneWidget);
    expect(find.byIcon(Icons.copy_rounded), findsOneWidget);
    expect(find.byIcon(Icons.folder_open_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
