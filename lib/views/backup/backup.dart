import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:we_repkg/config/theme_extensions.dart';
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
import 'package:we_repkg/utils/wallpaper_junk.dart';
import 'package:we_repkg/views/backup/backup_tile.dart';
import 'package:we_repkg/views/backup/backup_action_ui.dart';
import 'package:we_repkg/views/backup/integrity.dart';
import 'package:we_repkg/views/states/no_results.dart';
import 'package:we_repkg/views/top/filter_dropdown.dart';
import 'package:we_repkg/views/top/sort_toggle.dart';
import 'package:we_repkg/widgets/app_icon_button.dart';
import 'package:we_repkg/widgets/count_pill.dart';
import 'package:we_repkg/widgets/issue_note.dart';
import 'package:we_repkg/widgets/folder_input.dart';
import 'package:we_repkg/widgets/pill_dropdown.dart';
import 'package:we_repkg/widgets/search_field.dart';
import 'package:we_repkg/widgets/selection_grid.dart';
import 'package:we_repkg/widgets/sliding_switch.dart';
import 'package:we_repkg/widgets/top_bar.dart';
import 'package:we_repkg/widgets/scan_progress.dart';

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
    final bool backupReady =
        tab == BackupTab.backup && ref.watch(backupRootProvider) != null;
    final AsyncValue<BackupScan>? scan = backupReady
        ? ref.watch(backupScanProvider)
        : null;
    final bool grid = scan != null && _hasGrid(scan);

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
            // Off while anything is still reading: a second run writes its
            // progress into the same line as the first, which is still going
            // because nothing here is cancelled.
            onPressed:
                scan.isLoading || ref.watch(backupTilesProvider).isLoading
                ? null
                : () => ref.invalidate(backupScanProvider),
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

class _Backup extends ConsumerStatefulWidget {
  const _Backup();

  @override
  ConsumerState<_Backup> createState() => _BackupState();
}

class _BackupState extends ConsumerState<_Backup> {
  final GridEntranceReplay _entrance = GridEntranceReplay();
  BackupScan? _lastLoadedScan;

  @override
  void initState() {
    super.initState();
    final bool sectionEntrance = ref
        .read(currentSectionProvider.notifier)
        .consumeEntrance(NavSection.backup);
    final bool tabEntrance = ref
        .read(currentBackupTabProvider.notifier)
        .consumeEntrance(BackupTab.backup);
    if (sectionEntrance || tabEntrance) _entrance.request();
  }

  Widget _loaded(BackupScan scan) {
    final BackupScan? previous = _lastLoadedScan;
    _lastLoadedScan = scan;
    // A completed replacement scan is the other explicit replay trigger.
    // Comparing the scan object rather than its contents also covers rescans
    // whose result happens to be identical to the previous one.
    if (previous != null && !identical(previous, scan)) _entrance.request();
    return _Loaded(scan: scan, entrance: _entrance);
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(backupRootProvider) == null) return const _PickRoot();

    return switch (ref.watch(backupScanProvider)) {
      AsyncData<BackupScan>(value: final BackupScan scan)
          when scan.missing.isNotEmpty =>
        _MissingFolders(missing: scan.missing),
      AsyncData<BackupScan>(:final BackupScan value) => _loaded(value),
      AsyncError<BackupScan>(:final Object error) => Center(
        child: Text('${tr(AppI10n.backupScanFailed)} $error'),
      ),
      _ => const _Scanning(idle: AppI10n.backupScanReading),
    };
  }
}

/// Shows scan progress so filesystem work is distinguishable from a hung tab.
class _Scanning extends ConsumerWidget {
  const _Scanning({required this.idle});

  /// Shown until the phase reports, and after it has finished writing counts.
  final String idle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Only this listens, so a count that moves every few folders does not
    // rebuild the tab behind it.
    return ValueListenableBuilder<BackupScanProgress?>(
      valueListenable: ref.watch(backupScanProgressProvider),
      builder: (BuildContext context, BackupScanProgress? progress, _) {
        if (progress == null) return ScanProgress(label: tr(idle));
        return ScanProgress(
          label: switch (progress.phase) {
            BackupScanPhase.reading => tr(AppI10n.backupScanReading),
            BackupScanPhase.comparing => tr(AppI10n.backupScanComparing),
            BackupScanPhase.finishing => tr(AppI10n.backupScanFinishing),
            BackupScanPhase.details => tr(
              AppI10n.backupReadingDetailsCount,
              namedArgs: _counts(progress),
            ),
            BackupScanPhase.preparing => tr(AppI10n.backupPreparingGrid),
          },
          progress: switch (progress.phase) {
            BackupScanPhase.details when progress.total > 0 =>
              progress.done / progress.total,
            _ => null,
          },
        );
      },
    );
  }

  Map<String, String> _counts(BackupScanProgress progress) => <String, String>{
    'done': '${progress.done}',
    'total': '${progress.total}',
  };
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

