import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:we_repkg/constants/content_rating.dart';
import 'package:we_repkg/constants/wallpaper_type.dart';
import 'package:we_repkg/models/enums.dart';
import 'package:we_repkg/models/filter.dart';
import 'package:we_repkg/models/wallpaper.dart';
import 'package:we_repkg/provider/setting.dart';

import 'filter.dart';
import 'system.dart';

part 'wallpaper.g.dart';

@Riverpod(keepAlive: true)
class WallpaperList extends _$WallpaperList {
  @override
  List<WallpaperInfo> build() => [];
  void add(WallpaperInfo value) => state = [...state, value];

  void addAll(List<WallpaperInfo> value) => state = [...state, ...value];

  void remove(WallpaperInfo value) => removeAll({value.id});

  /// One state write, not one per id.
  void removeAll(Set<String> ids) {
    if (ids.isEmpty) return;
    state = state.where((e) => !ids.contains(e.id)).toList();
  }

  void clear() => state = [];

  /// Reads `checked` off the stored element, not off [value]. Callers can pass
  /// a stale instance, and `==` compares ids only, so a stale copy looks
  /// current and would flip the wrong way.
  void toggleChecked(WallpaperInfo value) => state = [
    for (final e in state)
      e.id == value.id ? e.copyWith(checked: !e.checked) : e,
  ];

  void updateChecked(WallpaperInfo value, bool checked) =>
      setCheckedByIds({value.id}, checked);

  /// One O(N) pass however many ids there are. Doing it per id costs a full
  /// filter-and-sort through filterWallpaperList each time.
  void setCheckedByIds(Set<String> ids, bool checked) {
    if (ids.isEmpty) return;
    state = [
      for (final e in state)
        ids.contains(e.id) && e.checked != checked
            ? e.copyWith(checked: checked)
            : e,
    ];
  }

  /// Selects [ids] and deselects everything else, in one pass. What a drag over
  /// the grid needs; a clear plus a set would rebuild the list twice a frame.
  void setCheckedExactly(Set<String> ids) {
    state = [
      for (final e in state)
        if (ids.contains(e.id) == e.checked)
          e
        else
          e.copyWith(checked: !e.checked),
    ];
  }

  /// What a plain left click does. Selects only [id], and clears it if it was
  /// already the only one selected, so you can deselect without aiming at the
  /// checkbox.
  void setExclusiveChecked(String id) {
    int checkedCount = 0;
    bool targetChecked = false;
    for (final e in state) {
      if (e.checked) checkedCount++;
      if (e.id == id) targetChecked = e.checked;
    }
    final bool select = !(targetChecked && checkedCount == 1);
    state = [
      for (final e in state)
        if (e.id == id)
          (e.checked == select ? e : e.copyWith(checked: select))
        else
          (e.checked ? e.copyWith(checked: false) : e),
    ];
  }
}

@Riverpod(keepAlive: true)
class SelectedWallpaper extends _$SelectedWallpaper {
  @override
  WallpaperInfo? build() => null;
  void update(WallpaperInfo? value) => state = value;
}

@riverpod
List<WallpaperInfo> checkedWallpaperList(Ref ref) =>
    ref.watch(filterWallpaperListProvider).where((e) => e.checked).toList();

@riverpod
List<WallpaperInfo> filterWallpaperList(Ref ref) {
  List<WallpaperInfo> list = ref.watch(wallpaperListProvider);
  String keyWord = ref.watch(searchContentProvider);
  final WallpaperFilter filter = ref.watch(filterStateProvider);
  final bool hideScene = filter.hideScene;
  final bool hideVideo = filter.hideVideo;
  final bool hideWeb = filter.hideWeb;
  final bool hideApp = filter.hideApp;
  final bool hideUnknown = filter.hideUnknown;
  final bool hideEveryone = filter.hideEveryone;
  final bool hideQuestionable = filter.hideQuestionable;
  final bool hideMature = filter.hideMature;
  final SortType sortType = ref.watch(wallpaperSortTypeProvider);
  final bool sortAscending = ref.watch(sortAscendingProvider);

  // One pass for every filter. toList copies, so the sort below cannot mutate
  // the provider's own list.
  final String keyWordLower = keyWord.toLowerCase();
  list = list.where((e) {
    // Anything not mature or questionable counts as all ages, so a wallpaper
    // with a missing or unknown rating cannot hide from all three checkboxes.
    if (e.contentRating == ContentRating.mature) {
      if (hideMature) return false;
    } else if (e.contentRating == ContentRating.questionable) {
      if (hideQuestionable) return false;
    } else if (hideEveryone) {
      return false;
    }
    if (keyWordLower.isNotEmpty &&
        !e.title.toLowerCase().contains(keyWordLower)) {
      return false;
    }
    // Wallpapers with no extractable file stay in the list; extractBranch
    // falls through to copying the whole folder.
    if (hideScene && e.type == WallpaperType.scene) return false;
    if (hideVideo && e.type == WallpaperType.video) return false;
    if (hideWeb && e.type == WallpaperType.web) return false;
    if (hideApp && e.type == WallpaperType.application) return false;
    if (hideUnknown && e.type == WallpaperType.unknown) return false;
    return true;
  }).toList();
  switch (sortType) {
    case SortType.time:
      // Everything from the library's earliest day is the bulk first import,
      // so push it to the end and show newer additions on top.
      final String? earliest = ref.watch(earliestTimeProvider);
      final DateTime? earliestDay = (earliest == null || earliest.isEmpty)
          ? null
          : DateTime.tryParse(earliest);
      List<WallpaperInfo> earliestList = [];
      List<WallpaperInfo> otherList = [];
      for (WallpaperInfo wallpaper in list) {
        final c = wallpaper.createTime;
        final bool onEarliestDay =
            earliestDay != null &&
            c.year == earliestDay.year &&
            c.month == earliestDay.month &&
            c.day == earliestDay.day;
        if (onEarliestDay) {
          earliestList.add(wallpaper);
        } else {
          otherList.add(wallpaper);
        }
      }
      earliestList.sort((a, b) => a.createTime.compareTo(b.createTime));
      otherList.sort((a, b) => b.createTime.compareTo(a.createTime));
      list = [...otherList, ...earliestList];
      break;
    case SortType.size:
      list.sort((a, b) => b.size.compareTo(a.size));
      break;
    case SortType.update:
      // Undated last. Comparing them equal to everything makes the comparator
      // intransitive, and the sort then misplaces the dated items as well.
      list.sort((a, b) {
        final int? x = a.updateTime, y = b.updateTime;
        if (x == null) return y == null ? 0 : 1;
        if (y == null) return -1;
        return y.compareTo(x);
      });
      break;
  }
  if (sortAscending) list = list.reversed.toList();
  return list;
}

/// How many wallpapers in the batch have finished, 0..total. A count, not a
/// cursor: with several in flight, completions arrive out of order.
@Riverpod(keepAlive: true)
class CurrentIndex extends _$CurrentIndex {
  @override
  int build() => 0;
  void update(int value) => state = value;
  void reset() => state = 0;
  void increment() => state = state + 1;
}

/// The wallpaper a worker most recently picked up, for the loading preview.
/// Separate from [CurrentIndex], which would index past the end of the list as
/// the last item completes.
@Riverpod(keepAlive: true)
class ProcessingWallpaper extends _$ProcessingWallpaper {
  @override
  WallpaperInfo? build() => null;
  void update(WallpaperInfo? value) => state = value;
}
