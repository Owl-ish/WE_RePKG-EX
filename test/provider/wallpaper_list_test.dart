import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:we_repkg/constants/content_rating.dart';
import 'package:we_repkg/constants/keys.dart';
import 'package:we_repkg/constants/wallpaper_type.dart';
import 'package:we_repkg/models/enums.dart';
import 'package:we_repkg/models/wallpaper.dart';
import 'package:we_repkg/provider/filter.dart';
import 'package:we_repkg/provider/system.dart';
import 'package:we_repkg/provider/wallpaper.dart';
import 'package:we_repkg/utils/storage.dart';

WallpaperInfo makeWallpaper(
  String id, {
  String? title,
  String type = WallpaperType.scene,
  String contentRating = 'everyone',
  String target = 'scene.pkg',
  int size = 0,
  int? updateTime,
  DateTime? createTime,
}) {
  return WallpaperInfo(
    id: id,
    title: title ?? 'wallpaper $id',
    contentRating: contentRating,
    tags: const [],
    previews: '',
    type: type,
    updateTime: updateTime,
    createTime: createTime ?? DateTime(2024, 1, 1),
    target: target,
    folder: 'C:\\wallpapers\\$id',
    size: size,
  );
}

/// Prefs that switch every filter off, so filterWallpaperList tests only see the
/// dimension each test sets. Without these, hideWeb and hideApp default to true.
Map<String, Object> permissivePrefs() => {
  AppKeys.hideScene: false,
  AppKeys.hideVideo: false,
  AppKeys.hideWeb: false,
  AppKeys.hideApp: false,
  AppKeys.hideUnknown: false,
  AppKeys.hideEveryone: false,
  AppKeys.hideQuestionable: false,
  AppKeys.hideMature: false,
  AppKeys.sortType: SortType.time.index,
  AppKeys.sortAscending: false,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;

  Future<void> boot([Map<String, Object>? prefs]) async {
    SharedPreferences.setMockInitialValues(prefs ?? permissivePrefs());
    await StorageUtil.init();
    container = ProviderContainer();
    addTearDown(container.dispose);
  }

  group('WallpaperList batch mutators', () {
    test('removeAll drops many wallpapers in one state write', () async {
      await boot();
      final notifier = container.read(wallpaperListProvider.notifier);
      notifier.addAll([for (int i = 0; i < 100; i++) makeWallpaper('$i')]);

      int emissions = 0;
      container.listen(wallpaperListProvider, (_, _) => emissions++);
      notifier.removeAll({for (int i = 0; i < 60; i++) '$i'});

      expect(emissions, 1);
      expect(container.read(wallpaperListProvider).length, 40);
    });

    test('removeAll with an empty set does not touch state', () async {
      await boot();
      final notifier = container.read(wallpaperListProvider.notifier);
      notifier.addAll([makeWallpaper('a')]);

      int emissions = 0;
      container.listen(wallpaperListProvider, (_, _) => emissions++);
      notifier.removeAll({});

      expect(emissions, 0);
    });
  });

  group('CheckedIds', () {
    // The whole point of holding selection apart from the library: ticking a
    // wallpaper must not rewrite two thousand elements and send
    // filterWallpaperList through a fresh filter and sort.
    test('selecting does not touch the library at all', () async {
      await boot();
      container.read(wallpaperListProvider.notifier).addAll([
        for (int i = 0; i < 200; i++) makeWallpaper('$i'),
      ]);
      final before = container.read(wallpaperListProvider);

      int libraryWrites = 0;
      container.listen(wallpaperListProvider, (_, _) => libraryWrites++);
      container.read(checkedIdsProvider.notifier).setAll({
        for (int i = 10; i < 160; i++) '$i',
      }, true);

      expect(libraryWrites, 0);
      expect(identical(container.read(wallpaperListProvider), before), isTrue);
    });

    // The filtered list is what the grid draws. Before selection moved out, a
    // tick rewrote the library and sent this through a fresh filter and sort.
    test('selecting does not rebuild the filtered list', () async {
      await boot();
      container.read(wallpaperListProvider.notifier).addAll([
        for (int i = 0; i < 200; i++) makeWallpaper('$i'),
      ]);
      final before = container.read(filterWallpaperListProvider);

      int rebuilds = 0;
      container.listen(filterWallpaperListProvider, (_, _) => rebuilds++);
      container.read(checkedIdsProvider.notifier).setAll({'7'}, true);
      await pumpEventQueue();

      expect(rebuilds, 0);
      expect(
        identical(container.read(filterWallpaperListProvider), before),
        isTrue,
        reason: 'the same list instance, not an equal one',
      );
    });

    test('setAll adds and removes', () async {
      await boot();
      final notifier = container.read(checkedIdsProvider.notifier);

      notifier.setAll({'a', 'b', 'c'}, true);
      expect(container.read(checkedIdsProvider), {'a', 'b', 'c'});

      notifier.setAll({'b'}, false);
      expect(container.read(checkedIdsProvider), {'a', 'c'});
    });

    test('an empty set does not touch state', () async {
      await boot();
      int emissions = 0;
      container.listen(checkedIdsProvider, (_, _) => emissions++);

      container.read(checkedIdsProvider.notifier).setAll({}, true);

      expect(emissions, 0);
    });

    test('toggle flips one id', () async {
      await boot();
      final notifier = container.read(checkedIdsProvider.notifier);

      notifier.toggle('a');
      expect(container.read(checkedIdsProvider), {'a'});
      notifier.toggle('a');
      expect(container.read(checkedIdsProvider), isEmpty);
    });

    group('setExclusive', () {
      test('selects one and clears the rest', () async {
        await boot();
        final notifier = container.read(checkedIdsProvider.notifier);
        notifier.setAll({'a', 'b'}, true);

        notifier.setExclusive('c');

        expect(container.read(checkedIdsProvider), {'c'});
      });

      test('clicking the only selected wallpaper clears it', () async {
        await boot();
        final notifier = container.read(checkedIdsProvider.notifier);
        notifier.setAll({'a'}, true);

        notifier.setExclusive('a');

        expect(container.read(checkedIdsProvider), isEmpty);
      });

      test('clicking one of several keeps just that one', () async {
        await boot();
        final notifier = container.read(checkedIdsProvider.notifier);
        notifier.setAll({'a', 'b'}, true);

        notifier.setExclusive('a');

        expect(
          container.read(checkedIdsProvider),
          {'a'},
          reason: 'replaces the range, does not clear',
        );
      });
    });

    // A drag reports a rectangle a frame; repeating one must write nothing.
    test('setExactly ignores a repeat of the same set', () async {
      await boot();
      final notifier = container.read(checkedIdsProvider.notifier);
      notifier.setExactly({'a', 'b'});

      int emissions = 0;
      container.listen(checkedIdsProvider, (_, _) => emissions++);
      notifier.setExactly({'b', 'a'});

      expect(emissions, 0);
      expect(container.read(checkedIdsProvider), {'a', 'b'});
    });

    test('setExactly replaces rather than adds', () async {
      await boot();
      final notifier = container.read(checkedIdsProvider.notifier);
      notifier.setAll({'a', 'b'}, true);

      notifier.setExactly({'c'});

      expect(container.read(checkedIdsProvider), {'c'});
    });
  });

  group('filterWallpaperList filtering', () {
    test('each rating toggle hides only its own level', () async {
      final cases = <String, String>{
        AppKeys.hideEveryone: ContentRating.everyone,
        AppKeys.hideQuestionable: ContentRating.questionable,
        AppKeys.hideMature: ContentRating.mature,
      };
      for (final entry in cases.entries) {
        await boot({...permissivePrefs(), entry.key: true});
        container.read(wallpaperListProvider.notifier).addAll([
          for (final rating in cases.values)
            makeWallpaper(rating, contentRating: rating),
        ]);

        final ratings = container
            .read(filterWallpaperListProvider)
            .map((e) => e.contentRating)
            .toSet();
        expect(
          ratings.contains(entry.value),
          isFalse,
          reason: '${entry.key} should hide ${entry.value}',
        );
        expect(ratings.length, cases.length - 1, reason: entry.key);
      }
    });

    test('an unrecognised rating counts as all ages', () async {
      // A project.json can carry a rating the app doesn't know, or none at all.
      // Those must follow the all-ages box, otherwise they'd be unreachable
      // with every box ticked.
      await boot();
      container.read(wallpaperListProvider.notifier).addAll([
        makeWallpaper('blank', contentRating: ''),
        makeWallpaper('odd', contentRating: 'pg13'),
      ]);
      expect(container.read(filterWallpaperListProvider).length, 2);

      await boot({...permissivePrefs(), AppKeys.hideEveryone: true});
      container.read(wallpaperListProvider.notifier).addAll([
        makeWallpaper('blank', contentRating: ''),
        makeWallpaper('odd', contentRating: 'pg13'),
      ]);
      expect(container.read(filterWallpaperListProvider), isEmpty);
    });

    test('search matches titles case-insensitively', () async {
      await boot();
      container.read(wallpaperListProvider.notifier).addAll([
        makeWallpaper('1', title: 'Neon City'),
        makeWallpaper('2', title: 'forest stream'),
      ]);
      container.read(searchContentProvider.notifier).update('NEON');

      final ids = container.read(filterWallpaperListProvider).map((e) => e.id);
      expect(ids, ['1']);
    });

    test(
      'wallpapers with no extractable file are never filtered out',
      () async {
        // They used to hide behind the "Show all wallpapers" box. That box is
        // gone: extractBranch copies the whole folder for them, so there is
        // nothing for the user to opt into.
        await boot();
        container.read(wallpaperListProvider.notifier).addAll([
          makeWallpaper('has', target: 'scene.pkg'),
          makeWallpaper('none', target: ''),
        ]);

        final ids = container
            .read(filterWallpaperListProvider)
            .map((e) => e.id);
        expect(ids, ['has', 'none']);
      },
    );

    test('each type toggle hides only its own type', () async {
      final cases = <String, String>{
        AppKeys.hideScene: WallpaperType.scene,
        AppKeys.hideVideo: WallpaperType.video,
        AppKeys.hideWeb: WallpaperType.web,
        AppKeys.hideApp: WallpaperType.application,
        AppKeys.hideUnknown: WallpaperType.unknown,
      };
      for (final entry in cases.entries) {
        await boot({...permissivePrefs(), entry.key: true});
        container.read(wallpaperListProvider.notifier).addAll([
          for (final type in cases.values) makeWallpaper(type, type: type),
        ]);

        final types = container
            .read(filterWallpaperListProvider)
            .map((e) => e.type)
            .toSet();
        expect(
          types.contains(entry.value),
          isFalse,
          reason: '${entry.key} should hide ${entry.value}',
        );
        expect(types.length, cases.length - 1, reason: entry.key);
      }
    });

    test('filters combine as AND', () async {
      await boot({
        ...permissivePrefs(),
        AppKeys.hideVideo: true,
        AppKeys.hideMature: true,
      });
      container.read(wallpaperListProvider.notifier).addAll([
        makeWallpaper('keep', type: WallpaperType.scene),
        makeWallpaper('byType', type: WallpaperType.video),
        makeWallpaper('byRating', contentRating: ContentRating.mature),
      ]);

      final ids = container.read(filterWallpaperListProvider).map((e) => e.id);
      expect(ids, ['keep']);
    });
  });

  group('reset filters', () {
    test('clears every type and rating box in one go', () async {
      await boot();
      final notifier = container.read(filterStateProvider.notifier);
      notifier.updateHideScene(true);
      notifier.updateHideWeb(true);
      notifier.updateHideMature(true);
      expect(container.read(filterStateProvider).nothingHidden, isFalse);

      notifier.reset();

      expect(container.read(filterStateProvider).nothingHidden, isTrue);
    });

    test('persists, so the boxes stay on after a restart', () async {
      await boot();
      container.read(filterStateProvider.notifier).updateHideVideo(true);
      container.read(filterStateProvider.notifier).reset();
      await Future<void>.delayed(Duration.zero);

      final reread = ProviderContainer();
      addTearDown(reread.dispose);
      expect(reread.read(filterStateProvider).nothingHidden, isTrue);
    });

    test('a fresh install hides nothing', () async {
      // hideWeb and hideApp used to default to true, from when those types
      // could not be extracted. Every type is visible until the user says
      // otherwise.
      await boot({AppKeys.sortType: SortType.time.index});

      expect(container.read(filterStateProvider).nothingHidden, isTrue);
    });
  });

  group('age rating migration from the pre-1.6 matureState', () {
    /// Prefs as they looked before the three rating flags existed.
    Map<String, Object> legacyPrefs(int matureState) => {
      // 'showAll' was also stored back then. Nothing reads it any more, so the
      // orphaned pref is left alone rather than migrated.
      'showAll': true,
      AppKeys.hideScene: false,
      AppKeys.hideVideo: false,
      AppKeys.hideWeb: false,
      AppKeys.hideApp: false,
      AppKeys.hideUnknown: false,
      AppKeys.matureState: matureState,
      AppKeys.sortType: SortType.time.index,
      AppKeys.sortAscending: false,
    };

    test('matureState 1 (hide) seeds hideMature alone', () async {
      await boot(legacyPrefs(1));
      final filter = container.read(filterStateProvider);
      expect(filter.hideMature, isTrue);
      expect(filter.hideQuestionable, isFalse);
      expect(filter.hideEveryone, isFalse);
    });

    test('matureState 2 (only) seeds the two milder levels', () async {
      await boot(legacyPrefs(2));
      final filter = container.read(filterStateProvider);
      expect(filter.hideMature, isFalse);
      expect(filter.hideQuestionable, isTrue);
      expect(filter.hideEveryone, isTrue);
    });

    test(
      'the seed is persisted, so a later single write cannot reset it',
      () async {
        // Deriving the flags on every load instead would break here: writing
        // hideEveryone alone would make the next launch look migrated while
        // hideMature silently fell back to false.
        await boot(legacyPrefs(1));
        container.read(filterStateProvider.notifier).updateHideEveryone(true);
        await Future<void>.delayed(Duration.zero);

        final reread = ProviderContainer();
        addTearDown(reread.dispose);
        final filter = reread.read(filterStateProvider);
        expect(filter.hideMature, isTrue);
        expect(filter.hideEveryone, isTrue);
      },
    );
  });

  group('filterWallpaperList sorting', () {
    test('size sorts descending', () async {
      await boot({...permissivePrefs(), AppKeys.sortType: SortType.size.index});
      container.read(wallpaperListProvider.notifier).addAll([
        makeWallpaper('small', size: 1),
        makeWallpaper('big', size: 100),
        makeWallpaper('mid', size: 50),
      ]);

      final ids = container.read(filterWallpaperListProvider).map((e) => e.id);
      expect(ids, ['big', 'mid', 'small']);
    });

    test('sortAscending reverses the order', () async {
      await boot({
        ...permissivePrefs(),
        AppKeys.sortType: SortType.size.index,
        AppKeys.sortAscending: true,
      });
      container.read(wallpaperListProvider.notifier).addAll([
        makeWallpaper('small', size: 1),
        makeWallpaper('big', size: 100),
      ]);

      final ids = container.read(filterWallpaperListProvider).map((e) => e.id);
      expect(ids, ['small', 'big']);
    });

    test('update sorts newest first', () async {
      await boot({
        ...permissivePrefs(),
        AppKeys.sortType: SortType.update.index,
      });
      container.read(wallpaperListProvider.notifier).addAll([
        makeWallpaper('old', updateTime: 1000),
        makeWallpaper('new', updateTime: 9000),
      ]);

      final ids = container.read(filterWallpaperListProvider).map((e) => e.id);
      expect(ids, ['new', 'old']);
    });

    // A wallpaper missing from the ACF has no updateTime, which is the norm for
    // anything self-made. Comparing those as equal to everything makes the
    // comparator intransitive, and Dart's sort then misplaces the dated items
    // too, so the damage is not confined to the undated ones.
    test(
      'update sort keeps dates in order around undated wallpapers',
      () async {
        await boot({
          ...permissivePrefs(),
          AppKeys.sortType: SortType.update.index,
        });
        container.read(wallpaperListProvider.notifier).addAll([
          makeWallpaper('a', updateTime: 500),
          makeWallpaper('undated1', updateTime: null),
          makeWallpaper('b', updateTime: 9000),
          makeWallpaper('c', updateTime: 100),
          makeWallpaper('undated2', updateTime: null),
          makeWallpaper('d', updateTime: 7000),
        ]);

        final list = container.read(filterWallpaperListProvider);
        final dated = list
            .where((e) => e.updateTime != null)
            .map((e) => e.updateTime!)
            .toList();

        expect(dated, [9000, 7000, 500, 100], reason: 'newest first');
        expect(
          list.sublist(list.length - 2).every((e) => e.updateTime == null),
          isTrue,
          reason: 'undated wallpapers belong at the end, not scattered',
        );
      },
    );

    test('time sort pushes the earliest import day to the end', () async {
      // The bulk first import all shares one createTime day; newer additions
      // belong on top, and the bulk day sorts ascending behind them.
      await boot({...permissivePrefs(), AppKeys.sortType: SortType.time.index});
      final bulkDay = DateTime(2023, 5, 1);
      container.read(wallpaperListProvider.notifier).addAll([
        makeWallpaper(
          'bulkA',
          createTime: bulkDay.add(const Duration(hours: 1)),
        ),
        makeWallpaper(
          'bulkB',
          createTime: bulkDay.add(const Duration(hours: 2)),
        ),
        makeWallpaper('newer', createTime: DateTime(2024, 2, 2)),
        makeWallpaper('newest', createTime: DateTime(2024, 8, 8)),
      ]);
      container.read(earliestTimeProvider.notifier).update('2023-05-01');

      final ids = container.read(filterWallpaperListProvider).map((e) => e.id);
      expect(ids, ['newest', 'newer', 'bulkA', 'bulkB']);
    });

    test(
      'time sort without an earliest date just sorts newest first',
      () async {
        await boot({
          ...permissivePrefs(),
          AppKeys.sortType: SortType.time.index,
        });
        container.read(wallpaperListProvider.notifier).addAll([
          makeWallpaper('a', createTime: DateTime(2023, 1, 1)),
          makeWallpaper('c', createTime: DateTime(2025, 1, 1)),
          makeWallpaper('b', createTime: DateTime(2024, 1, 1)),
        ]);

        final ids = container
            .read(filterWallpaperListProvider)
            .map((e) => e.id);
        expect(ids, ['c', 'b', 'a']);
      },
    );

    test('sorting does not mutate the underlying provider list', () async {
      await boot({...permissivePrefs(), AppKeys.sortType: SortType.size.index});
      container.read(wallpaperListProvider.notifier).addAll([
        makeWallpaper('small', size: 1),
        makeWallpaper('big', size: 100),
      ]);

      container.read(filterWallpaperListProvider);
      final rawIds = container.read(wallpaperListProvider).map((e) => e.id);
      expect(rawIds, ['small', 'big'], reason: 'insertion order must survive');
    });
  });

  group('checkedWallpaperList', () {
    test('reports only selected wallpapers that pass the filter', () async {
      await boot();
      container.read(wallpaperListProvider.notifier).addAll([
        makeWallpaper('a', type: WallpaperType.scene),
        makeWallpaper('b', type: WallpaperType.video),
        makeWallpaper('c', type: WallpaperType.scene),
      ]);
      container.read(checkedIdsProvider.notifier).setAll({'a', 'b'}, true);
      container.read(filterStateProvider.notifier).updateHideVideo(true);

      final ids = container.read(checkedWallpaperListProvider).map((e) => e.id);
      expect(ids, ['a']);
    });

    test('a range selection emits one checked-list update', () async {
      await boot();
      final notifier = container.read(wallpaperListProvider.notifier);
      notifier.addAll([for (int i = 0; i < 80; i++) makeWallpaper('$i')]);
      // Force the derived providers to build so later writes are observable.
      container.read(checkedWallpaperListProvider);

      int emissions = 0;
      container.listen(checkedWallpaperListProvider, (_, _) => emissions++);
      container.read(checkedIdsProvider.notifier).setAll({
        for (int i = 0; i < 40; i++) '$i',
      }, true);
      // Riverpod marks dependents dirty and notifies on a later microtask, so
      // the count is only meaningful after draining the queue.
      await pumpEventQueue();

      expect(
        emissions,
        1,
        reason: 'selecting 40 items must recompute the checked list once',
      );
      expect(container.read(checkedWallpaperListProvider).length, 40);
    });
  });
}
