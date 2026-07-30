import 'package:flutter/foundation.dart';
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

  void toggle(String id) => state = state.contains(id)
      ? (state.toSet()..remove(id))
      : (state.toSet()..add(id));

  void setAll(Set<String> ids, bool checked) {
    if (ids.isEmpty) return;
    final next = state.toSet();
    checked ? next.addAll(ids) : next.removeAll(ids);
    if (next.length != state.length) state = next;
  }

  /// Selects [ids] and nothing else. What a drag over the grid needs.
  void setExactly(Set<String> ids) {
    if (setEquals(ids, state)) return;
    state = ids.toSet();
  }

  /// What a plain left click does. Selects only [id], and clears it when it was
  /// already the only one selected, so you can deselect without aiming at the
  /// checkbox.
  void setExclusive(String id) {
    final bool only = state.length == 1 && state.contains(id);
    state = only ? const <String>{} : <String>{id};
  }

  void clear() {
    if (state.isNotEmpty) state = const <String>{};
  }

  /// Drops ids whose wallpaper is gone, so a deleted selection cannot linger.
  void forget(Set<String> ids) => setAll(ids, false);
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
