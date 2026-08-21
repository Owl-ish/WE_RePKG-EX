import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:we_repkg/models/enums.dart';
import 'package:we_repkg/models/filter.dart';
import 'package:we_repkg/models/wallpaper.dart';
import 'package:we_repkg/provider/setting.dart';
import 'package:we_repkg/utils/wallpaper_filter.dart';
import 'package:we_repkg/utils/wallpaper_search.dart';

import 'filter.dart';
import 'system.dart';

part 'wallpaper.g.dart';

@Riverpod(keepAlive: true)
class WallpaperList extends _$WallpaperList {
  @override
  List<WallpaperInfo> build() => [];

  void addAll(List<WallpaperInfo> value) => state = [...state, ...value];

  void remove(WallpaperInfo value) => removeAll({value.id});

  /// One state write, not one per id.
  void removeAll(Set<String> ids) {
    if (ids.isEmpty) return;
    state = state.where((e) => !ids.contains(e.id)).toList();
  }

  void clear() => state = [];
}

/// Which wallpapers are selected, by id.
///
/// Held apart from the library so ticking one does not rewrite two thousand
/// elements and send filterWallpaperList through a fresh filter and sort. Ids
/// rather than objects, so nothing here can hold a stale copy of a wallpaper.
@Riverpod(keepAlive: true)
class CheckedIds extends _$CheckedIds {
  @override
  Set<String> build() => const <String>{};

  /// Which wallpaper a Shift range reaches back to. Store the id rather than
  /// the visible index so sorting and filtering cannot move the anchor.
  String? shiftAnchor;

  void toggle(String id) {
    shiftAnchor = id;
    state = state.contains(id)
        ? (state.toSet()..remove(id))
        : (state.toSet()..add(id));
  }

  void setAll(Set<String> ids, bool checked) {
    if (ids.isEmpty) return;
    final next = state.toSet();
    checked ? next.addAll(ids) : next.removeAll(ids);
    if (next.length != state.length) state = next;
  }

  /// Selects [ids] and nothing else. What a drag over the grid needs.
  void setExactly(Set<String> ids) {
    if (ids.isEmpty) shiftAnchor = null;
    if (setEquals(ids, state)) return;
    state = ids.toSet();
  }

  /// What a plain left click does. Selects only [id], and clears it when it was
  /// already the only one selected, so a tile can be put down by clicking it
  /// again rather than by aiming at anything small.
  void setExclusive(String id) {
    final bool only = state.length == 1 && state.contains(id);
    state = only ? const <String>{} : <String>{id};
    shiftAnchor = state.isEmpty ? null : id;
  }

  void clear() {
    shiftAnchor = null;
    if (state.isNotEmpty) state = const <String>{};
  }

  /// Drops ids whose wallpaper is gone, so a deleted selection cannot linger.
  void forget(Set<String> ids) {
    if (shiftAnchor != null && ids.contains(shiftAnchor)) shiftAnchor = null;
    setAll(ids, false);
  }
}

@Riverpod(keepAlive: true)
class SelectedWallpaper extends _$SelectedWallpaper {
  @override
  WallpaperInfo? build() => null;
  void update(WallpaperInfo? value) => state = value;
}

@riverpod
List<WallpaperInfo> checkedWallpaperList(Ref ref) {
  final Set<String> checked = ref.watch(checkedIdsProvider);
  if (checked.isEmpty) return const <WallpaperInfo>[];
  return ref
      .watch(filterWallpaperListProvider)
      .where((e) => checked.contains(e.id))
      .toList();
}

@riverpod
List<WallpaperInfo> filterWallpaperList(Ref ref) {
  List<WallpaperInfo> list = ref.watch(wallpaperListProvider);
  String keyWord = ref.watch(searchContentProvider);
  final WallpaperFilter filter = ref.watch(filterStateProvider);
  final SortType sortType = ref.watch(wallpaperSortTypeProvider);
  final bool sortAscending = ref.watch(sortAscendingProvider);

  // One pass for every filter. toList copies, so the sort below cannot mutate
  // the provider's own list.
  final String keyWordLower = keyWord.toLowerCase();
  list = list.where((e) {
    if (!matchesSearch(title: e.title, id: e.id, needle: keyWordLower)) {
      return false;
    }
    return passesWallpaperFilter(
      type: e.type,
      rating: e.contentRating,
      filter: filter,
    );
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
