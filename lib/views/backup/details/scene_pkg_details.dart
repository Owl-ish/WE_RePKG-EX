part of 'content_details.dart';

Future<bool> _confirmPackageInspection(
  BuildContext context,
  ScenePkgInspectionSession session,
) async {
  await session.prepareTemporaryBase();
  if (!context.mounted) return false;
  final String tempBasePath = session.temporaryBasePath;
  return showConfirmDialog(
    title: tr(AppI10n.backupDetailInspectPackageTitle),
    message: tr(AppI10n.backupDetailInspectPackageMessage),
    confirmLabel: tr(AppI10n.backupDetailInspectPackageAction),
    destructive: false,
    pathDetails: <ConfirmPathDetail>[
      (
        label: tr(AppI10n.backupDetailTemporaryFolder),
        path: tempBasePath,
        copyTooltip: tr(AppI10n.backupDetailCopyTemporaryFolder),
        openTooltip: tr(AppI10n.backupDetailOpenTemporaryFolder),
        onOpen: () => browserFolder(tempBasePath),
      ),
    ],
  );
}

//========================
// scene.pkg Inspection UI
//========================
/// Presents opt-in scene.pkg inspection inside the file-difference tree.
///
/// Confirmation, localized errors, previews, and Backup choices live here.
/// RePKG execution, cancellation, comparison, and temporary-folder lifetime are
/// delegated to [ScenePkgInspectionSession].
List<Widget> _nestedDifferenceRows({
  required String title,
  required List<String> paths,
  required Color colour,
  required Color foreground,
  required String firstFolder,
  required String? firstLabel,
  String? secondFolder,
  String? secondLabel,
  bool directional = false,
  BackupUpdateSelection? selection,
  String? packagePath,
  bool deletion = false,
  String? compareSide,
  Set<String> compareSelection = const <String>{},
  FileTreeCompareAction? manualCompareAction,
  void Function(FileTreeCompareCandidate, bool, bool)? onCompareSelect,
  Widget Function(String)? saveAction,
}) {
  final List<String> ordered = List<String>.from(paths)
    ..sort((String a, String b) => a.toLowerCase().compareTo(b.toLowerCase()));
  if (ordered.isEmpty) return const <Widget>[];

  final BackupUpdateSelection? activeSelection = selection;
  final String? activePackagePath = packagePath;
  FileTreeRowChoice? groupChoice;
  if (activeSelection != null && activePackagePath != null) {
    groupChoice = deletion
        ? _deletionGroupChoice(
            activeSelection,
            ordered,
            foreground,
            keyBase: 'package-$activePackagePath-$title',
            packagePath: activePackagePath,
          )
        : _copyGroupChoice(
            activeSelection,
            ordered,
            foreground,
            keyBase: 'package-$activePackagePath-$title',
            packagePath: activePackagePath,
          );
  }

  return <Widget>[
    FileTreeRow(
      depth: 3,
      icon: Icons.folder_open_rounded,
      iconColor: colour,
      label: '$title (${ordered.length})',
      foreground: foreground,
      choice: groupChoice,
      hoverHighlight: false,
    ),
    for (final String filePath in ordered)
      _differenceFileEntry(
        depth: 4,
        filePath: filePath,
        colour: colour,
        foreground: foreground,
        firstFolder: firstFolder,
        firstLabel: firstLabel,
        secondFolder: secondFolder,
        secondLabel: secondLabel,
        directional: directional,
        subtitle:
            deletion && activeSelection != null && activePackagePath != null
            ? _deletionSubtitle(
                activeSelection,
                filePath,
                packagePath: activePackagePath,
              )
            : null,
        choice: activeSelection == null || activePackagePath == null
            ? null
            : deletion
            ? _deletionChoice(
                activeSelection,
                filePath,
                foreground,
                packagePath: activePackagePath,
              )
            : _copyChoice(
                activeSelection,
                filePath,
                foreground,
                packagePath: activePackagePath,
              ),
        compareCandidate: compareSide == null
            ? null
            : FileTreeCompareCandidate(
                id: '$compareSide::$filePath',
                path: path.join(firstFolder, filePath),
                label: firstLabel ?? path.basename(firstFolder),
              ),
        compareSelection: compareSelection,
        manualCompareAction: manualCompareAction,
        onCompareSelect: onCompareSelect,
        extraTrailing: saveAction?.call(filePath),
        hoverHighlight: false,
      ),
  ];
}

