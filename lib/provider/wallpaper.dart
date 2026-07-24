import 'package:riverpod_annotation/riverpod_annotation.dart';
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

  /// Drops every wallpaper whose id is in [ids] in a single state write, rather
  /// than one full-list rebuild per id.
  void removeAll(Set<String> ids) {
    if (ids.isEmpty) return;
    state = state.where((e) => !ids.contains(e.id)).toList();
  }

  void clear() => state = [];

  /// Flips the stored element's selection.
  ///
  /// Reads `checked` off the element held in state, not off [value]. Callers can
  /// hand back a stale instance (a captured closure, a list snapshot taken
  /// before the last rebuild), and `==` compares ids only, so a stale copy looks
  /// current. Trusting it would both flip the wrong way and overwrite the stored
  /// element's other fields with stale values.
  void toggleChecked(WallpaperInfo value) => state = [
    for (final e in state)
      e.id == value.id ? e.copyWith(checked: !e.checked) : e,
  ];

  void updateChecked(WallpaperInfo value, bool checked) =>
      setCheckedByIds({value.id}, checked);

  /// Sets selection for every id in [ids] in one state write.
  ///
  /// The loop that this replaces called a single-item mutator per wallpaper, so
  /// selecting a range of M items over a library of N rebuilt the whole list M
  /// times and drove M filter-and-sort passes through filterWallpaperList. This
  /// is one O(N) pass regardless of M.
  void setCheckedByIds(Set<String> ids, bool checked) {
    if (ids.isEmpty) return;
    state = [
      for (final e in state)
        ids.contains(e.id) && e.checked != checked
            ? e.copyWith(checked: checked)
            : e,
    ];
  }

  /// Clears selection across the entire library, including wallpapers the
  /// current filter hides.
  void clearAllChecked() {
    // Skip the state write when nothing is selected: an identical new list would
    // still invalidate filterWallpaperList and rebuild the grid for no reason.
    if (!state.any((e) => e.checked)) return;
    state = [for (final e in state) e.checked ? e.copyWith(checked: false) : e];
  }
}

@Riverpod(keepAlive: true)
class HoverWallpaper extends _$HoverWallpaper {
  @override
  WallpaperInfo? build() => null;
  void update(WallpaperInfo? value) => state = value;
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
  final MatureState matureState = filter.matureState;
  final bool showAll = filter.showAll;
  final bool hideScene = filter.hideScene;
  final bool hideVideo = filter.hideVideo;
  final bool hideWeb = filter.hideWeb;
  final bool hideApp = filter.hideApp;
  final bool hideUnknown = filter.hideUnknown;
  final SortType sortType = ref.watch(wallpaperSortTypeProvider);
  final bool sortAscending = ref.watch(sortAscendingProvider);

  // Combine all filters into a single pass (was multiple .where calls, each
  // allocating an intermediate list). All conditions are pure ANDs, so this is
  // equivalent to the original; the .toList() always copies, preventing the
  // later sort from mutating the provider's own stored list.
  final String keyWordLower = keyWord.toLowerCase();
  list = list.where((e) {
    // mature content rating
    if (matureState == MatureState.hide && e.contentRating == 'mature') {
      return false;
    }
    if (matureState == MatureState.only && e.contentRating != 'mature') {
      return false;
    }
    // search keyword (case-insensitive)
    if (keyWordLower.isNotEmpty &&
        !e.title.toLowerCase().contains(keyWordLower)) {
      return false;
    }
    // only show wallpapers with an extractable file
    if (!showAll && e.target.isEmpty) return false;
    // type filters
    if (hideScene && e.type == WallpaperType.scene) return false;
    if (hideVideo && e.type == WallpaperType.video) return false;
    if (hideWeb && e.type == WallpaperType.web) return false;
    if (hideApp && e.type == WallpaperType.application) return false;
    if (hideUnknown && e.type == WallpaperType.unknown) return false;
    return true;
  }).toList();
  switch (sortType) {
    case SortType.time:
      // Group wallpapers created on the library's earliest day (the bulk first
      // import) and push them to the end; newer additions show on top.
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
      list.sort((a, b) {
        if (a.updateTime == null || b.updateTime == null) return 0;
        return b.updateTime!.compareTo(a.updateTime!);
      });
      break;
  }
  if (sortAscending) list = list.reversed.toList();
  return list;
}

@Riverpod(keepAlive: true)
class ExtractList extends _$ExtractList {
  @override
  List<WallpaperInfo> build() => [];
  void addAll(List<WallpaperInfo> value) => state = [...value];
  void clear() => state = [];
}

/// How many wallpapers in the current batch have finished. Ranges 0..total.
///
/// This used to be the index of the item being worked on, which only made sense
/// while extraction was sequential. With several wallpapers in flight there is
/// no single current index, and completions arrive out of order, so the loading
/// view counts finishes instead of tracking a cursor.
@Riverpod(keepAlive: true)
class CurrentIndex extends _$CurrentIndex {
  @override
  int build() => 0;
  void update(int value) => state = value;
  void reset() => state = 0;
  void increment() => state = state + 1;
}

/// The wallpaper a worker most recently picked up, for the loading preview.
///
/// Separate from [CurrentIndex] on purpose: driving the preview off the progress
/// count would index past the end of the list as the final item completes.
@Riverpod(keepAlive: true)
class ProcessingWallpaper extends _$ProcessingWallpaper {
  @override
  WallpaperInfo? build() => null;
  void update(WallpaperInfo? value) => state = value;
}
