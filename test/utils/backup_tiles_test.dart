import 'package:flutter_test/flutter_test.dart';
import 'package:we_repkg/models/enums.dart';
import 'package:we_repkg/models/filter.dart';
import 'package:we_repkg/utils/backup_diff.dart';
import 'package:we_repkg/utils/backup_tiles.dart';

WallpaperFilter filterOf({
  bool hideScene = false,
  bool hideVideo = false,
  bool hideMature = false,
  bool hideEveryone = false,
}) => WallpaperFilter(
  hideScene: hideScene,
  hideVideo: hideVideo,
  hideWeb: false,
  hideApp: false,
  hideUnknown: false,
  hideEveryone: hideEveryone,
  hideQuestionable: false,
  hideMature: hideMature,
);

CardFace faceOf({
  String title = '',
  String type = '',
  String rating = '',
  DateTime? modified,
}) =>
    (title: title, preview: '', type: type, rating: rating, modified: modified);

BackupTile tileOf(
  String name, {
  BackupState state = BackupState.synced,
  WallpaperLibrary library = WallpaperLibrary.workshop,
  CardFace? face,
}) => (card: BackupCard(library, name), state: state, face: face);

/// Everything showing, which is what a test that is not about the pills wants.
final Set<BackupState> allStates = BackupState.values.toSet();

List<String> namesOf(List<BackupTile> tiles) =>
    tiles.map((BackupTile t) => t.card.name).toList();

List<BackupTile> visible(
  List<BackupTile> tiles, {
  Set<BackupState>? states,
  String needle = '',
  WallpaperFilter? filter,
  BackupSortType sort = BackupSortType.state,
  bool ascending = false,
}) => visibleBackupTiles(
  tiles: tiles,
  states: states ?? allStates,
  needle: needle,
  filter: filter ?? filterOf(),
  sort: sort,
  ascending: ascending,
);

