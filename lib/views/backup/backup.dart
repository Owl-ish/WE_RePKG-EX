import 'dart:math';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:we_repkg/config/custom_theme.dart';
import 'package:we_repkg/constants/i10n.dart';
import 'package:we_repkg/constants/nums.dart';
import 'package:we_repkg/cores/backup.dart';
import 'package:we_repkg/cores/base.dart';
import 'package:we_repkg/models/enums.dart';
import 'package:we_repkg/provider/backup.dart';
import 'package:we_repkg/provider/navigation.dart';
import 'package:we_repkg/provider/system.dart';
import 'package:we_repkg/utils/backup_diff.dart';
import 'package:we_repkg/utils/backup_tiles.dart';
import 'package:we_repkg/utils/grid_selection.dart';
import 'package:we_repkg/utils/modifier_keys.dart';
import 'package:we_repkg/views/backup/backup_tile.dart';
import 'package:we_repkg/views/backup/integrity.dart';
import 'package:we_repkg/views/states/no_results.dart';
import 'package:we_repkg/views/top/filter_dropdown.dart';
import 'package:we_repkg/views/top/sort_toggle.dart';
import 'package:we_repkg/widgets/app_icon_button.dart';
import 'package:we_repkg/widgets/folder_input.dart';
import 'package:we_repkg/widgets/pill_dropdown.dart';
import 'package:we_repkg/widgets/search_field.dart';
import 'package:we_repkg/widgets/selection_grid.dart';
import 'package:we_repkg/widgets/sliding_switch.dart';
import 'package:we_repkg/widgets/top_bar.dart';

/// The backup area: the backup itself, and the integrity check beside it.
class BackupView extends ConsumerWidget {
  const BackupView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final BackupTab tab = ref.watch(currentBackupTabProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _Bar(tab: tab),
        // The bar insets itself the way the extract tab's does, so only what is
        // under it is this view's to indent.
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              LayoutNums.edgeInset,
              0,
              LayoutNums.edgeInset,
              LayoutNums.contentGap,
            ),
            child: switch (tab) {
              // The integrity check reads the live libraries too, so it is
              // worth opening before a backup root has been chosen.
              BackupTab.integrity => const IntegrityView(),
              BackupTab.backup => const _Backup(),
            },
          ),
        ),
      ],
    );
  }
}

/// The tab switch, and the view controls once there is a grid to point them at.
class _Bar extends ConsumerWidget {
  const _Bar({required this.tab});

  final BackupTab tab;

  static const double _switchMaxWidth = 260;

  /// Whatever the last scan said, even while the next one runs: a rescan must
  /// not take the search box away, and with it what was typed in it.
  static bool _hasGrid(AsyncValue<BackupScan> scan) =>
      scan.hasValue && scan.requireValue.missing.isEmpty;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The scan is watched last on purpose. It starts the moment anything reads
    // it, and reading it here would run the whole comparison behind the "choose
    // a folder" screen and again beside the integrity check.
    final bool grid =
        tab == BackupTab.backup &&
        ref.watch(backupRootProvider) != null &&
        _hasGrid(ref.watch(backupScanProvider));

    return TopBar(
      leading: <Widget>[
        // The switch sizes itself to its labels and ignores a width it is
        // given, so in a row it is free to overflow. scaleDown never grows it.
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _switchMaxWidth),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: SlidingSwitch(
              initialValue: tab.index,
              children: <int, Widget>{
                for (int i = 0; i < BackupTab.values.length; i++)
                  i + 1: Text(BackupTab.values[i].label),
              },
              onValueChanged: (int v) => ref
                  .read(currentBackupTabProvider.notifier)
                  .update(BackupTab.values[v - 1]),
            ),
          ),
        ),
        if (grid) ...<Widget>[
          const SizedBox(width: 4),
          // The kept-alive scan does not notice the filesystem moving under it,
          // so this is the only way to ask for fresh numbers.
          AppIconButton(
            tooltip: tr(AppI10n.backupRefresh),
            onPressed: () => ref.invalidate(backupScanProvider),
            icon: Icons.refresh_rounded,
            width: TopBarNums.buttonSize,
            height: TopBarNums.buttonSize,
            iconSize: TopBarNums.iconSize,
          ),
        ],
        const SizedBox(width: 24),
      ],
      centre: grid
          ? SearchField(
              initialText: ref.read(backupSearchProvider),
              onChanged: (String text) =>
                  ref.read(backupSearchProvider.notifier).update(text),
            )
          : const SizedBox.shrink(),
      trailing: grid
          ? <Widget>[
              // Wider gap here than between the controls, so they read as a
              // group.
              const SizedBox(width: 16),
              const FilterDropdown(),
              const SizedBox(width: 8),
              SortToggle(
                ascending: ref.watch(backupSortAscendingProvider),
                onPressed: ref
                    .read(backupSortAscendingProvider.notifier)
                    .update,
              ),
              const SizedBox(width: 8),
              PillDropdown<BackupSortType>(
                value: ref.watch(backupSortOrderProvider),
                items: BackupSortType.values,
                labelOf: (BackupSortType type) => type.label,
                onChanged: ref.read(backupSortOrderProvider.notifier).update,
              ),
            ]
          : const <Widget>[],
    );
  }
}