//====================
// Backup Pill UI
//====================

class _Loaded extends ConsumerWidget {
  const _Loaded({required this.scan, required this.entrance});

  final BackupScan scan;
  final GridEntranceReplay entrance;

  String _stateAbout(BackupState state) => switch (state) {
    BackupState.synced => AppI10n.backupAboutSynced,
    BackupState.notBackedUp => AppI10n.backupAboutNotBackedUp,
    BackupState.vanished => AppI10n.backupAboutVanished,
    BackupState.updateAvailable => AppI10n.backupAboutUpdateAvailable,
    BackupState.updateDismissed => AppI10n.backupAboutUpdateDismissed,
    BackupState.emptyBackup => AppI10n.backupEmptyJunkAbout,
  };

  String _bulkActionText(BackupAction action) => switch (action) {
    BackupAction.backUp => AppI10n.backupActionBackUpAll,
    BackupAction.update => AppI10n.backupActionUpdateAll,
    BackupAction.restore => AppI10n.backupActionRestoreAll,
    BackupAction.recycleJunk => AppI10n.backupActionRecycleAll,
    BackupAction.showUpdateAgain => AppI10n.backupActionShowAgainAll,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Map<BackupState, int> counts = countByState(scan.cards.values);
    final BackupShown shown = ref.watch(backupStateFilterProvider);
    final BackupStateFilter pills = ref.read(
      backupStateFilterProvider.notifier,
    );
    final BackupAction? action =
        shown.reconcile || shown.state == BackupState.emptyBackup
        ? null
        : actionForBackupState(shown.state);
    final Map<BackupState, ({Color colour, String label})> looks =
        <BackupState, ({Color colour, String label})>{
          for (final BackupState state in backupStateOrder)
            state: backupStateLook(context, state),
        };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Missing Workshop version data makes affected comparisons unknown.
        if (!scan.acfRead)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              tr(AppI10n.backupAcfUnreadable),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(
            top: LayoutNums.contentGap,
            bottom: LayoutNums.smallGap,
          ),
          child: PillRow(
            children: [
              for (final BackupState state in backupStateOrder)
                CountPill(
                  colour: looks[state]!.colour,
                  label: tr(looks[state]!.label),
                  count: counts[state]!,
                  on: !shown.reconcile && shown.state == state,
                  // Synced is the one state with nothing to come back to, and
                  // on a looked-after library it is most of the grid.
                  nags: state != BackupState.synced,
                  onPressed: () => pills.show(state),
                ),
              // Reconcile is red because it is the one count the tab cannot
              // answer automatically.
              CountPill(
                colour: Theme.of(context).status.bad,
                label: tr(AppI10n.backupReconcile),
                count: scan.reconcile.length,
                on: shown.reconcile,
                onPressed: pills.showReconcile,
              ),
            ],
          ),
        ),
        if (action != null)
          Padding(
            padding: const EdgeInsets.only(top: LayoutNums.contentGap),
            child: Align(
              alignment: Alignment.centerRight,
              child: _GlowingActionButton(
                label: tr(
                  _bulkActionText(action),
                  namedArgs: <String, String>{
                    'count': '${counts[shown.state]}',
                  },
                ),
                icon: backupActionIcon(action),
                colour: looks[shown.state]!.colour,
                onPressed: counts[shown.state] == 0
                    ? null
                    : () => applyBackupAction(context, action, <BackupCard>[
                        for (final MapEntry<BackupCard, BackupState> entry
                            in scan.cards.entries)
                          if (entry.value == shown.state) entry.key,
                      ]),
              ),
            ),
          ),
        if (!shown.reconcile &&
            shown.state != BackupState.emptyBackup &&
            counts[shown.state]! > 0)
          _BackupIssueHeader(
            noteKey: ValueKey<String>('backup-state-note-${shown.state.name}'),
            child: Text(
              tr(_stateAbout(shown.state)),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        Expanded(child: _Grid(entrance: entrance)),
      ],
    );
  }
}