class _ScenePkgInspector extends StatefulWidget {
  const _ScenePkgInspector({
    required this.wallpaperName,
    required this.filePath,
    required this.leftFolder,
    required this.rightFolder,
    required this.leftLabel,
    required this.rightLabel,
    required this.directionalVisual,
    required this.rePKGPath,
    required this.foreground,
    required this.accent,
    this.leftOnlyLabel,
    this.rightOnlyLabel,
    this.selection,
    this.confirmedSession,
    this.fullView = false,
  });

  final String wallpaperName;
  final String filePath;
  final String leftFolder;
  final String rightFolder;
  final String? leftLabel;
  final String? rightLabel;
  final bool directionalVisual;
  final String? rePKGPath;
  final Color foreground;
  final Color accent;
  final String? leftOnlyLabel;
  final String? rightOnlyLabel;
  final BackupUpdateSelection? selection;
  final ScenePkgInspectionSession? confirmedSession;
  final bool fullView;

  @override
  State<_ScenePkgInspector> createState() => _ScenePkgInspectorState();
}

class _ScenePkgInspectorState extends State<_ScenePkgInspector> {
  Future<ScenePkgInspectionResult?>? _inspection;
  String? _preflightError;
  late final ScenePkgInspectionSession _session =
      widget.confirmedSession ?? ScenePkgInspectionSession();
  final FileTreeCompareSelection _manualCompare = FileTreeCompareSelection();