class _Backup extends ConsumerWidget {
  const _Backup();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(backupRootProvider) == null) return const _PickRoot();
    return switch (ref.watch(backupScanProvider)) {
      AsyncData<BackupScan>(value: final BackupScan scan)
          when scan.missing.isNotEmpty =>
        _MissingFolders(missing: scan.missing),
      AsyncData<BackupScan>(:final BackupScan value) => _Loaded(scan: value),
      AsyncError<BackupScan>(:final Object error) => Center(
        child: Text('${tr(AppI10n.backupScanFailed)} $error'),
      ),
      _ => const _Scanning(),
    };
  }
}

/// The first scan takes about twelve seconds against a real library, most of it
/// walking both backup trees, so the spinner says what it is doing rather than
/// leaving the tab blank.
class _Scanning extends ConsumerWidget {
  const _Scanning();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        spacing: 16,
        children: <Widget>[
          const CircularProgressIndicator(),
          // Only this line listens, so a count that moves every few folders
          // does not rebuild the tab behind it.
          ValueListenableBuilder<BackupScanProgress?>(
            valueListenable: ref.watch(backupScanProgressProvider),
            builder: (BuildContext context, BackupScanProgress? progress, _) {
              if (progress == null) return const SizedBox.shrink();
              return Text(switch (progress.phase) {
                BackupScanPhase.reading => tr(AppI10n.backupScanReading),
                BackupScanPhase.comparing => tr(
                  AppI10n.backupScanComparing,
                  namedArgs: <String, String>{
                    'done': '${progress.done}',
                    'total': '${progress.total}',
                  },
                ),
              }, style: Theme.of(context).meta.captionStyle);
            },
          ),
        ],
      ),
    );
  }
}

/// Names the folders the scan could not read, and what each is set to.
///
/// Counts are withheld rather than shown alongside: a missing live library
/// turns every backup folder into a vanished card and a missing backup root
/// empties the vanished list, and either reads as a confident number.
class _MissingFolders extends ConsumerWidget {
  const _MissingFolders({required this.missing});

  final Set<BackupFolder> missing;

  static const Map<BackupFolder, String> _labels = <BackupFolder, String>{
    BackupFolder.liveWorkshop: AppI10n.backupFolderLiveWorkshop,
    BackupFolder.liveMyProjects: AppI10n.backupFolderLiveMyProjects,
    BackupFolder.backupRoot: AppI10n.backupFolderBackupRoot,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Map<BackupFolder, String?> paths = <BackupFolder, String?>{
      BackupFolder.liveWorkshop: ref.watch(wallpaperPathProvider),
      BackupFolder.liveMyProjects: ref.watch(myProjectsLibraryProvider),
      BackupFolder.backupRoot: ref.watch(backupRootProvider),
    };
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        spacing: 12,
        children: [
          const Icon(Icons.folder_off_outlined, size: 48, color: Colors.grey),
          Text(tr(AppI10n.backupMissingFolders)),
          for (final BackupFolder folder in BackupFolder.values)
            if (missing.contains(folder))
              Text(
                '${tr(_labels[folder]!)}  '
                '${paths[folder] ?? tr(AppI10n.backupPathNotSet)}',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
        ],
      ),
    );
  }
}

/// Repeats the settings card's picker, so the feature is reachable without
/// knowing to look there.
class _PickRoot extends ConsumerWidget {
  const _PickRoot();

  static const double _pickerWidth = 460;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        spacing: 16,
        children: [
          Icon(Icons.backup_outlined, size: 48, color: Colors.grey),
          Text(
            tr(AppI10n.backupNoRoot),
            style: const TextStyle(
              fontSize: 16,
              color: Colors.grey,
              fontFamily: 'Microsoft YaHei',
            ),
          ),
          SizedBox(
            width: _pickerWidth,
            child: FolderInput(
              height: 36,
              text: null,
              hintText: tr(AppI10n.settingBackupRootTip),
              onPressed: () => setBackupRoot(ref),
            ),
          ),
        ],
      ),
    );
  }
}