void main() {
  group('the state pills', () {
    test('a state that is not lit is not drawn', () {
      final List<BackupTile> tiles = <BackupTile>[
        tileOf('gone', state: BackupState.vanished),
        tileOf('safe', state: BackupState.synced),
      ];

      final List<BackupTile> shown = visible(
        tiles,
        states: <BackupState>{BackupState.vanished},
      );

      expect(namesOf(shown), <String>['gone']);
    });

    // Emptied on purpose. Showing everything instead would make the last click
    // do the opposite of the five before it.
    test('no pills lit shows nothing', () {
      final List<BackupTile> shown = visible(<BackupTile>[
        tileOf('safe'),
      ], states: const <BackupState>{});

      expect(shown, isEmpty);
    });
  });

  group('the search box', () {
    test('matches the title or the folder name', () {
      final List<BackupTile> tiles = <BackupTile>[
        tileOf('793602574', face: faceOf(title: 'Neon City')),
        tileOf('833227004', face: faceOf(title: 'Forest stream')),
      ];

      expect(namesOf(visible(tiles, needle: 'neon')), <String>['793602574']);
      expect(namesOf(visible(tiles, needle: '8332')), <String>['833227004']);
    });

    // No title to match on, and one of the ones most worth finding. The needle
    // arrives lowercased; the folder name is what gets folded here.
    test('a card with no face is still found by its folder', () {
      final List<BackupTile> tiles = <BackupTile>[tileOf('Alpha')];

      expect(namesOf(visible(tiles, needle: 'alph')), <String>['Alpha']);
    });
  });

  group('the filter button', () {
    test('hides by type and by age rating', () {
      final List<BackupTile> tiles = <BackupTile>[
        tileOf('scene', face: faceOf(type: 'scene')),
        tileOf('video', face: faceOf(type: 'video')),
        tileOf(
          'adult',
          face: faceOf(type: 'video', rating: 'mature'),
        ),
      ];

      expect(
        namesOf(visible(tiles, filter: filterOf(hideScene: true))),
        <String>['adult', 'video'],
      );
      expect(
        namesOf(visible(tiles, filter: filterOf(hideMature: true))),
        <String>['scene', 'video'],
      );
    });

    // The extract grid reads the same folder as unknown and all ages, so both
    // tabs have to put it in the same place.
    test('a card with no face reads as unknown and all ages', () {
      final List<BackupTile> tiles = <BackupTile>[tileOf('alpha')];

      expect(visible(tiles, filter: filterOf(hideScene: true)), hasLength(1));
      expect(visible(tiles, filter: filterOf(hideEveryone: true)), isEmpty);
    });
  });

  group('the order', () {
    final DateTime old = DateTime(2024);
    final DateTime recent = DateTime(2026);

    List<BackupTile> tiles() => <BackupTile>[
      tileOf(
        'beta',
        state: BackupState.synced,
        face: faceOf(modified: recent),
      ),
      tileOf(
        'alpha',
        state: BackupState.vanished,
        face: faceOf(modified: old),
      ),
    ];

    test('by state puts the worst first', () {
      expect(namesOf(visible(tiles())), <String>['alpha', 'beta']);
    });

    test('by name ignores the state', () {
      expect(namesOf(visible(tiles(), sort: BackupSortType.name)), <String>[
        'alpha',
        'beta',
      ]);
    });

    test('by date puts the newest first', () {
      expect(namesOf(visible(tiles(), sort: BackupSortType.date)), <String>[
        'beta',
        'alpha',
      ]);
    });

    test('the toggle runs the order the other way', () {
      expect(namesOf(visible(tiles(), ascending: true)), <String>[
        'beta',
        'alpha',
      ]);
    });

    // Comparing undated equal to everything would make the comparator
    // intransitive and misplace the dated ones too.
    test('undated cards sort last', () {
      final List<BackupTile> tiles = <BackupTile>[
        tileOf('nothing'),
        tileOf('dated', face: faceOf(modified: old)),
      ];

      expect(namesOf(visible(tiles, sort: BackupSortType.date)), <String>[
        'dated',
        'nothing',
      ]);
    });

    // Shift-click and the marquee index into these positions, so a tie cannot
    // swap places between refreshes. Fed in the wrong order deliberately: a
    // comparator returning 0 would leave a two-element list alone and pass.
    test('a tie breaks on name then library', () {
      final List<BackupTile> tiles = <BackupTile>[
        tileOf('alpha'),
        tileOf('alpha', library: WallpaperLibrary.myProjects),
      ];

      expect(
        visible(tiles).map((BackupTile t) => t.card.library),
        <WallpaperLibrary>[
          WallpaperLibrary.myProjects,
          WallpaperLibrary.workshop,
        ],
      );
    });

    // Ties are the one thing the toggle must not reverse, or the list stops
    // holding still exactly when it is running the other way.
    test('the toggle leaves a tie alone', () {
      final List<BackupTile> tiles = <BackupTile>[
        tileOf('alpha'),
        tileOf('alpha', library: WallpaperLibrary.myProjects),
      ];

      expect(
        visible(tiles, ascending: true).map((BackupTile t) => t.card.library),
        <WallpaperLibrary>[
          WallpaperLibrary.myProjects,
          WallpaperLibrary.workshop,
        ],
      );
    });

    // A reconcile tile can stand for a live copy in each library.
    test('a reconcile tile sorts by the worst of its live states', () {
      ReconcileTile entry(String name, Map<WallpaperLibrary, BackupState> s) =>
          (
            entry: ReconcileEntry(
              name: name,
              states: s,
              backupWorkshop: true,
              backupMyProjects: false,
            ),
            face: null,
          );
      final List<ReconcileTile> tiles = <ReconcileTile>[
        entry('safe', const <WallpaperLibrary, BackupState>{
          WallpaperLibrary.myProjects: BackupState.synced,
        }),
        entry('exposed', const <WallpaperLibrary, BackupState>{
          WallpaperLibrary.myProjects: BackupState.synced,
          WallpaperLibrary.workshop: BackupState.notBackedUp,
        }),
      ];

      final List<ReconcileTile> shown = visibleReconcileTiles(
        tiles: tiles,
        needle: '',
        filter: filterOf(),
        sort: BackupSortType.state,
        ascending: false,
      );

      expect(shown.map((ReconcileTile t) => t.entry.name), <String>[
        'exposed',
        'safe',
      ]);
    });
  });

  group('reconcile tiles', () {
    ReconcileTile entryOf(String name, {CardFace? face}) => (
      entry: ReconcileEntry(
        name: name,
        states: const <WallpaperLibrary, BackupState>{
          WallpaperLibrary.myProjects: BackupState.synced,
        },
        backupWorkshop: true,
        backupMyProjects: false,
      ),
      face: face,
    );

    test('the search and the filter reach them too', () {
      final List<ReconcileTile> tiles = <ReconcileTile>[
        entryOf('alpha'),
        entryOf('793602574', face: faceOf(title: 'Neon City')),
      ];

      final List<ReconcileTile> shown = visibleReconcileTiles(
        tiles: tiles,
        needle: 'neon',
        filter: filterOf(),
        sort: BackupSortType.state,
        ascending: false,
      );

      expect(shown.map((ReconcileTile t) => t.entry.name), <String>[
        '793602574',
      ]);
    });

    // Or a name would collide with the card of the same name and share its
    // selection.
    test('a reconcile id is not a card id', () {
      expect(
        reconcileTileId('Alpha'),
        isNot(const BackupCard(WallpaperLibrary.myProjects, 'Alpha').id),
      );
      expect(reconcileTileId('Alpha'), reconcileTileId('alpha'));
    });
  });
}
