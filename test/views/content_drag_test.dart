import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:we_repkg/constants/keys.dart';
import 'package:we_repkg/models/enums.dart';
import 'package:we_repkg/constants/nums.dart';
import 'package:we_repkg/models/wallpaper.dart';
import 'package:we_repkg/provider/system.dart';
import 'package:we_repkg/provider/wallpaper.dart';
import 'package:we_repkg/utils/storage.dart';
import 'package:we_repkg/views/content/content.dart';
import 'package:we_repkg/views/content/item.dart';

/// The maths under the marquee has its own tests in grid_selection_test. This
/// covers the wiring: the gesture, the ticker that scrolls past the edge, and
/// the selection writes they produce.
///
/// Geometry at the default 800x600 surface: the 24px inset each side leaves 752,
/// which comes out as four 182px columns on a 190px stride. pumpGrid asserts it,
/// because 752 / 188 is exactly 4 and a pixel either way would give five columns
/// and a different tile size.
const double _tile = 182;
const double _firstLeft = LayoutNums.edgeInset;
const double _firstTop = LayoutNums.contentGap;

/// Middle of the top left cell, in viewport coordinates at scroll zero.
const Offset _firstCentre = Offset(
  _firstLeft + _tile / 2,
  _firstTop + _tile / 2,
);

/// In the gap between the first two columns, which belongs to no tile, so a
/// press here reaches the grid rather than a tile's own click handler.
const Offset _columnGap = Offset(210, 300);

WallpaperInfo make(String id) => WallpaperInfo(
  id: id,
  title: 'Wallpaper $id',
  contentRating: 'everyone',
  tags: const [],
  previews: '',
  type: 'scene',
  updateTime: null,
  createTime: DateTime(2024, 1, 1),
  target: 'scene.pkg',
  folder: 'C:\\wallpapers\\$id',
  size: 0,
);