/// The pills across the top, then the grid they describe.
///
/// The counts stay whole-library while a pill or the search narrows the grid:
/// they are the summary of what is on disk, and narrowing is a way of looking
/// at it.
class _Loaded extends ConsumerWidget {
  const _Loaded({required this.scan});

  final BackupScan scan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Map<BackupState, int> counts = countByState(scan.cards.values);
    final BackupShown shown = ref.watch(backupStateFilterProvider);
    final BackupStateFilter pills = ref.read(
      backupStateFilterProvider.notifier,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Without the ACF every backed-up Workshop wallpaper compares as
        // current, so the update count reads zero rather than unknown.
        if (!scan.acfRead)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              tr(AppI10n.backupAcfUnreadable),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: LayoutNums.contentGap),
          child: Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final BackupState state in backupStateOrder)
                _CountPill(
                  colour: backupStateLook[state]!.colour,
                  label: tr(backupStateLook[state]!.label),
                  count: counts[state]!,
                  // All off while the reconcile pill has the grid, which is what
                  // makes clicking one mean "show me that state".
                  on: !shown.reconcile && shown.states.contains(state),
                  // Synced is the one state with nothing to come back to, and
                  // on a looked-after library it is most of the grid.
                  nags: state != BackupState.synced,
                  onPressed: () => pills.toggle(state),
                ),
              _CountPill(
                colour: _reconcileColour,
                label: tr(AppI10n.backupReconcile),
                count: scan.reconcile.length,
                on: shown.reconcile,
                onPressed: pills.toggleReconcile,
              ),
            ],
          ),
        ),
        const Expanded(child: _Grid()),
      ],
    );
  }
}

/// A count that switches its own tiles on and off.
///
/// Glows in its own colour while it holds wallpapers and is switched off: a
/// state nobody is looking at is one to come back to. Dimmed and unclickable at
/// zero, except while it holds the grid, or resolving the last one waiting
/// would leave an empty grid with no way back.
class _CountPill extends StatefulWidget {
  const _CountPill({
    required this.colour,
    required this.label,
    required this.count,
    required this.on,
    required this.onPressed,
    this.nags = true,
  });

  final Color colour;
  final String label;
  final int count;
  final bool on;
  final VoidCallback onPressed;

  /// Whether this pill is worth coming back to at all.
  final bool nags;

  @override
  State<_CountPill> createState() => _CountPillState();
}

