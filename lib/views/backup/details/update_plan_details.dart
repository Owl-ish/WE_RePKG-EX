part of 'content_details.dart';

//====================
// Update Detail Layout
//====================
/// Presents the content and placement changes contained in one Update plan.
///
/// This layer only explains the plan and collects optional per-file choices.
/// Filesystem mutation remains owned by the Backup action/core layers.
class UpdatePlanDetailContent extends StatelessWidget {
  const UpdatePlanDetailContent({
    super.key,
    required this.plan,
    required this.card,
    required this.liveFolder,
    required this.backupFolder,
    required this.foreground,
    required this.focused,
    required this.needsFocus,
    required this.rePKGPath,
    required this.selection,
    this.onRequestFocus,
  });

  final BackupUpdatePlan plan;
  final BackupCard card;
  final String? liveFolder;
  final String? backupFolder;
  final Color foreground;
  final bool focused;
  final bool needsFocus;
  final String? rePKGPath;
  final BackupUpdateSelection? selection;
  final VoidCallback? onRequestFocus;

  String _liveLabel(WallpaperLibrary library) {
    final String root = tr(switch (library) {
      WallpaperLibrary.workshop => AppI10n.homeLibraryWorkshop,
      WallpaperLibrary.myProjects => AppI10n.homeLibraryMyProjects,
    });
    return '$root / ${card.name}';
  }

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
    if (plan.updateContent && needsFocus && !focused) {
      return BackupDetailScrollView(
        padding: const EdgeInsets.only(right: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            BackupDetailGroup(
              title: tr(AppI10n.backupTileUpdate),
              items: <String>[tr(AppI10n.backupDetailUpdateToLive)],
              foreground: foreground,
            ),
            BackupDetailExpandPrompt(
              key: const ValueKey<String>('backup-update-expand-file-changes'),
              title: tr(AppI10n.backupDetailFileChanges),
              subtitle: tr(AppI10n.backupDetailExpandFileChanges),
              foreground: foreground,
              onPressed: onRequestFocus ?? () {},
            ),
            if (syncDetail != null) ...<Widget>[
              const SizedBox(height: 10),
              syncDetail,
            ],
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (plan.updateContent)
          BackupDetailGroup(
            title: tr(AppI10n.backupTileUpdate),
            items: <String>[tr(AppI10n.backupDetailUpdateToLive)],
            foreground: foreground,
          ),
        if (plan.updateContent && (!needsFocus || focused))
          Expanded(
            child: _UpdateFileChanges(
              wallpaperName: card.name,
              liveFolder: liveFolder,
              backupFolder: backupFolder,
              sourceLabel: _liveLabel(card.library),
              destinationLabel: _backupLabel(card.library),
              rePKGPath: rePKGPath,
              foreground: foreground,
              selection: selection,
            ),
          ),
        if (!plan.updateContent && syncDetail != null)
          Expanded(
            child: Align(
              key: const ValueKey<String>('backup-sync-only-content'),
              alignment: Alignment.center,
              child: SizedBox(width: double.infinity, child: syncDetail),
            ),
          )
        else if (syncDetail != null) ...<Widget>[
          const SizedBox(height: 10),
          syncDetail,
        ],
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

class _UpdateFileChanges extends StatefulWidget {
  const _UpdateFileChanges({
    required this.wallpaperName,
    required this.liveFolder,
    required this.backupFolder,
    required this.sourceLabel,
    required this.destinationLabel,
    required this.rePKGPath,
    required this.foreground,
    required this.selection,
  });

  final String wallpaperName;
  final String? liveFolder;
  final String? backupFolder;
  final String sourceLabel;
  final String destinationLabel;
  final String? rePKGPath;
  final Color foreground;
  final BackupUpdateSelection? selection;

  @override
  State<_UpdateFileChanges> createState() => _UpdateFileChangesState();
}

class _UpdateFileChangesState extends State<_UpdateFileChanges> {
  late Future<BackupFileChanges?> _changes;
  final FileTreeCompareSelection _manualCompare = FileTreeCompareSelection();

  @override
  void initState() {
    super.initState();
    _changes = widget.selection?.changes ?? _read();
  }

  @override
  void didUpdateWidget(covariant _UpdateFileChanges oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.liveFolder != widget.liveFolder ||
        oldWidget.backupFolder != widget.backupFolder ||
        oldWidget.selection != widget.selection) {
      _changes = widget.selection?.changes ?? _read();
      _manualCompare.clear();
    }
  }

  Future<BackupFileChanges?> _read() async {
    final String? live = widget.liveFolder;
    final String? backup = widget.backupFolder;
    if (live == null || backup == null) return null;
    return compareBackupFileChanges(liveFolder: live, backupFolder: backup);
  }

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
      FutureBuilder<BackupFileChanges?>(
        future: _changes,
        builder:
            (BuildContext context, AsyncSnapshot<BackupFileChanges?> snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
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
              final BackupFileChanges? changes = snapshot.data;
              if (snapshot.hasError || changes == null) {
                return _fileChangeMessage(
                  tr(AppI10n.backupDetailFileComparisonUnavailable),
                );
              }
              final int total =
                  changes.modified.length +
                  changes.onlyLive.length +
                  changes.onlyBackup.length;
              if (total == 0) {
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
              return FileTreeScrollView(
                key: const ValueKey<String>('backup-update-file-tree'),
                foreground: widget.foreground,
                semanticLabel: '${tr(AppI10n.backupDetailFileChanges)}: $total',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    FileTreeRouteBanner(
                      source: widget.sourceLabel,
                      destination: widget.destinationLabel,
                      foreground: widget.foreground,
                    ),
                    if (compareCandidates.length >= 2)
                      FileTreeCompareBar(
                        keyBase: 'backup-manual-compare',
                        candidates: compareCandidates,
                        selection: _manualCompare,
                        foreground: widget.foreground,
                        label: tr(AppI10n.backupDetailCompareFiles),
                        clearTooltip: tr(AppI10n.backupDetailDeselectAll),
                        actionBuilder:
                            (
                              Key key,
                              FileTreeCompareCandidate first,
                              FileTreeCompareCandidate second,
                            ) => _fileCompareAction(
                              key: key,
                              firstLabel: first.label,
                              firstPath: first.path,
                              secondLabel: second.label,
                              secondPath: second.path,
                              foreground: widget.foreground,
                            ),
                        onClear: () {
                          setState(_manualCompare.clear);
                        },
                      ),
                    if (changes.modified.isNotEmpty)
                      _ChangedFileGroup(
                        title: tr(AppI10n.backupDetailModified),
                        paths: changes.modified,
                        wallpaperName: widget.wallpaperName,
                        leftFolder: widget.liveFolder!,
                        rightFolder: widget.backupFolder!,
                        leftLabel: widget.sourceLabel,
                        rightLabel: widget.destinationLabel,
                        directionalVisual: true,
                        rePKGPath: widget.rePKGPath,
                        colour: colours.warn,
                        foreground: widget.foreground,
                        selection: widget.selection,
                        groupChoiceKey: 'modified',
                      ),
                    if (changes.onlyLive.isNotEmpty)
                      _pathDifferenceGroup(
                        title: tr(AppI10n.backupDetailAddedFiles),
                        paths: changes.onlyLive,
                        previewFolder: widget.liveFolder,
                        previewLabel: widget.sourceLabel,
                        colour: colours.good,
                        foreground: widget.foreground,
                        selection: widget.selection,
                        groupChoiceKey: 'only-live',
                        compareSide: 'live',
                        compareSelection: _manualCompare.selected,
                        manualCompareAction: manualCompareAction,
                        onCompareSelect:
                            (
                              FileTreeCompareCandidate candidate,
                              bool control,
                              bool shift,
                            ) => _selectManualCompare(
                              compareCandidates,
                              candidate,
                              control,
                              shift,
                            ),
                      ),
                    if (changes.onlyBackup.isNotEmpty)
                      _pathDifferenceGroup(
                        title: tr(AppI10n.backupDetailRemovedFiles),
                        paths: changes.onlyBackup,
                        previewFolder: widget.backupFolder,
                        previewLabel: widget.destinationLabel,
                        colour: colours.note,
                        foreground: widget.foreground,
                        selection: widget.selection,
                        deletion: true,
                        groupChoiceKey: 'only-backup',
                        compareSide: 'backup',
                        compareSelection: _manualCompare.selected,
                        manualCompareAction: manualCompareAction,
                        onCompareSelect:
                            (
                              FileTreeCompareCandidate candidate,
                              bool control,
                              bool shift,
                            ) => _selectManualCompare(
                              compareCandidates,
                              candidate,
                              control,
                              shift,
                            ),
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