/// Every filter off, so the grid shows the whole seeded library.
Map<String, Object> prefs() => {
  AppKeys.hideScene: false,
  AppKeys.hideVideo: false,
  AppKeys.hideWeb: false,
  AppKeys.hideApp: false,
  AppKeys.hideUnknown: false,
  AppKeys.hideEveryone: false,
  AppKeys.hideQuestionable: false,
  AppKeys.hideMature: false,
  AppKeys.sortType: SortType.update.index,
  AppKeys.sortAscending: true,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;

  // Out here rather than in the test body: init looks the settings folder up
  // over a method channel, and awaiting that inside testWidgets hands the wait
  // to the fake clock, which never delivers the reply. The lookup has no
  // implementation under flutter_test, so it fails and is swallowed instead of
  // reaching the real %APPDATA%.
  setUp(() async {
    SharedPreferences.setMockInitialValues(prefs());
    await StorageUtil.init();
  });

  /// Seeds the library before pumping. ContentView scans for wallpapers itself
  /// when the list is empty, which would reach for the real disk.
  Future<void> pumpGrid(WidgetTester tester, int count) async {
    container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(wallpaperListProvider.notifier).addAll([
      for (int i = 0; i < count; i++) make('$i'),
    ]);
    // Complete before the first frame, so the entrance animation stays out of
    // the way of the gestures below.
    container.read(currentStateProvider.notifier).update(RunState.complete);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: Column(children: [ContentView()])),
        ),
      ),
    );
    // ContentView defers its own library scan by a zero-length timer. It finds
    // the list already seeded and returns, but the timer has to be let run or
    // it outlives the test.
    await tester.pump(const Duration(milliseconds: 1));

    // Pins the constants above against the real layout, so a change to the
    // insets or the tile width fails here rather than as four wrong selections.
    expect(
      tester.getRect(find.byType(ImageItem).first),
      const Rect.fromLTWH(_firstLeft, _firstTop, _tile, _tile),
    );
  }

  Set<String> checkedIds() => container
      .read(wallpaperListProvider)
      .where((e) => e.checked)
      .map((e) => e.id)
      .toSet();

  /// Ids of the cells at the given positions in the grid. The grid draws the
  /// sorted list, which is not the order the wallpapers were seeded in, so the
  /// expectations below are written in cell positions rather than in ids.
  Set<String> idsAt(Iterable<int> cells) {
    final List<WallpaperInfo> order = container.read(
      filterWallpaperListProvider,
    );
    return {for (final int i in cells) order[i].id};
  }

  testWidgets('a box dragged over the grid selects what it covers', (
    tester,
  ) async {
    await pumpGrid(tester, 8);

    // Starts below the two rows of tiles, so the press lands on the grid
    // background rather than on a tile, whose own click handler would select.
    final TestGesture drag = await tester.startGesture(
      const Offset(30, 500),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();

    // Right edge stops 6px inside column 0, which only holds if the rectangle
    // is measured from the grid's padded origin rather than the viewport corner.
    // Clear of the top 60px too, or the autoscroll band would join in.
    await drag.moveTo(const Offset(200, 100));
    await tester.pump();
    expect(checkedIds(), idsAt([0, 4]));

    // Widen it into the next column.
    await drag.moveTo(const Offset(300, 100));
    await tester.pump();
    expect(checkedIds(), idsAt([0, 1, 4, 5]));

    await drag.up();
    await tester.pump();
    expect(checkedIds(), idsAt([0, 1, 4, 5]), reason: 'release keeps it');
  });

  testWidgets('two moves in one frame do not lose the later one', (
    tester,
  ) async {
    await pumpGrid(tester, 8);
    final TestGesture drag = await tester.startGesture(
      const Offset(30, 500),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();

    // A fast mouse reports twice in a frame, which is what the write coalescing
    // is there for. The selection has to end up at the last rectangle, not the
    // first: the pointer may now be still, so nothing will come along to
    // correct it.
    await drag.moveTo(const Offset(200, 100));
    await drag.moveTo(const Offset(300, 100));
    await tester.pump();

    expect(checkedIds(), idsAt([0, 1, 4, 5]));
    await drag.up();
    await tester.pump();
  });

  testWidgets('ctrl keeps what was already selected', (tester) async {
    await pumpGrid(tester, 8);
    // Top right cell, well clear of the rectangle the drag below sweeps.
    final Set<String> before = idsAt([3]);
    container
        .read(wallpaperListProvider.notifier)
        .setCheckedByIds(before, true);
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    addTearDown(() => tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft));

    final TestGesture drag = await tester.startGesture(
      const Offset(30, 500),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await drag.moveTo(_firstCentre);
    await tester.pump();

    expect(checkedIds(), {
      ...before,
      ...idsAt([0, 4]),
    }, reason: 'ctrl adds to the selection rather than replacing it');
    await drag.up();
    await tester.pump();
  });

  testWidgets('dragging into the bottom band scrolls, and stops on release', (
    tester,
  ) async {
    await pumpGrid(tester, 40);
    final ScrollableState scrollable = tester.state(find.byType(Scrollable));
    expect(scrollable.position.pixels, 0);

    final TestGesture drag = await tester.startGesture(
      _columnGap,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    // Inside the 60px autoscroll band at the bottom of the viewport.
    await drag.moveTo(const Offset(200, 570));
    // The ticker's first callback reports zero elapsed, so nothing moves until
    // the frame after it.
    await tester.pump();

    await tester.pump(const Duration(milliseconds: 100));
    final double first = scrollable.position.pixels;
    expect(first, greaterThan(0));
    final int grew = checkedIds().length;

    // Twice the elapsed time must move roughly twice as far. A fixed step per
    // tick would move the same distance, and would run at the monitor's
    // refresh rate rather than at a set speed.
    await tester.pump(const Duration(milliseconds: 200));
    final double second = scrollable.position.pixels - first;
    expect(second, closeTo(first * 2, first * 0.4));

    // The point of scrolling is to keep taking in wallpapers, so the rows that
    // came into view have to join the selection. Long enough to carry the
    // bottom edge over a 190px row boundary.
    await tester.pump(const Duration(milliseconds: 400));
    expect(checkedIds().length, greaterThan(grew));

    await drag.up();
    await tester.pump();
    final double stopped = scrollable.position.pixels;
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      scrollable.position.pixels,
      stopped,
      reason: 'the ticker must go with the drag',
    );
  });

  testWidgets('a drag that leaves the band stops scrolling', (tester) async {
    await pumpGrid(tester, 40);
    final ScrollableState scrollable = tester.state(find.byType(Scrollable));

    final TestGesture drag = await tester.startGesture(
      _columnGap,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await drag.moveTo(const Offset(200, 570));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(scrollable.position.pixels, greaterThan(0));

    await drag.moveTo(const Offset(200, 300));
    await tester.pump();
    final double parked = scrollable.position.pixels;
    await tester.pump(const Duration(milliseconds: 300));

    expect(scrollable.position.pixels, parked);
    await drag.up();
    await tester.pump();
  });
}