class _BackupIssueNote extends StatelessWidget {
  const _BackupIssueNote({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1100),
      child: SizedBox(
        width: double.infinity,
        child: IssueNote(
          compact: true,
          colour: Theme.of(context).status.note,
          child: DefaultTextStyle.merge(
            style: Theme.of(context).meta.mediumStyle.copyWith(height: 1.2),
            child: child,
          ),
        ),
      ),
    ),
  );
}

const double _backupIssueHeaderHeight = 60;
const double _backupJunkActionExtent = 50;

class _BackupIssueHeader extends StatelessWidget {
  const _BackupIssueHeader({
    required this.noteKey,
    required this.child,
    this.pinned = false,
  });

  final Key noteKey;
  final Widget child;
  final bool pinned;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: pinned
        ? Theme.of(context).scaffoldBackgroundColor
        : Colors.transparent,
    child: Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: _BackupIssueNote(key: noteKey, child: child),
    ),
  );
}

class _GlowingActionButton extends StatelessWidget {
  const _GlowingActionButton({
    required this.label,
    required this.icon,
    required this.colour,
    required this.onPressed,
    this.destructive = false,
  });

  final String label;
  final IconData icon;
  final Color colour;
  final VoidCallback? onPressed;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onPressed != null;
    final ThemeData theme = Theme.of(context);
    final ActionButtonTheme actionColors = theme.actionButtons;
    final Color resolvedColour = enabled
        ? (destructive ? actionColors.destructiveForeground : colour)
        : theme.disabledColor;
    // Non-destructive state actions rest like their status pills. Destructive
    // actions use the app-wide danger surface, then the same outward pulse.
    final Color fill = destructive
        ? (enabled
              ? actionColors.destructiveBackground
              : actionColors.destructiveBackground.withValues(alpha: .5))
        : Color.alphaBlend(
            resolvedColour.withValues(alpha: enabled ? .07 : .05),
            theme.scaffoldBackgroundColor,
          );
    final Color border = destructive
        ? (enabled
              ? actionColors.destructiveBorder
              : actionColors.destructiveBorder.withValues(alpha: .5))
        : resolvedColour.withValues(alpha: enabled ? .2 : .15);
    return Tooltip(
      message: label,
      child: BackupActionGlow(
        colour: resolvedColour,
        enabled: enabled,
        borderRadius: LayoutNums.pill,
        glowKey: const ValueKey<String>('backup-all-action-glow'),
        child: Material(
          color: fill,
          shape: RoundedRectangleBorder(
            borderRadius: LayoutNums.pill,
            side: BorderSide(color: border),
          ),
          child: InkWell(
            borderRadius: LayoutNums.pill,
            onTap: onPressed,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: LayoutNums.compactGap,
                children: <Widget>[
                  Icon(icon, size: 16, color: resolvedColour),
                  Text(label, style: TextStyle(color: resolvedColour)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Resolves tile faces separately so the scan counts and pills can appear
/// before preview metadata finishes loading.
class _Grid extends ConsumerStatefulWidget {
  const _Grid({required this.entrance});

  final GridEntranceReplay entrance;

  @override
  ConsumerState<_Grid> createState() => _GridState();
}

class _GridState extends ConsumerState<_Grid> {
  static const SelectionEngine<String> _selection = SelectionEngine<String>();

  bool _takeEntrance() => widget.entrance.take();

  /// Plain click selects one, Ctrl toggles, Shift replaces the anchor range,
  /// and Ctrl+Shift adds that range. The id anchor is shared with Extract so
  /// sorting or filtering cannot silently move the range start.
  void _click(WidgetRef ref, List<String> ids, int index) {
    final BackupSelection selection = ref.read(
      backupSelectionProvider.notifier,
    );
    final Set<String> selected = ref.read(backupSelectionProvider);
    final String id = ids[index];
    final bool control = isCtrlPressed;
    final bool shift = isShiftPressed;

    final Set<String> next = _selection.click(
      ordered: ids,
      current: selected,
      target: index,
      control: control,
      shift: shift,
      anchor: selection.shiftAnchor,
    );
    selection.setExactly(next);

    if (control && !shift) {
      selection.shiftAnchor = id;
    } else if (!shift) {
      selection.shiftAnchor = next.isEmpty ? null : id;
    }
  }

  Widget _selectionGrid(
    WidgetRef ref,
    BuildContext context, {
    required String id,
    required List<String> ids,
    required Object reflowIdentity,
    required Widget Function(
      BuildContext context,
      int index,
      GridGeometry geometry,
    )
    itemBuilder,
    EdgeInsets padding = const EdgeInsets.only(top: LayoutNums.contentGap),
    List<SelectionGridSection> sections = const <SelectionGridSection>[],
    int? entranceToken,
    bool? entranceOnMount,
  }) {
    return SelectionGrid(
      key: ValueKey<String>(id),
      id: id,
      itemCount: ids.length,
      idAt: (int index) => ids[index],
      currentSelection: () => ref.read(backupSelectionProvider),
      onSelectionChanged: (Set<String> selected) {
        if (context.mounted) {
          ref.read(backupSelectionProvider.notifier).setExactly(selected);
        }
      },
      padding: padding,
      entranceToken: entranceToken ?? widget.entrance.token,
      entranceOnMount: entranceOnMount ?? _takeEntrance(),
      reflowIdentity: reflowIdentity,
      sections: sections,
      itemBuilder: itemBuilder,
    );
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
    required Widget waiting,
    required Object reflowIdentity,
  }) {
    return switch (tiles) {
      AsyncData<List<T>>(value: final List<T> value) when value.isEmpty =>
        Builder(
          builder: (BuildContext context) {
            widget.entrance.discard();
            return const NoResultsView(key: NoResultsView.viewKey);
          },
        ),
      AsyncData<List<T>>(:final List<T> value) => Builder(
        builder: (BuildContext context) {
          final List<String> ids = value.map(idOf).toList();
          return _selectionGrid(
            ref,
            context,
            id: id,
            ids: ids,
            reflowIdentity: reflowIdentity,
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
      _ => waiting,
    };
  }

  ({String title, String about}) _reconcileText(BackupReconcileReason reason) =>
      switch (reason) {
        BackupReconcileReason.duplicateLiveCopies => (
          title: AppI10n.backupReconcileDuplicateLiveTitle,
          about: AppI10n.backupReconcileDuplicateLiveAbout,
        ),
        BackupReconcileReason.conflictingBackupCopies => (
          title: AppI10n.backupReconcileConflictingBackupsTitle,
          about: AppI10n.backupReconcileConflictingBackupsAbout,
        ),
        BackupReconcileReason.comparisonUnavailable => (
          title: AppI10n.backupReconcileComparisonUnavailableTitle,
          about: AppI10n.backupReconcileComparisonUnavailableAbout,
        ),
      };

  Widget _reconcileGrid(
    WidgetRef ref,
    AsyncValue<List<ReconcileTile>> tiles, {
    required String? backupRoot,
    required String? workshop,
    required String? myProjects,
  }) {
    return switch (tiles) {
      AsyncData<List<ReconcileTile>>(value: final List<ReconcileTile> value)
          when value.isEmpty =>
        Builder(
          builder: (BuildContext context) {
            widget.entrance.discard();
            return const NoResultsView(key: NoResultsView.viewKey);
          },
        ),
      AsyncData<List<ReconcileTile>>(:final List<ReconcileTile> value) =>
        Builder(
          builder: (BuildContext context) {
            widget.entrance.discard();
            final Map<BackupReconcileReason, List<ReconcileTile>> groups =
                <BackupReconcileReason, List<ReconcileTile>>{
                  for (final BackupReconcileReason reason
                      in BackupReconcileReason.values)
                    reason: <ReconcileTile>[],
                };
            for (final ReconcileTile tile in value) {
              groups[tile.entry.reason]!.add(tile);
            }
            final List<ReconcileTile> grouped = <ReconcileTile>[
              for (final BackupReconcileReason reason
                  in BackupReconcileReason.values)
                ...groups[reason]!,
            ];
            final List<String> ids = <String>[
              for (final ReconcileTile tile in grouped)
                reconcileTileId(tile.entry.name),
            ];

            return _selectionGrid(
              ref,
              context,
              id: 'backup-reconcile-grid',
              ids: ids,
              padding: EdgeInsets.zero,
              entranceToken: 0,
              entranceOnMount: false,
              reflowIdentity: const ValueKey<String>('reconcile-groups'),
              sections: <SelectionGridSection>[
                for (final BackupReconcileReason reason
                    in BackupReconcileReason.values)
                  if (groups[reason]!.isNotEmpty)
                    SelectionGridSection(
                      itemCount: groups[reason]!.length,
                      headerPinned: true,
                      headerExtent: _backupIssueHeaderHeight,
                      header: _BackupIssueHeader(
                        noteKey: ValueKey<String>(
                          'backup-reconcile-note-${reason.name}',
                        ),
                        pinned: true,
                        child: Text.rich(
                          TextSpan(
                            children: <InlineSpan>[
                              TextSpan(
                                text: '${tr(_reconcileText(reason).title)} - ',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              TextSpan(text: tr(_reconcileText(reason).about)),
                            ],
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
              ],
              itemBuilder:
                  (BuildContext context, int index, GridGeometry geometry) {
                    final ReconcileTile tile = grouped[index];
                    return ReconcileTileView(
                      key: ValueKey<String>(ids[index]),
                      width: geometry.tile,
                      tile: tile,
                      folders: reconcileFolders(
                        entry: tile.entry,
                        backupRoot: backupRoot,
                        liveWorkshopPath: workshop,
                        liveMyProjectsPath: myProjects,
                      ),
                      onTap: () => _click(ref, ids, index),
                    );
                  },
            );
          },
        ),
      AsyncError<List<ReconcileTile>>(:final Object error) => Center(
        child: Text('${tr(AppI10n.backupTilesFailed)} $error'),
      ),
      _ => ScanProgress(label: tr(AppI10n.backupReadingDetails)),
    };
  }

  ({String title, String about}) _junkText(WallpaperJunkKind kind) =>
      switch (kind) {
        WallpaperJunkKind.empty => (
          title: AppI10n.backupJunkEmptyTitle,
          about: AppI10n.backupJunkEmptyAbout,
        ),
        WallpaperJunkKind.shaderCacheOnly => (
          title: AppI10n.backupJunkShaderTitle,
          about: AppI10n.backupJunkShaderAbout,
        ),
        WallpaperJunkKind.mixed => (
          title: AppI10n.backupJunkMixedTitle,
          about: AppI10n.backupJunkMixedAbout,
        ),
      };

  Widget _junkGrid(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<BackupTile>> tiles, {
    required BackupScan scan,
    required String? backupRoot,
    required String? workshop,
    required String? myProjects,
  }) {
    return switch (tiles) {
      AsyncData<List<BackupTile>>(value: final List<BackupTile> value)
          when value.isEmpty =>
        Builder(
          builder: (BuildContext context) {
            widget.entrance.discard();
            return const NoResultsView(key: NoResultsView.viewKey);
          },
        ),
      AsyncData<List<BackupTile>>(:final List<BackupTile> value) => Builder(
        builder: (BuildContext context) {
          final Map<WallpaperJunkKind, List<BackupTile>> groups =
              <WallpaperJunkKind, List<BackupTile>>{
                for (final WallpaperJunkKind kind in WallpaperJunkKind.values)
                  kind: <BackupTile>[],
              };
          for (final BackupTile tile in value) {
            groups[scan.junk[tile.card.id]?.kind ?? WallpaperJunkKind.empty]!
                .add(tile);
          }
          final List<BackupTile> grouped = <BackupTile>[
            for (final WallpaperJunkKind kind in WallpaperJunkKind.values)
              ...groups[kind]!,
          ];
          final List<String> ids = <String>[
            for (final BackupTile tile in grouped) tile.card.id,
          ];

          return _selectionGrid(
            ref,
            context,
            id: 'backup-junk-grid',
            ids: ids,
            padding: EdgeInsets.zero,
            reflowIdentity: BackupState.emptyBackup,
            sections: <SelectionGridSection>[
              for (final WallpaperJunkKind kind in WallpaperJunkKind.values)
                if (groups[kind]!.isNotEmpty)
                  SelectionGridSection(
                    itemCount: groups[kind]!.length,
                    beforeHeaderExtent: _backupJunkActionExtent,
                    beforeHeader: Padding(
                      padding: const EdgeInsets.only(
                        top: LayoutNums.contentGap,
                        bottom: LayoutNums.smallGap,
                      ),
                      child: Align(
                        key: ValueKey<String>(
                          'backup-junk-action-${kind.name}',
                        ),
                        alignment: Alignment.centerRight,
                        child: _GlowingActionButton(
                          label: tr(
                            AppI10n.backupActionRecycleAll,
                            namedArgs: <String, String>{
                              'count': '${groups[kind]!.length}',
                            },
                          ),
                          icon: backupActionIcon(BackupAction.recycleJunk),
                          colour: backupStateLook(
                            context,
                            BackupState.emptyBackup,
                          ).colour,
                          destructive: backupActionIsDestructive(
                            BackupAction.recycleJunk,
                          ),
                          onPressed: () => applyBackupAction(
                            context,
                            BackupAction.recycleJunk,
                            <BackupCard>[
                              for (final BackupTile tile in groups[kind]!)
                                tile.card,
                            ],
                          ),
                        ),
                      ),
                    ),
                    headerPinned: true,
                    headerExtent: _backupIssueHeaderHeight,
                    header: _BackupIssueHeader(
                      noteKey: ValueKey<String>(
                        'backup-junk-note-${kind.name}',
                      ),
                      pinned: true,
                      child: Text.rich(
                        TextSpan(
                          children: <InlineSpan>[
                            TextSpan(
                              text: '${tr(_junkText(kind).title)} - ',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            TextSpan(text: tr(_junkText(kind).about)),
                          ],
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
            ],
            itemBuilder:
                (BuildContext context, int index, GridGeometry geometry) {
                  final BackupTile tile = grouped[index];
                  final WallpaperJunkKind kind =
                      scan.junk[tile.card.id]?.kind ?? WallpaperJunkKind.empty;
                  return BackupTileView(
                    key: ValueKey<String>(tile.card.id),
                    width: geometry.tile,
                    tile: tile,
                    junkKind: kind,
                    folders: cardFolders(
                      library: tile.card.library,
                      name: tile.card.name,
                      liveExists: scan.junk[tile.card.id]?.live ?? false,
                      backupExists: scan.junk[tile.card.id]?.backup ?? false,
                      backupRoot: backupRoot,
                      liveWorkshopPath: workshop,
                      liveMyProjectsPath: myProjects,
                    ),
                    onTap: () => _click(ref, ids, index),
                    onAction: () => applyBackupAction(
                      context,
                      BackupAction.recycleJunk,
                      <BackupCard>[tile.card],
                    ),
                  );
                },
          );
        },
      ),
      AsyncError<List<BackupTile>>(:final Object error) => Center(
        child: Text('${tr(AppI10n.backupTilesFailed)} $error'),
      ),
      _ => const _Scanning(idle: AppI10n.backupPreparingGrid),
    };
  }

  @override
  Widget build(BuildContext context) {
    final String? backupRoot = ref.watch(backupRootProvider);
    final String? workshop = ref.watch(wallpaperPathProvider);
    final String? myProjects = ref.watch(myProjectsLibraryProvider);
    final BackupScan scan = ref.watch(backupScanProvider).requireValue;
    final Map<String, ({bool live, bool backup})> presence = scan.presence;
    final BackupShown shown = ref.watch(backupStateFilterProvider);
    late final Widget grid;
    if (shown.reconcile) {
      grid = _reconcileGrid(
        ref,
        ref.watch(backupVisibleReconcileTilesProvider),
        backupRoot: backupRoot,
        workshop: workshop,
        myProjects: myProjects,
      );
    } else if (shown.state == BackupState.emptyBackup) {
      grid = _junkGrid(
        context,
        ref,
        ref.watch(backupVisibleTilesProvider),
        scan: scan,
        backupRoot: backupRoot,
        workshop: workshop,
        myProjects: myProjects,
      );
    } else {
      grid = _grid<BackupTile>(
        ref,
        ref.watch(backupVisibleTilesProvider),
        id: 'backup-grid',
        reflowIdentity: shown.state,
        waiting: const _Scanning(idle: AppI10n.backupPreparingGrid),
        idOf: (BackupTile tile) => tile.card.id,
        build: (BackupTile tile, double width, VoidCallback onTap) =>
            BackupTileView(
              key: ValueKey<String>(tile.card.id),
              width: width,
              tile: tile,
              updatePlan: scan.updates[tile.card],
              folders: cardFolders(
                library: tile.card.library,
                name: tile.card.name,
                liveExists: tile.state == BackupState.emptyBackup
                    ? scan.junk[tile.card.id]?.live ?? false
                    : presence[tile.card.id]?.live ?? false,
                backupExists: tile.state == BackupState.emptyBackup
                    ? scan.junk[tile.card.id]?.backup ?? false
                    : presence[tile.card.id]?.backup ?? false,
                backupRoot: backupRoot,
                liveWorkshopPath: workshop,
                liveMyProjectsPath: myProjects,
              ),
              onTap: onTap,
              onAction: actionForBackupState(tile.state) == null
                  ? null
                  : () => applyBackupAction(
                      context,
                      actionForBackupState(tile.state)!,
                      <BackupCard>[tile.card],
                    ),
            ),
      );
    }
    return grid;
  }
}
