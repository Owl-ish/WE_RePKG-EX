part of 'content_details.dart';

//====================
// Update Detail Layout
//====================
/// Presents the content and placement changes contained in one Update plan.
///
/// This layer explains the plan and opens the shared file view for choices.
/// Filesystem mutation remains owned by the Backup action/core layers.
class UpdatePlanDetailContent extends StatelessWidget {
  const UpdatePlanDetailContent({
    super.key,
    required this.plan,
    required this.card,
    required this.foreground,
  });

  final BackupUpdatePlan plan;
  final BackupCard card;
  final Color foreground;

  String _backupLabel(WallpaperLibrary library) {
    final String root = tr(switch (library) {
      WallpaperLibrary.workshop => AppI10n.backupFolderBackupWorkshop,
      WallpaperLibrary.myProjects => AppI10n.backupFolderBackupMyProjects,
    });
    return '$root / ${card.name}';
  }

  Widget _syncDetail(BackupSyncPlan sync) => switch (sync.kind) {
    BackupSyncKind.relocate => SyncMoveDetail(
      fromPath: _backupLabel(sync.from),
      toPath: _backupLabel(sync.to),
      foreground: foreground,
    ),
    BackupSyncKind.removeDuplicate => SyncDuplicateDetail(
      keepPath: _backupLabel(sync.to),
      removePath: _backupLabel(sync.from),
      foreground: foreground,
    ),
  };

  @override
  Widget build(BuildContext context) {
    final BackupSyncPlan? sync = plan.sync;
    final Widget? syncDetail = sync == null ? null : _syncDetail(sync);
    if (plan.updateContent) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(
            child: BackupDetailScrollView(
              padding: const EdgeInsets.only(right: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  BackupDetailGroup(
                    title: tr(AppI10n.backupTileUpdate),
                    items: <String>[tr(AppI10n.backupDetailUpdateToLive)],
                    foreground: foreground,
                  ),
                  if (syncDetail != null) ...<Widget>[
                    const SizedBox(height: 10),
                    syncDetail,
                  ],
                ],
              ),
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (syncDetail != null)
          Expanded(
            child: Align(
              key: const ValueKey<String>('backup-sync-only-content'),
              alignment: Alignment.center,
              child: SizedBox(width: double.infinity, child: syncDetail),
            ),
          ),
      ],
    );
  }
}