  @override
  void initState() {
    super.initState();
    if (widget.confirmedSession != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_startInspection());
      });
    }
  }

  Future<void> _saveExtracted(
    ScenePkgInspectionResult result,
    String filePath,
    bool live,
  ) async {
    try {
      final FileSaveLocation? location = await getSaveLocation(
        suggestedName: path.basename(filePath),
      );
      if (location == null || !mounted) return;
      await _session.saveExtractedFile(
        result: result,
        relativePath: filePath,
        live: live,
        destination: location.path,
        liveFolder: widget.leftFolder,
        backupFolder: widget.rightFolder,
      );
      if (!mounted) return;
      showNoticeToast(tr(AppI10n.backupDetailSaveExtractedSuccess));
    } on ScenePkgSaveException catch (error) {
      if (!mounted) return;
      final String message = switch (error.reason) {
        ScenePkgSaveFailure.invalidSource => tr(
          AppI10n.backupDetailSaveExtractedInvalidSource,
        ),
        ScenePkgSaveFailure.protectedDestination => tr(
          AppI10n.backupDetailSaveExtractedProtected,
        ),
        ScenePkgSaveFailure.exists => tr(
          AppI10n.backupDetailSaveExtractedExists,
        ),
        ScenePkgSaveFailure.writeFailed =>
          error.possiblePartialFile
              ? tr(AppI10n.backupDetailSaveExtractedPartial)
              : tr(AppI10n.backupDetailSaveExtractedFailed),
      };
      showErrorToast(message);
    } catch (_) {
      if (!mounted) return;
      showErrorToast(tr(AppI10n.backupDetailSaveExtractedFailed));
    }
  }

  Widget _saveAction(
    ScenePkgInspectionResult result,
    String filePath, {
    required bool live,
    bool both = false,
  }) => both
      ? PopupMenuButton<bool>(
          key: ValueKey<String>('backup-package-save-$filePath'),
          tooltip: tr(AppI10n.backupDetailSaveExtractedAction),
          icon: const Icon(Icons.save_alt_rounded, size: 18),
          padding: EdgeInsets.zero,
          onSelected: (bool selectedLive) =>
              _saveExtracted(result, filePath, selectedLive),
          itemBuilder: (BuildContext context) => <PopupMenuEntry<bool>>[
            PopupMenuItem<bool>(
              value: true,
              child: Text(
                tr(
                  AppI10n.backupDetailSaveExtractedCopy,
                  namedArgs: <String, String>{
                    'source':
                        widget.leftLabel ?? path.basename(widget.leftFolder),
                  },
                ),
              ),
            ),
            PopupMenuItem<bool>(
              value: false,
              child: Text(
                tr(
                  AppI10n.backupDetailSaveExtractedCopy,
                  namedArgs: <String, String>{
                    'source':
                        widget.rightLabel ?? path.basename(widget.rightFolder),
                  },
                ),
              ),
            ),
          ],
        )
      : FileTreeAction(
          key: ValueKey<String>('backup-package-save-$filePath'),
          tooltip: tr(AppI10n.backupDetailSaveExtractedAction),
          icon: Icons.save_alt_rounded,
          foreground: widget.foreground,
          onPressed: () => _saveExtracted(result, filePath, live),
        );

  @override
  void dispose() {
    unawaited(_session.dispose());
    super.dispose();
  }

  Future<void> _confirmInspection() async {
    if (_inspection != null) return;
    if (!await _confirmPackageInspection(context, _session) || !mounted) return;
    await _startInspection();
  }

  Future<void> _startInspection() async {
    final String? tool = widget.rePKGPath;
    if (tool == null || !await File(tool).exists()) {
      if (!mounted) return;
      setState(() {
        _preflightError = tr(AppI10n.backupDetailInspectPackageNoTool);
      });
      return;
    }

    final Future<ScenePkgInspectionResult?> inspection = _inspect(tool);
    setState(() {
      _preflightError = null;
      _inspection = inspection;
    });
  }

  Future<ScenePkgInspectionResult?> _inspect(String tool) async {
    try {
      return await _session.inspect(
        tool: tool,
        wallpaperName: widget.wallpaperName,
        filePath: widget.filePath,
        leftFolder: widget.leftFolder,
        rightFolder: widget.rightFolder,
      );
    } on ScenePkgInspectionException {
      throw StateError(tr(AppI10n.backupDetailInspectPackageUnavailable));
    }
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

  Widget _temporaryFolderRow(ScenePkgInspectionResult result) =>
      FileTreePathControl(
        key: const ValueKey<String>('backup-scene-pkg-temp-path'),
        depth: 2,
        label: tr(AppI10n.backupDetailTemporaryFolder),
        path: result.rootFolder,
        foreground: widget.foreground,
        copyTooltip: tr(AppI10n.backupDetailCopyTemporaryFolder),
        openTooltip: tr(AppI10n.backupDetailOpenTemporaryFolder),
        onOpen: () => browserFolder(result.rootFolder),
      );

  @override
  Widget build(BuildContext context) {
    if (!widget.fullView) return _buildInspectionTree(context);
    return FutureBuilder<ScenePkgInspectionResult?>(
      future: _inspection,
      builder: (context, snapshot) {
        final ScenePkgInspectionResult? result = snapshot.data;
        if (result == null) {
          return FileTreeScrollView(
            foreground: widget.foreground,
            child: _buildInspectionTree(context),
          );
        }
        final candidates = <FileTreeCompareCandidate>[
          ..._manualCompareCandidates(
            paths: result.changes.onlyLive,
            side: 'live',
            folder: result.leftFolder,
            label: widget.leftLabel,
          ),
          ..._manualCompareCandidates(
            paths: result.changes.onlyBackup,
            side: 'backup',
            folder: result.rightFolder,
            label: widget.rightLabel,
          ),
        ];
        return _PairedUpdateTree(
          configuration: UpdateFileChanges(
            wallpaperName: widget.wallpaperName,
            liveFolder: result.leftFolder,
            backupFolder: result.rightFolder,
            sourceLabel: widget.leftLabel ?? path.basename(widget.leftFolder),
            destinationLabel:
                widget.rightLabel ?? path.basename(widget.rightFolder),
            rePKGPath: null,
            foreground: widget.foreground,
            selection: null,
          ),
          changes: result.changes,
          inspectPackages: false,
          fileAction: (file, live) => _saveAction(result, file, live: live),
          manualSelection: _manualCompare,
          manualAction: _selectedManualCompareAction(
            candidates: candidates,
            selectedIds: _manualCompare.selected,
            foreground: widget.foreground,
          ),
          onCompareSelect: (candidate, control, shift) =>
              _selectManualCompare(candidates, candidate, control, shift),
          toolbar: Column(
            children: <Widget>[
              Text(tr(AppI10n.backupDetailRepackingComingSoon)),
              Wrap(
                spacing: 12,
                children: <Widget>[
                  if (result.changes.modified.isNotEmpty)
                    Text(
                      '${tr(AppI10n.backupDetailModified)} (${result.changes.modified.length})',
                    ),
                  if (result.changes.onlyLive.isNotEmpty)
                    Text(
                      '${tr(AppI10n.backupDetailAddedFiles)} (${result.changes.onlyLive.length})',
                    ),
                  if (result.changes.onlyBackup.isNotEmpty)
                    Text(
                      '${tr(AppI10n.backupDetailRemovedFiles)} (${result.changes.onlyBackup.length})',
                    ),
                  if (result.changes.modified.isEmpty &&
                      result.changes.onlyLive.isEmpty &&
                      result.changes.onlyBackup.isEmpty)
                    Text(tr(AppI10n.backupDetailInspectPackageNoDifferences)),
                ],
              ),
              _temporaryFolderRow(result),
              if (candidates.length >= 2)
                FileTreeCompareBar(
                  keyBase: 'backup-package-manual-compare',
                  candidates: candidates,
                  selection: _manualCompare,
                  foreground: widget.foreground,
                  label: tr(AppI10n.backupDetailCompareFiles),
                  clearTooltip: tr(AppI10n.backupDetailDeselectAll),
                  actionBuilder: (key, first, second) => _fileCompareAction(
                    key: key,
                    firstLabel: first.label,
                    firstPath: first.path,
                    secondLabel: second.label,
                    secondPath: second.path,
                    foreground: widget.foreground,
                  ),
                  onClear: () => setState(_manualCompare.clear),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInspectionTree(BuildContext context) {
    final Future<ScenePkgInspectionResult?>? inspection = _inspection;
    final String firstFolder = widget.directionalVisual
        ? widget.rightFolder
        : widget.leftFolder;
    final String firstLabel = widget.directionalVisual
        ? _oldImageLabel(widget.rightLabel)
        : (widget.leftLabel ?? path.basename(widget.leftFolder));
    final String secondFolder = widget.directionalVisual
        ? widget.leftFolder
        : widget.rightFolder;
    final String secondLabel = widget.directionalVisual
        ? _newImageLabel(widget.leftLabel)
        : (widget.rightLabel ?? path.basename(widget.rightFolder));
    final FileTreeCompareAction packageCompareAction = _fileCompareAction(
      key: ValueKey<String>('backup-file-compare-${widget.filePath}'),
      firstLabel: firstLabel,
      firstPath: path.join(firstFolder, widget.filePath),
      secondLabel: secondLabel,
      secondPath: path.join(secondFolder, widget.filePath),
      foreground: widget.foreground,
      hoverInert: true,
    );
    // FileTreeScrollView already owns the accessibility container for this
    // dynamic tree. Keep package inspection keyed without introducing a second
    // semantics root that is replaced when the extraction Future completes.
    return KeyedSubtree(
      key: ValueKey<String>('backup-scene-pkg-container-${widget.filePath}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          FileTreeRow(
            key: ValueKey<String>('backup-scene-pkg-row-${widget.filePath}'),
            depth: 1,
            icon: Icons.inventory_2_outlined,
            iconColor: widget.accent,
            label: _treePath(widget.filePath),
            foreground: widget.foreground,
            hoverHighlight: false,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                packageCompareAction,
                if (inspection == null)
                  TextButton.icon(
                    key: const ValueKey<String>('backup-scene-pkg-inspect'),
                    onPressed: _confirmInspection,
                    icon: const Icon(Icons.manage_search_rounded, size: 16),
                    label: Text(tr(AppI10n.backupDetailInspectPackageAction)),
                  ),
              ],
            ),
            choice: widget.directionalVisual && widget.selection != null
                ? _copyChoice(
                    widget.selection!,
                    widget.filePath,
                    widget.foreground,
                  )
                : null,
            contextActions: <FileTreeContextAction>[
              _compareContextAction(packageCompareAction),
            ],
          ),
          if (_preflightError case final String error)
            FileTreeRow(
              depth: 2,
              icon: Icons.error_outline_rounded,
              label: error,
              foreground: widget.foreground,
              iconColor: Theme.of(context).status.bad,
            ),
          FutureBuilder<ScenePkgInspectionResult?>(
            future: inspection,
            builder:
                (
                  BuildContext context,
                  AsyncSnapshot<ScenePkgInspectionResult?> snapshot,
                ) {
                  // Keep one stable container in the tree from idle through
                  // extraction completion. Only its children change, avoiding
                  // another parent replacement during a large AXTree update.
                  if (inspection == null) {
                    return const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[],
                    );
                  }
                  if (snapshot.connectionState != ConnectionState.done) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        FileTreeRow(
                          depth: 2,
                          icon: Icons.hourglass_top_rounded,
                          label: tr(AppI10n.backupDetailInspectPackageWorking),
                          foreground: widget.foreground,
                          iconColor: widget.accent,
                        ),
                      ],
                    );
                  }
                  final ScenePkgInspectionResult? result = snapshot.data;
                  if (snapshot.hasError || result == null) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        FileTreeRow(
                          depth: 2,
                          icon: Icons.error_outline_rounded,
                          label: tr(
                            AppI10n.backupDetailInspectPackageUnavailable,
                          ),
                          subtitle: snapshot.error?.toString(),
                          foreground: widget.foreground,
                          iconColor: Theme.of(context).status.bad,
                        ),
                      ],
                    );
                  }
                  final BackupFileChanges changes = result.changes;
                  final int total =
                      changes.modified.length +
                      changes.onlyLive.length +
                      changes.onlyBackup.length +
                      0;
                  if (total == 0) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        _temporaryFolderRow(result),
                        FileTreeRow(
                          depth: 2,
                          icon: Icons.check_circle_outline_rounded,
                          label: tr(
                            AppI10n.backupDetailInspectPackageNoDifferences,
                          ),
                          foreground: widget.foreground,
                          iconColor: Theme.of(context).status.good,
                        ),
                      ],
                    );
                  }
                  final List<FileTreeCompareCandidate> compareCandidates =
                      <FileTreeCompareCandidate>[
                        ..._manualCompareCandidates(
                          paths: changes.onlyLive,
                          side: 'package-left',
                          folder: result.leftFolder,
                          label: widget.leftLabel,
                        ),
                        ..._manualCompareCandidates(
                          paths: changes.onlyBackup,
                          side: 'package-right',
                          folder: result.rightFolder,
                          label: widget.rightLabel,
                        ),
                      ];
                  final FileTreeCompareAction? manualCompareAction =
                      _selectedManualCompareAction(
                        candidates: compareCandidates,
                        selectedIds: _manualCompare.selected,
                        foreground: widget.foreground,
                      );
                  final StatusPalette colours = Theme.of(context).status;
                  final String firstModifiedFolder = widget.directionalVisual
                      ? result.rightFolder
                      : result.leftFolder;
                  final String? firstModifiedLabel = widget.directionalVisual
                      ? _oldImageLabel(widget.rightLabel)
                      : widget.leftLabel;
                  final String secondModifiedFolder = widget.directionalVisual
                      ? result.leftFolder
                      : result.rightFolder;
                  final String? secondModifiedLabel = widget.directionalVisual
                      ? _newImageLabel(widget.leftLabel)
                      : widget.rightLabel;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      FileTreeRow(
                        depth: 2,
                        icon: Icons.account_tree_outlined,
                        label:
                            '${tr(AppI10n.backupDetailInsidePackage)} ($total)',
                        foreground: widget.foreground,
                        iconColor: widget.accent,
                      ),
                      if (widget.directionalVisual && widget.selection != null)
                        FileTreeRow(
                          key: ValueKey<String>(
                            'backup-package-repacking-notice-${widget.filePath}',
                          ),
                          depth: 3,
                          icon: Icons.info_outline_rounded,
                          label: tr(AppI10n.backupDetailRepackingComingSoon),
                          foreground: widget.foreground,
                          iconColor: widget.foreground.withValues(alpha: .65),
                          hoverHighlight: false,
                        ),
                      _temporaryFolderRow(result),
                      if (compareCandidates.length >= 2)
                        FileTreeCompareBar(
                          keyBase: 'backup-package-manual-compare',
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
                                hoverInert: true,
                              ),
                          onClear: () {
                            setState(_manualCompare.clear);
                          },
                        ),
                      ..._nestedDifferenceRows(
                        title: tr(AppI10n.backupDetailModified),
                        paths: changes.modified,
                        colour: colours.warn,
                        foreground: widget.foreground,
                        firstFolder: firstModifiedFolder,
                        firstLabel: firstModifiedLabel,
                        secondFolder: secondModifiedFolder,
                        secondLabel: secondModifiedLabel,
                        directional: widget.directionalVisual,
                        selection: widget.directionalVisual
                            ? widget.selection
                            : null,
                        packagePath: widget.filePath,
                        saveAction: (String filePath) => _saveAction(
                          result,
                          filePath,
                          live: true,
                          both: true,
                        ),
                      ),
                      ..._nestedDifferenceRows(
                        title:
                            widget.leftOnlyLabel ??
                            tr(AppI10n.backupDetailAddedFiles),
                        paths: changes.onlyLive,
                        colour: colours.good,
                        foreground: widget.foreground,
                        firstFolder: result.leftFolder,
                        firstLabel: widget.leftLabel,
                        selection: widget.directionalVisual
                            ? widget.selection
                            : null,
                        packagePath: widget.filePath,
                        saveAction: (String filePath) =>
                            _saveAction(result, filePath, live: true),
                        compareSide: 'package-left',
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
                      ..._nestedDifferenceRows(
                        title:
                            widget.rightOnlyLabel ??
                            tr(AppI10n.backupDetailRemovedFiles),
                        paths: changes.onlyBackup,
                        colour: colours.note,
                        foreground: widget.foreground,
                        firstFolder: result.rightFolder,
                        firstLabel: widget.rightLabel,
                        selection: widget.directionalVisual
                            ? widget.selection
                            : null,
                        packagePath: widget.filePath,
                        saveAction: (String filePath) =>
                            _saveAction(result, filePath, live: false),
                        deletion: widget.directionalVisual,
                        compareSide: 'package-right',
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
                  );
                },
          ),
        ],
      ),
    );
  }
}
