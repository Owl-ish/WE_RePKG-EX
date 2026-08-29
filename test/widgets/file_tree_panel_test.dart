import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
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
}