class _CountPillState extends State<_CountPill>
    with SingleTickerProviderStateMixin {
  /// Slow enough to read as breathing rather than blinking, and faint enough to
  /// sit behind text without moving the eye off the grid.
  static const Duration _period = Duration(milliseconds: 2600);
  static const double _peak = .22;

  late final AnimationController _glow = AnimationController(
    vsync: this,
    duration: _period,
  );

  bool get _wanted => widget.nags && widget.count > 0 && !widget.on;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(_CountPill old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (_wanted) {
      if (!_glow.isAnimating) _glow.repeat();
    } else if (_glow.isAnimating) {
      _glow.stop();
      _glow.value = 0;
    }
  }

  @override
  void dispose() {
    _glow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool live = widget.count > 0 || widget.on;
    final Color tint = live ? widget.colour : Theme.of(context).disabledColor;
    return AnimatedBuilder(
      animation: _glow,
      builder: (BuildContext context, Widget? child) => Material(
        // Cosine, so it swells and fades rather than snapping at either end.
        color: widget.colour.withValues(
          alpha: _peak * (1 - cos(_glow.value * 2 * pi)) / 2,
        ),
        borderRadius: LayoutNums.pill,
        child: child,
      ),
      child: InkWell(
        borderRadius: LayoutNums.pill,
        mouseCursor: live ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onTap: live ? widget.onPressed : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            borderRadius: LayoutNums.pill,
            border: Border.all(
              color: widget.on && live ? tint : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 6,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: widget.on ? tint : Colors.transparent,
                  border: Border.all(color: tint, width: 1.5),
                  shape: BoxShape.circle,
                ),
              ),
              // Flexible, or a long label in a narrow window overflows its own
              // row rather than being cut short.
              Flexible(
                child: Text(
                  '${widget.label} ${widget.count}',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: live && widget.on ? null : tint),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Red, unlike the grey badge a reconcile tile wears: on the tile it names a
/// question, here it is the one count the tab cannot answer for at all.
const Color _reconcileColour = Color(0xFFC62828);

/// Reading a few thousand titles and previews takes about half a second on top
/// of the scan, so the pills above are already up while this resolves.
class _Grid extends ConsumerWidget {
  const _Grid();

  /// Ctrl toggles, shift reaches back to the last click, a plain click takes
  /// this one alone. The same three the extract grid offers.
  void _click(WidgetRef ref, List<String> ids, int index) {
    final BackupSelection selection = ref.read(
      backupSelectionProvider.notifier,
    );
    final String id = ids[index];
    if (isCtrlPressed) {
      selection.toggle(id);
      return;
    }
    if (!isShiftPressed) {
      selection.setExclusive(id);
      return;
    }
    final Set<String> selected = ref.read(backupSelectionProvider);
    // The anchor is an id, so it is looked up in the list as it stands now.
    // Falls back to the last selected tile, so shift still extends after a
    // marquee drag, which sets no anchor.
    final int held = ids.indexOf(selection.shiftAnchor ?? '');
    final int? anchor = held >= 0
        ? held
        : (selected.isEmpty ? null : ids.lastIndexWhere(selected.contains));
    final ({int begin, int end}) range = shiftRange(
      anchor: anchor,
      target: index,
      count: ids.length,
    );
    selection.setExactly(<String>{
      for (int i = range.begin; i <= range.end; i++) ids[i],
    });
  }

  /// One grid for both lists: a tile is a picture and an id whichever it draws.
  ///
  /// [id] names the scroll position, so the cards keep theirs while a trip
  /// through the reconcile pill scrolls that much shorter list.
  Widget _grid<T>(
    WidgetRef ref,
    AsyncValue<List<T>> tiles, {
    required String id,
    required String Function(T tile) idOf,
    required Widget Function(T tile, double width, VoidCallback onTap) build,
  }) {
    return switch (tiles) {
      AsyncData<List<T>>(value: final List<T> value) when value.isEmpty =>
        const NoResultsView(key: NoResultsView.viewKey),
      AsyncData<List<T>>(:final List<T> value) => Builder(
        builder: (BuildContext context) {
          final List<String> ids = value.map(idOf).toList();
          return SelectionGrid(
            key: ValueKey<String>(id),
            id: id,
            // The tab is already inset either side, so only the gap under the
            // pills is this grid's to add.
            padding: const EdgeInsets.only(top: LayoutNums.contentGap),
            itemCount: value.length,
            idAt: (int index) => ids[index],
            currentSelection: () => ref.read(backupSelectionProvider),
            onSelectionChanged: (Set<String> selected) {
              if (context.mounted) {
                ref.read(backupSelectionProvider.notifier).setExactly(selected);
              }
            },
            itemBuilder:
                (BuildContext context, int index, GridGeometry geometry) =>
                    build(
                      value[index],
                      geometry.tile,
                      () => _click(ref, ids, index),
                    ),
          );
        },
      ),
      // Its own message rather than the scan's: the counts above this are
      // proof the scan itself worked.
      AsyncError<List<T>>(:final Object error) => Center(
        child: Text('${tr(AppI10n.backupTilesFailed)} $error'),
      ),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String? backupRoot = ref.watch(backupRootProvider);
    final String? workshop = ref.watch(wallpaperPathProvider);
    final String? myProjects = ref.watch(myProjectsLibraryProvider);

    if (ref.watch(backupStateFilterProvider).reconcile) {
      return _grid<ReconcileTile>(
        ref,
        ref.watch(backupVisibleReconcileTilesProvider),
        id: 'backup-reconcile-grid',
        idOf: (ReconcileTile tile) => reconcileTileId(tile.entry.name),
        build: (ReconcileTile tile, double width, VoidCallback onTap) =>
            ReconcileTileView(
              key: ValueKey<String>(reconcileTileId(tile.entry.name)),
              width: width,
              tile: tile,
              folders: reconcileFolders(
                entry: tile.entry,
                backupRoot: backupRoot,
                liveWorkshopPath: workshop,
                liveMyProjectsPath: myProjects,
              ),
              onTap: onTap,
            ),
      );
    }

    return _grid<BackupTile>(
      ref,
      ref.watch(backupVisibleTilesProvider),
      id: 'backup-grid',
      idOf: (BackupTile tile) => tile.card.id,
      build: (BackupTile tile, double width, VoidCallback onTap) =>
          BackupTileView(
            key: ValueKey<String>(tile.card.id),
            width: width,
            tile: tile,
            folders: cardFolders(
              library: tile.card.library,
              name: tile.card.name,
              liveExists: tile.state != BackupState.vanished,
              backupExists: tile.state != BackupState.notBackedUp,
              backupRoot: backupRoot,
              liveWorkshopPath: workshop,
              liveMyProjectsPath: myProjects,
            ),
            onTap: onTap,
          ),
    );
  }
}
