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
          title: AppI10n.backupReconcileReasonDuplicateLiveTitle,
          about: AppI10n.backupReconcileReasonDuplicateLiveGroupAbout,
        ),
        BackupReconcileReason.conflictingBackupCopies => (
          title: AppI10n.backupReconcileReasonConflictingBackupsTitle,
          about: AppI10n.backupReconcileReasonConflictingBackupsAbout,
        ),
        BackupReconcileReason.comparisonUnavailable => (
          title: AppI10n.backupReconcileReasonComparisonUnavailableTitle,
          about: AppI10n.backupReconcileReasonComparisonUnavailableAbout,
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
              final BackupReconcileReason? reason =
                  tile.entry.activePrimaryReason;
              if (reason != null) groups[reason]!.add(tile);
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