//========================
// File Difference Explorer
//========================
/// Loads and renders the live-to-backup difference set for a detailed Update.
///
/// Comparison stays lazy so opening a tile does not recursively inspect every
/// file until the detail area actually needs that information.
List<FileTreeCompareCandidate> _manualCompareCandidates({
  required List<String> paths,
  required String side,
  required String? folder,
  required String? label,
}) {
  if (folder == null) return const <FileTreeCompareCandidate>[];
  final List<String> ordered = List<String>.from(paths)
    ..sort((String a, String b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return <FileTreeCompareCandidate>[
    for (final String filePath in ordered)
      FileTreeCompareCandidate(
        id: '$side::$filePath',
        path: path.join(folder, filePath),
        label: label ?? path.basename(folder),
      ),
  ];
}

FileTreeCompareAction _fileCompareAction({
  Key? key,
  required String firstLabel,
  required String firstPath,
  required String secondLabel,
  required String secondPath,
  required Color foreground,
  bool hoverInert = false,
}) => FileTreeCompareAction(
  key: key,
  first: FileComparisonSide(label: firstLabel, path: firstPath),
  second: FileComparisonSide(label: secondLabel, path: secondPath),
  title: tr(AppI10n.backupDetailCompareFiles),
  tooltip: tr(AppI10n.backupDetailCompareFiles),
  unavailableText: tr(AppI10n.backupDetailFileUnavailable),
  jsonModeLabel: tr(AppI10n.backupDetailStructuredJson),
  textModeLabel: tr(AppI10n.backupDetailTextComparison),
  jsonNoDifferencesText: tr(AppI10n.backupDetailJsonFormattingOnly),
  missingValueText: tr(AppI10n.backupDetailValueMissing),
  truncatedText: tr(AppI10n.backupDetailTextPreviewTruncated),
  binaryModeLabel: tr(AppI10n.backupDetailBinaryComparison),
  fileTypeLabel: tr(AppI10n.backupDetailFileType),
  fileSizeLabel: tr(AppI10n.backupDetailFileSize),
  fileModifiedLabel: tr(AppI10n.backupDetailFileModified),
  hashLabel: tr(AppI10n.backupDetailSha256),
  sameText: tr(AppI10n.backupDetailSame),
  differentText: tr(AppI10n.backupDetailDifferent),
  noExtensionText: tr(AppI10n.backupDetailNoExtension),
  imageZoomOutTooltip: tr(AppI10n.backupDetailImageZoomOut),
  imageResetViewTooltip: tr(AppI10n.backupDetailImageResetView),
  imageZoomInTooltip: tr(AppI10n.backupDetailImageZoomIn),
  imageLinkViewsTooltip: tr(AppI10n.backupDetailImageLinkViews),
  imageUnlinkViewsTooltip: tr(AppI10n.backupDetailImageUnlinkViews),
  imageSideBySideLabel: tr(AppI10n.backupDetailImageSideBySide),
  imageOverlayLabel: tr(AppI10n.backupDetailImageOverlay),
  imageBlinkLabel: tr(AppI10n.backupDetailImageBlink),
  imageDifferenceLabel: tr(AppI10n.backupDetailImageDifference),
  imageOverlayOpacityLabel: tr(AppI10n.backupDetailImageOverlayOpacity),
  imageDifferenceSameHint: tr(AppI10n.backupDetailImageDifferenceSameHint),
  imageDifferenceIntensityLabel: tr(
    AppI10n.backupDetailImageDifferenceIntensity,
  ),
  imageDifferenceSizeMismatch: tr(
    AppI10n.backupDetailImageDifferenceSizeMismatch,
  ),
  foreground: foreground,
  hoverInert: hoverInert,
);

FileTreeContextAction _compareContextAction(
  FileTreeCompareAction action, {
  bool enabled = true,
}) => FileTreeContextAction(
  label: tr(AppI10n.backupDetailCompareFiles),
  enabled: enabled && action.enabled,
  onSelected: (BuildContext context) => action.open(context),
);

FileTreeCompareAction? _selectedManualCompareAction({
  required List<FileTreeCompareCandidate> candidates,
  required Set<String> selectedIds,
  required Color foreground,
}) {
  final List<FileTreeCompareCandidate> selected = candidates
      .where(
        (FileTreeCompareCandidate candidate) =>
            selectedIds.contains(candidate.id),
      )
      .toList();
  if (selected.length != 2) return null;
  return _fileCompareAction(
    firstLabel: selected[0].label,
    firstPath: selected[0].path,
    secondLabel: selected[1].label,
    secondPath: selected[1].path,
    foreground: foreground,
  );
}

typedef _DisplayedFileChanges = ({
  BackupFileChanges changes,
  List<String> matching,
});

/// Update comparison using the detail session's existing file choices.
class UpdateFileChanges extends StatefulWidget {
  const UpdateFileChanges({
    super.key,
    this.wallpaper,
    required this.wallpaperName,
    required this.liveFolder,
    required this.backupFolder,
    required this.sourceLabel,
    required this.destinationLabel,
    required this.rePKGPath,
    required this.foreground,
    required this.selection,
    this.includeMatchingFiles = false,
    this.sourceOnlyTitle,
    this.destinationOnlyTitle,
    this.sourceActions,
    this.destinationActions,
    this.bidirectional = false,
    this.overview,
  });

  final WallpaperInfo? wallpaper;
  final String wallpaperName;
  final String? liveFolder;
  final String? backupFolder;
  final String sourceLabel;
  final String destinationLabel;
  final String? rePKGPath;
  final Color foreground;
  final BackupUpdateSelection? selection;
  final bool includeMatchingFiles;
  final String? sourceOnlyTitle;
  final String? destinationOnlyTitle;
  final Widget? sourceActions;
  final Widget? destinationActions;
  final bool bidirectional;
  final FolderFileOverview? overview;

  @override
  State<UpdateFileChanges> createState() => _UpdateFileChangesState();
}

class _UpdateFileChangesState extends State<UpdateFileChanges> {
  late Future<_DisplayedFileChanges?> _changes;
  final FileTreeCompareSelection _manualCompare = FileTreeCompareSelection();

  @override
  void initState() {
    super.initState();
    _changes = _loadChanges();
  }

  @override
  void didUpdateWidget(covariant UpdateFileChanges oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.liveFolder != widget.liveFolder ||
        oldWidget.backupFolder != widget.backupFolder ||
        oldWidget.selection != widget.selection ||
        oldWidget.includeMatchingFiles != widget.includeMatchingFiles ||
        oldWidget.overview != widget.overview) {
      _changes = _loadChanges();
      _manualCompare.clear();
    }
  }

  Future<_DisplayedFileChanges?> _loadChanges() async {
    final BackupUpdateSelection? selection = widget.selection;
    if (selection == null) {
      final FolderFileOverview? overview = widget.overview;
      return overview == null ? _read() : _displayedOverview(overview);
    }
    final BackupFileChanges? changes = await selection.changes;
    return changes == null
        ? null
        : (changes: changes, matching: const <String>[]);
  }

  Future<_DisplayedFileChanges?> _read() async {
    final String? live = widget.liveFolder;
    final String? backup = widget.backupFolder;
    if (live == null || backup == null) return null;
    final FolderFileComparison? comparison = await compareFolderFilesDetailed(
      firstFolder: live,
      secondFolder: backup,
    );
    return comparison == null ? null : _displayedComparison(comparison);
  }

  _DisplayedFileChanges _displayedComparison(FolderFileComparison comparison) {
    return (
      changes: (
        modified: comparison.changes.modified,
        onlyLive: comparison.changes.onlyFirst,
        onlyBackup: comparison.changes.onlySecond,
      ),
      matching: widget.includeMatchingFiles
          ? comparison.matching
          : const <String>[],
    );
  }

  _DisplayedFileChanges _displayedOverview(FolderFileOverview overview) => (
    changes: (
      modified: overview.differentSize,
      onlyLive: overview.onlyFirst,
      onlyBackup: overview.onlySecond,
    ),
    matching: overview.shared,
  );

  void _selectManualCompare(
    List<FileTreeCompareCandidate> visible,
    FileTreeCompareCandidate candidate,
    bool control,
    bool shift,
  ) {
    setState(() {
      _manualCompare.click(visible, candidate, control: control, shift: shift);
    });
  }

  @override
  Widget build(BuildContext context) {
    final BackupUpdateSelection? selection = widget.selection;
    if (selection == null) return _buildChanges(context);
    return AnimatedBuilder(
      animation: selection,
      builder: (BuildContext context, Widget? _) => _buildChanges(context),
    );
  }

  Widget _buildChanges(BuildContext context) =>
      FutureBuilder<_DisplayedFileChanges?>(
        future: _changes,
        initialData: widget.overview == null
            ? null
            : _displayedOverview(widget.overview!),
        builder:
            (
              BuildContext context,
              AsyncSnapshot<_DisplayedFileChanges?> snapshot,
            ) {
              final _DisplayedFileChanges? displayed = snapshot.data;
              if (displayed == null &&
                  snapshot.connectionState != ConnectionState.done) {
                return FileTreeSurface(
                  foreground: widget.foreground,
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Row(
                      children: <Widget>[
                        SizedBox.square(
                          dimension: 15,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: widget.foreground.withValues(alpha: .7),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            tr(AppI10n.backupDetailComparingFiles),
                            style: TextStyle(color: widget.foreground),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }
              if (snapshot.hasError || displayed == null) {
                return _fileChangeMessage(
                  tr(AppI10n.backupDetailFileComparisonUnavailable),
                );
              }
              final BackupFileChanges changes = displayed.changes;
              final int total =
                  changes.modified.length +
                  changes.onlyLive.length +
                  changes.onlyBackup.length +
                  displayed.matching.length;
              if (total == 0 &&
                  widget.sourceActions == null &&
                  widget.destinationActions == null) {
                return _fileChangeMessage(
                  tr(AppI10n.backupDetailNoFileDifferences),
                );
              }
              final List<FileTreeCompareCandidate> compareCandidates =
                  <FileTreeCompareCandidate>[
                    ..._manualCompareCandidates(
                      paths: changes.onlyLive,
                      side: 'live',
                      folder: widget.liveFolder,
                      label: widget.sourceLabel,
                    ),
                    ..._manualCompareCandidates(
                      paths: changes.onlyBackup,
                      side: 'backup',
                      folder: widget.backupFolder,
                      label: widget.destinationLabel,
                    ),
                  ];
              final FileTreeCompareAction? manualCompareAction =
                  _selectedManualCompareAction(
                    candidates: compareCandidates,
                    selectedIds: _manualCompare.selected,
                    foreground: widget.foreground,
                  );
              final StatusPalette colours = Theme.of(context).status;
              final BackupUpdateSelection? selection = widget.selection;
              return _PairedUpdateTree(
                key: const ValueKey<String>('backup-update-file-tree'),
                configuration: widget,
                changes: changes,
                matching: displayed.matching,
                manualSelection: _manualCompare,
                manualAction: manualCompareAction,
                onCompareSelect: (candidate, control, shift) =>
                    _selectManualCompare(
                      compareCandidates,
                      candidate,
                      control,
                      shift,
                    ),
                toolbar: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    if (compareCandidates.length >= 2)
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: FileTreeCompareBar(
                          keyBase: 'backup-manual-compare',
                          candidates: compareCandidates,
                          selection: _manualCompare,
                          foreground: widget.foreground,
                          label: tr(AppI10n.backupDetailCompareFiles),
                          clearTooltip: tr(AppI10n.backupDetailDeselectAll),
                          actionBuilder: (key, first, second) =>
                              _fileCompareAction(
                                key: key,
                                firstLabel: first.label,
                                firstPath: first.path,
                                secondLabel: second.label,
                                secondPath: second.path,
                                foreground: widget.foreground,
                              ),
                          onClear: () => setState(_manualCompare.clear),
                        ),
                      ),
                    Wrap(
                      spacing: 12,
                      children: <Widget>[
                        if (changes.modified.isNotEmpty)
                          FileTreeGroupHeader(
                            title: tr(AppI10n.backupDetailModified),
                            count: changes.modified.length,
                            accent: colours.warn,
                            foreground: widget.foreground,
                            trailing: selection == null
                                ? null
                                : _copyGroupChoice(
                                    selection,
                                    changes.modified,
                                    widget.foreground,
                                    keyBase: 'modified',
                                  ),
                          ),
                        if (changes.onlyLive.isNotEmpty)
                          FileTreeGroupHeader(
                            title:
                                widget.sourceOnlyTitle ??
                                tr(AppI10n.backupDetailAddedFiles),
                            count: changes.onlyLive.length,
                            accent: colours.good,
                            foreground: widget.foreground,
                            trailing: selection == null
                                ? null
                                : _copyGroupChoice(
                                    selection,
                                    changes.onlyLive,
                                    widget.foreground,
                                    keyBase: 'only-live',
                                  ),
                          ),
                        if (changes.onlyBackup.isNotEmpty)
                          FileTreeGroupHeader(
                            title:
                                widget.destinationOnlyTitle ??
                                tr(AppI10n.backupDetailRemovedFiles),
                            count: changes.onlyBackup.length,
                            accent: colours.note,
                            foreground: widget.foreground,
                            trailing: selection == null
                                ? null
                                : _deletionGroupChoice(
                                    selection,
                                    changes.onlyBackup,
                                    widget.foreground,
                                    keyBase: 'only-backup',
                                  ),
                          ),
                        if (displayed.matching.isNotEmpty)
                          FileTreeGroupHeader(
                            title: tr(AppI10n.backupDetailMatchingFiles),
                            count: displayed.matching.length,
                            accent: colours.good,
                            foreground: widget.foreground,
                          ),
                      ],
                    ),
                  ],
                ),
              );
            },
      );

  Widget _fileChangeMessage(String text) => FileTreeSurface(
    foreground: widget.foreground,
    child: Padding(
      padding: const EdgeInsets.all(10),
      child: Text(
        text,
        style: TextStyle(color: widget.foreground, height: 1.3),
      ),
    ),
  );
}
