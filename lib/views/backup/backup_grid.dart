part of 'backup.dart';

typedef _IgnoredGridItem = ({
  BackupTile? update,
  ReconcileTile? reconcile,
  BackupReconcileReason? reason,
});

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
  DuplicateLiveOperationProgress? _duplicateLiveProgress;

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

  void _setDuplicateLiveProgress(DuplicateLiveOperationProgress? progress) {
    if (mounted) setState(() => _duplicateLiveProgress = progress);
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
    bool animateGroupedChanges = false,
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
      animateGroupedChanges: animateGroupedChanges,
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
          title: AppI10n.backupReconcileReasonDuplicateLiveTitle,
          about: AppI10n.backupReconcileReasonDuplicateLiveGroupAbout,
        ),
        BackupReconcileReason.conflictingBackupCopies => (
          title: AppI10n.backupReconcileReasonConflictingBackupsTitle,
          about: AppI10n.backupReconcileReasonConflictingBackupsAbout,
        ),
        BackupReconcileReason.duplicateBackupCopies => (
          title: AppI10n.backupDuplicateBackupsTitle,
          about: AppI10n.backupDuplicateBackupsAbout,
        ),
        BackupReconcileReason.comparisonUnavailable => (
          title: AppI10n.backupReconcileReasonComparisonUnavailableTitle,
          about: AppI10n.backupReconcileReasonComparisonUnavailableAbout,
        ),
      };

  Widget _reconcileGrid(
    WidgetRef ref,
    AsyncValue<List<ReconcileTile>> tiles, {
    required BackupScan scan,
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
      AsyncData<List<ReconcileTile>>(:final List<ReconcileTile> value) => Builder(
        builder: (BuildContext context) {
          widget.entrance.discard();
          final BackupDirectBatch batch = ref.read(backupDirectBatchProvider);
          final BackupDirectBatchState check = batch.forScan(scan, backupRoot);
          final Map<BackupReconcileReason, List<ReconcileTile>> groups =
              <BackupReconcileReason, List<ReconcileTile>>{
                for (final BackupReconcileReason reason
                    in BackupReconcileReason.values)
                  reason: <ReconcileTile>[],
              };
          for (final ReconcileTile tile in value) {
            final BackupReconcileReason? reason =
                tile.entry.activePrimaryReason;
            if (reason == null) continue;
            groups[reason]!.add(tile);
          }
          final List<
            ({
              BackupReconcileReason reason,
              String title,
              String? resultLabel,
              String? about,
              List<ReconcileTile> tiles,
              TileBadgeData? primaryBadge,
            })
          >
          issueSections = [];
          for (final BackupReconcileReason reason
              in BackupReconcileReason.values) {
            final List<ReconcileTile> tiles = groups[reason]!;
            if (tiles.isEmpty) continue;
            if (reason != BackupReconcileReason.conflictingBackupCopies) {
              issueSections.add((
                reason: reason,
                title: _reconcileText(reason).title,
                resultLabel: null,
                about: _reconcileText(reason).about,
                tiles: tiles,
                primaryBadge: null,
              ));
              continue;
            }
            final List<ReconcileTile> pending = [];
            final List<ReconcileTile> matches = [];
            final List<ReconcileTile> different = [];
            final List<ReconcileTile> inconclusive = [];
            final List<ReconcileTile> other = [];
            for (final ReconcileTile tile in tiles) {
              if (!BackupDirectBatch.isPackedUnpackedConflict(tile.entry)) {
                other.add(tile);
                continue;
              }
              final DirectBackupProbeStatus? status =
                  check.results[tile.entry.name.toLowerCase()]?.status;
              if (status == DirectBackupProbeStatus.candidateMatch) {
                matches.add(tile);
              } else if (status == DirectBackupProbeStatus.different ||
                  status == DirectBackupProbeStatus.differentIncomplete) {
                different.add(tile);
              } else if (status == DirectBackupProbeStatus.unavailable ||
                  !BackupDirectBatch.eligible(tile.entry)) {
                inconclusive.add(tile);
              } else {
                pending.add(tile);
              }
            }
            final String packedTitle = AppI10n.backupPackedUnpackedTitle;
            if (matches.isNotEmpty) {
              issueSections.add((
                reason: reason,
                title: packedTitle,
                resultLabel: AppI10n.backupDirectCheckMatch,
                about: null,
                tiles: matches,
                primaryBadge: TileBadgeData(
                  text: tr(AppI10n.backupDirectCheckMatch),
                  colour: Theme.of(context).status.good,
                ),
              ));
            }
            if (different.isNotEmpty) {
              issueSections.add((
                reason: reason,
                title: packedTitle,
                resultLabel: AppI10n.backupTileVerificationChanged,
                about: null,
                tiles: different,
                primaryBadge: TileBadgeData(
                  text: tr(AppI10n.backupTileVerificationChanged),
                  colour: Theme.of(context).status.bad,
                ),
              ));
            }
            if (inconclusive.isNotEmpty) {
              issueSections.add((
                reason: reason,
                title: packedTitle,
                resultLabel: AppI10n.backupDirectCheckReview,
                about: null,
                tiles: inconclusive,
                primaryBadge: TileBadgeData(
                  text: tr(AppI10n.backupDirectCheckReview),
                  colour: Theme.of(context).status.warn,
                ),
              ));
            }
            if (pending.isNotEmpty) {
              issueSections.add((
                reason: reason,
                title: packedTitle,
                resultLabel: AppI10n.backupDirectCheckAwaiting,
                about: check.total == 0
                    ? AppI10n.backupPackedUnpackedAbout
                    : null,
                tiles: pending,
                primaryBadge: TileBadgeData(
                  text: tr(AppI10n.backupPackedUnpackedTag),
                  colour: Theme.of(context).status.note,
                ),
              ));
            }
            if (other.isNotEmpty) {
              issueSections.add((
                reason: reason,
                title: AppI10n.backupOtherConflictsTitle,
                resultLabel: null,
                about: _reconcileText(reason).about,
                tiles: other,
                primaryBadge: null,
              ));
            }
          }
          final grouped = <({ReconcileTile tile, TileBadgeData? primaryBadge})>[
            for (final section in issueSections)
              for (final tile in section.tiles)
                (tile: tile, primaryBadge: section.primaryBadge),
          ];
          final List<String> ids = <String>[
            for (final item in grouped) reconcileTileId(item.tile.entry.name),
          ];
          final List<ReconcileEntry> activeEntries =
              visibleBackupReconcileEntries(
                scan,
                ref.read(backupResolvedIssuesProvider),
              );
          final List<ReconcileEntry> actionableMatchEntries = batch
              .matchedEntries(
                scan: scan,
                backupRoot: backupRoot,
                entries: activeEntries,
              );
          final int actionableMatches = actionableMatchEntries.length;
          final int duplicateLiveCount = activeEntries
              .where(
                (entry) => entry.activeReasons.contains(
                  BackupReconcileReason.duplicateLiveCopies,
                ),
              )
              .length;
          final List<ReconcileEntry> duplicateLiveEntries = activeEntries
              .where(
                (entry) => entry.activeReasons.contains(
                  BackupReconcileReason.duplicateLiveCopies,
                ),
              )
              .toList();
          final List<WallpaperLibrary> duplicateLiveLocations =
              <WallpaperLibrary>[
                if (duplicateLiveEntries.any(
                  (entry) => entry.evidence.liveWorkshop,
                ))
                  WallpaperLibrary.workshop,
                if (duplicateLiveEntries.any(
                  (entry) => entry.evidence.liveMyProjects,
                ))
                  WallpaperLibrary.myProjects,
              ];
          int duplicateCountFor(WallpaperLibrary library) =>
              duplicateLiveEntries
                  .where(
                    (entry) => library == WallpaperLibrary.workshop
                        ? entry.liveWorkshop
                        : entry.liveMyProjects,
                  )
                  .length;
          final bool showDuplicateActions =
              duplicateLiveCount > 0 && duplicateLiveLocations.isNotEmpty;
          final int checkableCount = activeEntries
              .where(BackupDirectBatch.eligible)
              .length;
          final int firstPackedSection = issueSections.indexWhere(
            (section) => section.title == AppI10n.backupPackedUnpackedTitle,
          );
          final bool showPackedProgress = check.running || check.done > 0;
          final int matches = check.results.values
              .where(
                (result) =>
                    result.status == DirectBackupProbeStatus.candidateMatch,
              )
              .length;
          final int different = check.results.values
              .where(
                (result) =>
                    result.status == DirectBackupProbeStatus.different ||
                    result.status ==
                        DirectBackupProbeStatus.differentIncomplete,
              )
              .length;
          final int review = check.results.length - matches - different;
          final bool canResume = check.cancelled && check.done < checkableCount;
          final double duplicateActionsExtent =
              MediaQuery.sizeOf(context).width < 1100 ? 108 : 60;

          return _selectionGrid(
            ref,
            context,
            id: 'backup-reconcile-grid',
            ids: ids,
            padding: EdgeInsets.zero,
            entranceToken: 0,
            entranceOnMount: false,
            reflowIdentity: const ValueKey<String>('reconcile-groups'),
            animateGroupedChanges: true,
            sections: <SelectionGridSection>[
              for (final (sectionIndex, section) in issueSections.indexed)
                SelectionGridSection(
                  itemCount: section.tiles.length,
                  identity: '${section.title}:${section.resultLabel}',
                  afterHeaderExtent:
                      sectionIndex == firstPackedSection &&
                              showPackedProgress ||
                          section.resultLabel ==
                                  AppI10n.backupDirectCheckMatch &&
                              actionableMatches > 0 ||
                          section.reason ==
                                  BackupReconcileReason.duplicateLiveCopies &&
                              showDuplicateActions
                      ? (sectionIndex == firstPackedSection &&
                                    showPackedProgress
                                ? 74.0
                                : 0.0) +
                            (section.resultLabel ==
                                        AppI10n.backupDirectCheckMatch &&
                                    actionableMatches > 0
                                ? 80.0
                                : 0.0) +
                            (section.reason ==
                                        BackupReconcileReason
                                            .duplicateLiveCopies &&
                                    showDuplicateActions
                                ? duplicateActionsExtent +
                                      (_duplicateLiveProgress == null
                                          ? 0.0
                                          : 74.0)
                                : 0.0)
                      : null,
                  afterHeader:
                      sectionIndex == firstPackedSection &&
                              showPackedProgress ||
                          section.resultLabel ==
                                  AppI10n.backupDirectCheckMatch &&
                              actionableMatches > 0 ||
                          section.reason ==
                                  BackupReconcileReason.duplicateLiveCopies &&
                              showDuplicateActions
                      ? Column(
                          children: <Widget>[
                            if (sectionIndex == firstPackedSection &&
                                showPackedProgress)
                              _InlineReconcileProgress(
                                label: tr(
                                  check.running
                                      ? AppI10n
                                            .backupDirectCheckCheckingContents
                                      : check.cancelled
                                      ? AppI10n.backupDirectCheckPaused
                                      : AppI10n.backupDirectCheckComplete,
                                ),
                                detail: tr(
                                  AppI10n.backupDirectCheckProgress,
                                  namedArgs: <String, String>{
                                    'done': '${check.done}',
                                    'total': '${check.total}',
                                    'matches': '$matches',
                                    'different': '$different',
                                    'review': '$review',
                                  },
                                ),
                                value: check.total == 0
                                    ? 0
                                    : check.done / check.total,
                                colour: Theme.of(context).status.note,
                              ),
                            if (section.resultLabel ==
                                    AppI10n.backupDirectCheckMatch &&
                                actionableMatches > 0)
                              Padding(
                                padding: const EdgeInsets.only(
                                  top: LayoutNums.contentGap,
                                  bottom: LayoutNums.smallGap,
                                ),
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  child: Wrap(
                                    spacing: 8,
                                    runSpacing: 6,
                                    children: <Widget>[
                                      for (final format in <BackupCopyFormat>[
                                        BackupCopyFormat.packed,
                                        BackupCopyFormat.unpacked,
                                      ])
                                        BackupBulkActionButton(
                                          label: tr(
                                            format == BackupCopyFormat.packed
                                                ? AppI10n
                                                      .backupDirectCheckDeletePacked
                                                : AppI10n
                                                      .backupDirectCheckDeleteUnpacked,
                                            namedArgs: <String, String>{
                                              'count': '$actionableMatches',
                                            },
                                          ),
                                          icon: Icons.delete_outline,
                                          colour: Theme.of(context).status.bad,
                                          destructive: true,
                                          onPressed: () =>
                                              deleteEquivalentBackupCopies(
                                                context,
                                                removedFormat: format,
                                              ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            if (section.reason ==
                                    BackupReconcileReason.duplicateLiveCopies &&
                                showDuplicateActions)
                              Padding(
                                padding: const EdgeInsets.only(
                                  top: LayoutNums.contentGap,
                                  bottom: LayoutNums.smallGap,
                                ),
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  child: Wrap(
                                    spacing: 8,
                                    runSpacing: 6,
                                    children: <Widget>[
                                      for (final library
                                          in duplicateLiveLocations)
                                        BackupBulkActionButton(
                                          key: ValueKey<String>(
                                            'backup-delete-duplicate-live-${library.name}',
                                          ),
                                          label: tr(
                                            AppI10n
                                                .backupActionDeleteVerifiedLiveCopies,
                                            namedArgs: <String, String>{
                                              'count':
                                                  '${duplicateCountFor(library)}',
                                              'version': tr(
                                                library ==
                                                        WallpaperLibrary
                                                            .workshop
                                                    ? AppI10n
                                                          .backupDetailWorkshopLive
                                                    : AppI10n
                                                          .backupDetailMyProjectsLive,
                                              ),
                                            },
                                          ),
                                          icon: Icons.delete_outline,
                                          colour: Theme.of(context).status.bad,
                                          destructive: true,
                                          onPressed:
                                              _duplicateLiveProgress != null
                                              ? null
                                              : () => deleteIdenticalLiveCopies(
                                                  context,
                                                  removedLibrary: library,
                                                  onProgress:
                                                      _setDuplicateLiveProgress,
                                                ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            if (section.reason ==
                                BackupReconcileReason.duplicateLiveCopies)
                              if (_duplicateLiveProgress
                                  case final DuplicateLiveOperationProgress
                                      progress)
                                _InlineReconcileProgress(
                                  label: tr(
                                    progress.stage ==
                                            DuplicateLiveOperationStage.checking
                                        ? AppI10n.backupActionCheckingLiveCopies
                                        : AppI10n
                                              .backupActionDeletingLiveCopies,
                                    namedArgs: <String, String>{
                                      'version': tr(
                                        progress.location ==
                                                WallpaperLibrary.workshop
                                            ? AppI10n.backupDetailWorkshopLive
                                            : AppI10n
                                                  .backupDetailMyProjectsLive,
                                      ),
                                    },
                                  ),
                                  detail: tr(
                                    AppI10n.backupActionLiveProgress,
                                    namedArgs: <String, String>{
                                      'done': '${progress.done}',
                                      'total': '${progress.total}',
                                    },
                                  ),
                                  value: progress.total == 0
                                      ? 0
                                      : progress.done / progress.total,
                                  colour: Theme.of(context).status.bad,
                                ),
                          ],
                        )
                      : null,
                  headerPinned: true,
                  headerExtent:
                      sectionIndex == firstPackedSection &&
                          checkableCount > 0 &&
                          backupRoot != null &&
                          MediaQuery.sizeOf(context).width < 1100
                      ? 104
                      : _backupIssueHeaderHeight,
                  header: _BackupIssueHeader(
                    noteKey: ValueKey<String>(
                      'backup-reconcile-note-${section.title}-${section.resultLabel}',
                    ),
                    pinned: true,
                    trailing:
                        sectionIndex == firstPackedSection &&
                            checkableCount > 0 &&
                            backupRoot != null
                        ? BackupBulkActionButton(
                            key: const ValueKey<String>(
                              'backup-check-packed-unpacked',
                            ),
                            label: tr(
                              check.running
                                  ? check.cancelled
                                        ? AppI10n.backupDirectCheckStopping
                                        : AppI10n.backupDirectCheckCancel
                                  : canResume
                                  ? AppI10n.backupDirectCheckResume
                                  : AppI10n.backupDirectCheckStart,
                              namedArgs: <String, String>{
                                'count':
                                    '${canResume ? checkableCount - check.done : checkableCount}',
                              },
                            ),
                            icon: check.running
                                ? Icons.stop_rounded
                                : Icons.fact_check_outlined,
                            colour: Theme.of(context).status.note,
                            onPressed: check.running && check.cancelled
                                ? null
                                : check.running
                                ? batch.cancel
                                : () => batch.start(
                                    scan: scan,
                                    backupRoot: backupRoot,
                                    entries: activeEntries,
                                  ),
                          )
                        : null,
                    child: Text.rich(
                      TextSpan(
                        children: <InlineSpan>[
                          TextSpan(
                            text:
                                '${tr(section.title)}'
                                '${section.resultLabel == null ? '' : ' · ${tr(section.resultLabel!)}'}'
                                ' (${section.tiles.length})'
                                '${section.about == null ? '' : ' - '}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          if (section.about case final String about)
                            TextSpan(text: tr(about)),
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
                  final item = grouped[index];
                  final ReconcileTile tile = item.tile;
                  return ReconcileTileView(
                    key: ValueKey<String>(ids[index]),
                    width: geometry.tile,
                    tile: tile,
                    primaryBadge: item.primaryBadge,
                    contentProbe: check.results[tile.entry.name.toLowerCase()],
                    canDeleteMatchedCopy:
                        BackupDirectBatch.eligible(tile.entry) &&
                        check.results[tile.entry.name.toLowerCase()]?.status ==
                            DirectBackupProbeStatus.candidateMatch,
                    contentScanning:
                        check.running &&
                        !check.cancelled &&
                        BackupDirectBatch.eligible(tile.entry) &&
                        !check.results.containsKey(
                          tile.entry.name.toLowerCase(),
                        ),
                    folders: reconcileFolders(
                      entry: tile.entry,
                      backupRoot: backupRoot,
                      liveWorkshopPath: workshop,
                      liveMyProjectsPath: myProjects,
                    ),
                    backupRoot: backupRoot,
                    liveWorkshopRoot: workshop,
                    liveMyProjectsRoot: myProjects,
                    ignored: false,
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

  Widget _ignoredGrid(
    WidgetRef ref,
    AsyncValue<List<BackupTile>> updateTiles,
    AsyncValue<List<ReconcileTile>> reconcileTiles, {
    required BackupScan scan,
    required String? backupRoot,
    required String? workshop,
    required String? myProjects,
  }) {
    if (updateTiles case AsyncError<List<BackupTile>>(:final Object error)) {
      return Center(child: Text('${tr(AppI10n.backupTilesFailed)} $error'));
    }
    if (reconcileTiles case AsyncError<List<ReconcileTile>>(
      :final Object error,
    )) {
      return Center(child: Text('${tr(AppI10n.backupTilesFailed)} $error'));
    }
    if (updateTiles is! AsyncData<List<BackupTile>> ||
        reconcileTiles is! AsyncData<List<ReconcileTile>>) {
      return ScanProgress(label: tr(AppI10n.backupReadingDetails));
    }

    final List<BackupTile> updates = updateTiles.value;
    final List<ReconcileTile> reconcile = reconcileTiles.value;
    if (updates.isEmpty && reconcile.isEmpty) {
      widget.entrance.discard();
      return const NoResultsView(key: NoResultsView.viewKey);
    }

    widget.entrance.discard();
    final Map<BackupReconcileReason, List<ReconcileTile>> reasonGroups =
        <BackupReconcileReason, List<ReconcileTile>>{
          for (final BackupReconcileReason reason
              in BackupReconcileReason.values)
            reason: <ReconcileTile>[],
        };
    for (final ReconcileTile tile in reconcile) {
      for (final BackupReconcileReason reason in tile.entry.ignoredReasons) {
        reasonGroups[reason]!.add(tile);
      }
    }

    final List<_IgnoredGridItem> grouped = <_IgnoredGridItem>[
      for (final BackupTile tile in updates)
        (update: tile, reconcile: null, reason: null),
      for (final BackupReconcileReason reason in BackupReconcileReason.values)
        for (final ReconcileTile tile in reasonGroups[reason]!)
          (update: null, reconcile: tile, reason: reason),
    ];
    final List<String> ids = <String>[
      for (final _IgnoredGridItem item in grouped)
        item.update?.card.id ??
            ignoredReconcileTileId(item.reconcile!.entry.name, item.reason!),
    ];

    return _selectionGrid(
      ref,
      context,
      id: 'backup-ignored-grid',
      ids: ids,
      padding: EdgeInsets.zero,
      entranceToken: 0,
      entranceOnMount: false,
      reflowIdentity: const ValueKey<String>('ignored-groups'),
      sections: <SelectionGridSection>[
        if (updates.isNotEmpty)
          SelectionGridSection(
            itemCount: updates.length,
            headerPinned: true,
            headerExtent: _backupIssueHeaderHeight,
            header: _BackupIssueHeader(
              noteKey: const ValueKey<String>('backup-ignored-note-update'),
              pinned: true,
              child: Text.rich(
                TextSpan(
                  children: <InlineSpan>[
                    TextSpan(
                      text: '${tr(AppI10n.backupIgnoredGroupUpdateTitle)} - ',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    TextSpan(text: tr(AppI10n.backupIgnoredGroupUpdateAbout)),
                  ],
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        for (final BackupReconcileReason reason in BackupReconcileReason.values)
          if (reasonGroups[reason]!.isNotEmpty)
            SelectionGridSection(
              itemCount: reasonGroups[reason]!.length,
              headerPinned: true,
              headerExtent: _backupIssueHeaderHeight,
              header: _BackupIssueHeader(
                noteKey: ValueKey<String>('backup-ignored-note-${reason.name}'),
                pinned: true,
                child: Text.rich(
                  TextSpan(
                    children: <InlineSpan>[
                      TextSpan(
                        text: '${tr(_reconcileText(reason).title)} - ',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      TextSpan(
                        text: tr(AppI10n.backupIgnoredGroupReconcileAbout),
                      ),
                    ],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
      ],
      itemBuilder: (BuildContext context, int index, GridGeometry geometry) {
        final _IgnoredGridItem item = grouped[index];
        if (item.update case final BackupTile tile) {
          return BackupTileView(
            key: ValueKey<String>(ids[index]),
            width: geometry.tile,
            tile: tile,
            backupRoot: backupRoot,
            folders: cardFolders(
              library: tile.card.library,
              name: tile.card.name,
              liveExists: scan.presence[tile.card.id]?.live ?? false,
              backupExists: scan.presence[tile.card.id]?.backup ?? false,
              backupRoot: backupRoot,
              liveWorkshopPath: workshop,
              liveMyProjectsPath: myProjects,
            ),
            onTap: () => _click(ref, ids, index),
            onAction: () => applyBackupAction(
              context,
              BackupAction.showUpdateAgain,
              <BackupCard>[tile.card],
            ),
          );
        }
        final ReconcileTile tile = item.reconcile!;
        return ReconcileTileView(
          key: ValueKey<String>(ids[index]),
          width: geometry.tile,
          tile: tile,
          ignored: true,
          reasonOverride: item.reason,
          selectionIdOverride: ids[index],
          folders: reconcileFolders(
            entry: tile.entry,
            backupRoot: backupRoot,
            liveWorkshopPath: workshop,
            liveMyProjectsPath: myProjects,
          ),
          backupRoot: backupRoot,
          liveWorkshopRoot: workshop,
          liveMyProjectsRoot: myProjects,
          onTap: () => _click(ref, ids, index),
        );
      },
    );
  }

  Widget _updateSyncGrid(
    WidgetRef ref,
    AsyncValue<List<BackupTile>> tiles, {
    required BackupScan scan,
    required BackupResolvedIssuesState resolved,
    required String? backupRoot,
    required String? workshop,
    required String? myProjects,
  }) {
    return switch (tiles) {
      AsyncData<List<BackupTile>>(value: final List<BackupTile> value)
          when value.isEmpty =>
        Builder(
          builder: (_) {
            widget.entrance.discard();
            return const NoResultsView(key: NoResultsView.viewKey);
          },
        ),
      AsyncData<List<BackupTile>>(:final List<BackupTile> value) => Builder(
        builder: (BuildContext context) {
          final List<BackupTile> updates = [];
          final List<BackupTile> syncs = [];
          final List<BackupTile> both = [];
          for (final BackupTile tile in value) {
            final BackupUpdatePlan plan =
                visibleBackupUpdatePlan(scan, resolved, tile.card) ??
                const BackupUpdatePlan(updateContent: true);
            if (plan.updateContent && plan.needsSync) {
              both.add(tile);
            } else if (plan.needsSync) {
              syncs.add(tile);
            } else {
              updates.add(tile);
            }
          }
          final List<({String title, List<BackupTile> tiles})> sections = [
            (title: AppI10n.backupUpdateOnlyTitle, tiles: updates),
            (title: AppI10n.backupSyncOnlyTitle, tiles: syncs),
            (title: AppI10n.backupUpdateSyncTitle, tiles: both),
          ];
          final List<BackupTile> grouped = [
            for (final section in sections) ...section.tiles,
          ];
          final List<String> ids = [for (final tile in grouped) tile.card.id];
          return _selectionGrid(
            ref,
            context,
            id: 'backup-grid',
            ids: ids,
            reflowIdentity: BackupState.updateAvailable,
            animateGroupedChanges: true,
            sections: [
              for (final section in sections)
                if (section.tiles.isNotEmpty)
                  SelectionGridSection(
                    itemCount: section.tiles.length,
                    identity: section.title,
                    headerPinned: true,
                    headerExtent: _backupIssueHeaderHeight,
                    header: _BackupIssueHeader(
                      noteKey: ValueKey<String>(
                        'backup-update-sync-${section.title}',
                      ),
                      pinned: true,
                      child: Text(
                        '${tr(section.title)} (${section.tiles.length})',
                      ),
                    ),
                  ),
            ],
            itemBuilder:
                (BuildContext context, int index, GridGeometry geometry) {
                  final BackupTile tile = grouped[index];
                  return BackupTileView(
                    key: ValueKey<String>(ids[index]),
                    width: geometry.tile,
                    tile: tile,
                    updatePlan: visibleBackupUpdatePlan(
                      scan,
                      resolved,
                      tile.card,
                    ),
                    backupRoot: backupRoot,
                    folders: cardFolders(
                      library: tile.card.library,
                      name: tile.card.name,
                      liveExists: scan.presence[tile.card.id]?.live ?? false,
                      backupExists:
                          scan.presence[tile.card.id]?.backup ?? false,
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
      AsyncError<List<BackupTile>>(:final Object error) => Center(
        child: Text('${tr(AppI10n.backupTilesFailed)} $error'),
      ),
      _ => const _Scanning(idle: AppI10n.backupPreparingGrid),
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
                        child: BackupBulkActionButton(
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
                    backupRoot: backupRoot,
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
    final BackupResolvedIssuesState resolved = ref.watch(
      backupResolvedIssuesProvider,
    );
    final Map<String, ({bool live, bool backup})> presence = scan.presence;
    final BackupShown shown = ref.watch(backupStateFilterProvider);
    late final Widget grid;
    if (shown.ignored) {
      grid = _ignoredGrid(
        ref,
        ref.watch(backupVisibleTilesProvider),
        ref.watch(backupVisibleReconcileTilesProvider),
        scan: scan,
        backupRoot: backupRoot,
        workshop: workshop,
        myProjects: myProjects,
      );
    } else if (shown.reconcile) {
      final AsyncValue<List<ReconcileTile>> tiles = ref.watch(
        backupVisibleReconcileTilesProvider,
      );
      grid = ValueListenableBuilder<BackupDirectBatchState>(
        valueListenable: ref.read(backupDirectBatchProvider),
        builder: (context, _, _) => _reconcileGrid(
          ref,
          tiles,
          scan: scan,
          backupRoot: backupRoot,
          workshop: workshop,
          myProjects: myProjects,
        ),
      );
    } else if (shown.state == BackupState.updateAvailable) {
      grid = _updateSyncGrid(
        ref,
        ref.watch(backupVisibleTilesProvider),
        scan: scan,
        resolved: resolved,
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
              updatePlan: visibleBackupUpdatePlan(scan, resolved, tile.card),
              backupRoot: backupRoot,
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
