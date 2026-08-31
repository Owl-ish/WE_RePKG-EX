part of 'content_details.dart';

bool _pathNamed(String filePath, String name) =>
    path.basename(filePath).toLowerCase() == name.toLowerCase();

FileTreeRowChoice _copyChoice(
  BackupUpdateSelection selection,
  String filePath,
  Color foreground, {
  String? packagePath,
}) {
  final bool selected = packagePath == null
      ? selection.copySelected(filePath)
      : selection.packageChangeSelected(packagePath, filePath, deletion: false);
  final String keyPath = packagePath == null
      ? filePath
      : '$packagePath::$filePath';
  return FileTreeRowChoice(
    selected: selected,
    onChanged: (bool value) {
      if (packagePath == null) {
        selection.setCopySelected(filePath, value);
      } else {
        selection.setPackageChangeSelected(
          packagePath,
          filePath,
          value,
          deletion: false,
        );
      }
    },
    rejectTooltip: tr(AppI10n.backupDetailKeepOld),
    acceptTooltip: tr(AppI10n.backupDetailApplyChange),
    foreground: foreground,
    enabled: packagePath == null,
    disabledTooltip: packagePath == null
        ? null
        : tr(AppI10n.backupDetailRepackingComingSoon),
    rejectKey: ValueKey<String>('backup-update-reject-$keyPath'),
    acceptKey: ValueKey<String>('backup-update-accept-$keyPath'),
  );
}

FileTreeRowChoice _deletionChoice(
  BackupUpdateSelection selection,
  String filePath,
  Color foreground, {
  String? packagePath,
}) {
  final bool selected = packagePath == null
      ? selection.deletionSelected(filePath)
      : selection.packageChangeSelected(packagePath, filePath, deletion: true);
  final String keyPath = packagePath == null
      ? filePath
      : '$packagePath::$filePath';
  return FileTreeRowChoice(
    selected: selected,
    onChanged: (bool value) {
      if (packagePath == null) {
        selection.setDeletionSelected(filePath, value);
      } else {
        selection.setPackageChangeSelected(
          packagePath,
          filePath,
          value,
          deletion: true,
        );
      }
    },
    rejectTooltip: tr(AppI10n.backupDetailKeepBackupFile),
    acceptTooltip: tr(AppI10n.backupDetailRemoveBackupFile),
    foreground: foreground,
    enabled: packagePath == null,
    disabledTooltip: packagePath == null
        ? null
        : tr(AppI10n.backupDetailRepackingComingSoon),
    rejectKey: ValueKey<String>('backup-update-reject-$keyPath'),
    acceptKey: ValueKey<String>('backup-update-accept-$keyPath'),
  );
}

FileTreeRowChoice _copyGroupChoice(
  BackupUpdateSelection selection,
  Iterable<String> filePaths,
  Color foreground, {
  required String keyBase,
  String? packagePath,
}) {
  final List<String> paths = List<String>.from(filePaths);
  final bool? selected = packagePath == null
      ? selection.copyGroupSelected(paths)
      : selection.packageGroupSelected(packagePath, paths, deletion: false);
  return FileTreeRowChoice(
    selected: selected,
    onChanged: (bool value) {
      if (packagePath == null) {
        selection.setCopyGroupSelected(paths, value);
      } else {
        selection.setPackageGroupSelected(
          packagePath,
          paths,
          value,
          deletion: false,
        );
      }
    },
    rejectTooltip: tr(AppI10n.backupDetailDeselectAll),
    acceptTooltip: tr(AppI10n.backupDetailSelectAll),
    foreground: foreground,
    enabled: packagePath == null,
    disabledTooltip: packagePath == null
        ? null
        : tr(AppI10n.backupDetailRepackingComingSoon),
    rejectKey: ValueKey<String>('backup-update-group-reject-$keyBase'),
    acceptKey: ValueKey<String>('backup-update-group-accept-$keyBase'),
  );
}

FileTreeRowChoice _deletionGroupChoice(
  BackupUpdateSelection selection,
  Iterable<String> filePaths,
  Color foreground, {
  required String keyBase,
  String? packagePath,
}) {
  final List<String> paths = List<String>.from(filePaths);
  final bool? selected = packagePath == null
      ? selection.deletionGroupSelected(paths)
      : selection.packageGroupSelected(packagePath, paths, deletion: true);
  return FileTreeRowChoice(
    selected: selected,
    onChanged: (bool value) {
      if (packagePath == null) {
        selection.setDeletionGroupSelected(paths, value);
      } else {
        selection.setPackageGroupSelected(
          packagePath,
          paths,
          value,
          deletion: true,
        );
      }
    },
    rejectTooltip: tr(AppI10n.backupDetailDeselectAll),
    acceptTooltip: tr(AppI10n.backupDetailSelectAll),
    foreground: foreground,
    enabled: packagePath == null,
    disabledTooltip: packagePath == null
        ? null
        : tr(AppI10n.backupDetailRepackingComingSoon),
    rejectKey: ValueKey<String>('backup-update-group-reject-$keyBase'),
    acceptKey: ValueKey<String>('backup-update-group-accept-$keyBase'),
  );
}

String _deletionSubtitle(
  BackupUpdateSelection selection,
  String filePath, {
  String? packagePath,
}) {
  final bool selected = packagePath == null
      ? selection.deletionSelected(filePath)
      : selection.packageChangeSelected(packagePath, filePath, deletion: true);
  return tr(
    selected ? AppI10n.backupDetailWillRemove : AppI10n.backupDetailWillKeep,
  );
}

Widget _pathDifferenceGroup({
  required String title,
  required List<String> paths,
  required String? previewFolder,
  required String? previewLabel,
  required Color colour,
  required Color foreground,
  BackupUpdateSelection? selection,
  bool deletion = false,
  String? groupChoiceKey,
  String? compareSide,
  Set<String> compareSelection = const <String>{},
  FileTreeCompareAction? manualCompareAction,
  void Function(FileTreeCompareCandidate, bool, bool)? onCompareSelect,
}) {
  final List<String> ordered = List<String>.from(paths)
    ..sort((String a, String b) => a.toLowerCase().compareTo(b.toLowerCase()));
  final BackupUpdateSelection? activeSelection = selection;
  final String? activeGroupChoiceKey = groupChoiceKey;
  final FileTreeRowChoice? groupChoice =
      activeSelection == null || activeGroupChoiceKey == null
      ? null
      : deletion
      ? _deletionGroupChoice(
          activeSelection,
          ordered,
          foreground,
          keyBase: activeGroupChoiceKey,
        )
      : _copyGroupChoice(
          activeSelection,
          ordered,
          foreground,
          keyBase: activeGroupChoiceKey,
        );

  return FileTreeGroup(
    title: title,
    count: ordered.length,
    accent: colour,
    foreground: foreground,
    trailing: groupChoice,
    children: <Widget>[
      for (final String filePath in ordered)
        _differenceFileEntry(
          depth: 1,
          filePath: filePath,
          colour: colour,
          foreground: foreground,
          firstFolder: previewFolder,
          firstLabel: previewLabel,
          subtitle: deletion && activeSelection != null
              ? _deletionSubtitle(activeSelection, filePath)
              : null,
          choice: activeSelection == null
              ? null
              : deletion
              ? _deletionChoice(activeSelection, filePath, foreground)
              : _copyChoice(activeSelection, filePath, foreground),
          compareCandidate: compareSide == null || previewFolder == null
              ? null
              : FileTreeCompareCandidate(
                  id: '$compareSide::$filePath',
                  path: path.join(previewFolder, filePath),
                  label: previewLabel ?? path.basename(previewFolder),
                ),
          compareSelection: compareSelection,
          manualCompareAction: manualCompareAction,
          onCompareSelect: onCompareSelect,
        ),
    ],
  );
}

/// Backup-specific wrapper around the shared two-folder difference tree.
class BackupDifferenceFileTree extends StatelessWidget {
  const BackupDifferenceFileTree({
    super.key,
    required this.wallpaperName,
    required this.difference,
    required this.workshopBackupFolder,
    required this.myProjectsBackupFolder,
    required this.rePKGPath,
    required this.foreground,
  });

  final String wallpaperName;
  final BackupCopyDifference? difference;
  final String? workshopBackupFolder;
  final String? myProjectsBackupFolder;
  final String? rePKGPath;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final BackupCopyDifference? difference = this.difference;
    final FolderFileChanges? changes = difference == null
        ? null
        : (
            modified: difference.differentSize,
            onlyFirst: difference.onlyWorkshop,
            onlySecond: difference.onlyMyProjects,
          );
    return FolderDifferenceFileTree(
      wallpaperName: wallpaperName,
      changes: changes,
      firstFolder: workshopBackupFolder,
      secondFolder: myProjectsBackupFolder,
      firstLabel: '${tr(AppI10n.backupFolderBackupWorkshop)} / $wallpaperName',
      secondLabel:
          '${tr(AppI10n.backupFolderBackupMyProjects)} / $wallpaperName',
      modifiedTitle: tr(AppI10n.backupDetailDifferentSize),
      firstOnlyTitle: tr(AppI10n.backupDetailInWorkshopBackup),
      secondOnlyTitle: tr(AppI10n.backupDetailInMyProjectsBackup),
      semanticLabel: tr(AppI10n.backupDetailDetectedDifferences),
      unavailableText: tr(AppI10n.backupDetailDifferenceUnavailable),
      openFolderTooltip: tr(AppI10n.backupOpenBackupFolder),
      keyBase: 'backup-reconcile',
      firstSideId: 'reconcile-workshop',
      secondSideId: 'reconcile-myprojects',
      firstFolderActionKey: 'backup-reconcile-backup-workshop-button',
      secondFolderActionKey: 'backup-reconcile-backup-myprojects-button',
      rePKGPath: rePKGPath,
      foreground: foreground,
    );
  }
}

/// Shared exact/two-sided file tree for backup conflicts and live-copy checks.
///
/// Callers supply the side labels and group wording, so comparison mechanics,
/// package inspection, and manual two-file selection stay consistent without
/// baking Backup Workshop/MyProjects terminology into the tree itself.
class FolderDifferenceFileTree extends StatefulWidget {
  const FolderDifferenceFileTree({
    super.key,
    required this.wallpaperName,
    required this.changes,
    required this.firstFolder,
    required this.secondFolder,
    required this.firstLabel,
    required this.secondLabel,
    required this.modifiedTitle,
    required this.firstOnlyTitle,
    required this.secondOnlyTitle,
    required this.semanticLabel,
    required this.unavailableText,
    required this.openFolderTooltip,
    required this.keyBase,
    required this.firstSideId,
    required this.secondSideId,
    required this.firstFolderActionKey,
    required this.secondFolderActionKey,
    required this.rePKGPath,
    required this.foreground,
  });

  final String wallpaperName;
  final FolderFileChanges? changes;
  final String? firstFolder;
  final String? secondFolder;
  final String firstLabel;
  final String secondLabel;
  final String modifiedTitle;
  final String firstOnlyTitle;
  final String secondOnlyTitle;
  final String semanticLabel;
  final String unavailableText;
  final String openFolderTooltip;
  final String keyBase;
  final String firstSideId;
  final String secondSideId;
  final String firstFolderActionKey;
  final String secondFolderActionKey;
  final String? rePKGPath;
  final Color foreground;

  @override
  State<FolderDifferenceFileTree> createState() =>
      _FolderDifferenceFileTreeState();
}

class _FolderDifferenceFileTreeState extends State<FolderDifferenceFileTree> {
  final FileTreeCompareSelection _manualCompare = FileTreeCompareSelection();

  @override
  void didUpdateWidget(covariant FolderDifferenceFileTree oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.changes != widget.changes ||
        oldWidget.firstFolder != widget.firstFolder ||
        oldWidget.secondFolder != widget.secondFolder) {
      _manualCompare.clear();
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

  Widget? _routeFolderAction({
    required String keyName,
    required String? folder,
  }) {
    if (folder == null) return null;
    return FileTreeTooltip(
      message: '${widget.openFolderTooltip}\n$folder',
      child: IconButton(
        key: ValueKey<String>(keyName),
        onPressed: () => browserFolder(folder),
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints.tightFor(width: 28, height: 28),
        icon: Icon(
          Icons.folder_open_outlined,
          size: 16,
          color: widget.foreground.withValues(alpha: .78),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final FolderFileChanges? current = widget.changes;
    final int total = current == null
        ? 0
        : current.modified.length +
              current.onlyFirst.length +
              current.onlySecond.length;
    if (current == null || total == 0) {
      return FileTreeSurface(
        foreground: widget.foreground,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Text(
            widget.unavailableText,
            style: TextStyle(color: widget.foreground, height: 1.3),
          ),
        ),
      );
    }

    final StatusPalette colours = Theme.of(context).status;
    final List<FileTreeCompareCandidate> compareCandidates =
        <FileTreeCompareCandidate>[
          ..._manualCompareCandidates(
            paths: current.onlyFirst,
            side: widget.firstSideId,
            folder: widget.firstFolder,
            label: widget.firstLabel,
          ),
          ..._manualCompareCandidates(
            paths: current.onlySecond,
            side: widget.secondSideId,
            folder: widget.secondFolder,
            label: widget.secondLabel,
          ),
        ];
    final FileTreeCompareAction? manualCompareAction =
        _selectedManualCompareAction(
          candidates: compareCandidates,
          selectedIds: _manualCompare.selected,
          foreground: widget.foreground,
        );

    return FileTreeScrollView(
      key: ValueKey<String>('${widget.keyBase}-detail-scroll'),
      foreground: widget.foreground,
      semanticLabel: '${widget.semanticLabel}: $total',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          FileTreeRouteBanner(
            source: widget.firstLabel,
            destination: widget.secondLabel,
            foreground: widget.foreground,
            bidirectional: true,
            sourceAction: _routeFolderAction(
              keyName: widget.firstFolderActionKey,
              folder: widget.firstFolder,
            ),
            destinationAction: _routeFolderAction(
              keyName: widget.secondFolderActionKey,
              folder: widget.secondFolder,
            ),
          ),
          if (compareCandidates.length >= 2)
            FileTreeCompareBar(
              keyBase: '${widget.keyBase}-manual-compare',
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
              onClear: () => setState(_manualCompare.clear),
            ),
          if (current.modified.isNotEmpty)
            _ChangedFileGroup(
              title: widget.modifiedTitle,
              paths: current.modified,
              wallpaperName: widget.wallpaperName,
              leftFolder: widget.firstFolder,
              rightFolder: widget.secondFolder,
              leftLabel: widget.firstLabel,
              rightLabel: widget.secondLabel,
              directionalVisual: false,
              rePKGPath: widget.rePKGPath,
              colour: colours.warn,
              foreground: widget.foreground,
              leftOnlyLabel: widget.firstOnlyTitle,
              rightOnlyLabel: widget.secondOnlyTitle,
            ),
          if (current.onlyFirst.isNotEmpty)
            _pathDifferenceGroup(
              title: widget.firstOnlyTitle,
              paths: current.onlyFirst,
              previewFolder: widget.firstFolder,
              previewLabel: widget.firstLabel,
              colour: colours.note,
              foreground: widget.foreground,
              compareSide: widget.firstSideId,
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
          if (current.onlySecond.isNotEmpty)
            _pathDifferenceGroup(
              title: widget.secondOnlyTitle,
              paths: current.onlySecond,
              previewFolder: widget.secondFolder,
              previewLabel: widget.secondLabel,
              colour: colours.good,
              foreground: widget.foreground,
              compareSide: widget.secondSideId,
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
  }
}

class _ChangedFileGroup extends StatelessWidget {
  const _ChangedFileGroup({
    required this.title,
    required this.paths,
    required this.wallpaperName,
    required this.leftFolder,
    required this.rightFolder,
    required this.leftLabel,
    required this.rightLabel,
    required this.directionalVisual,
    required this.rePKGPath,
    required this.colour,
    required this.foreground,
    this.leftOnlyLabel,
    this.rightOnlyLabel,
    this.selection,
    this.groupChoiceKey,
  });

  final String title;
  final List<String> paths;
  final String wallpaperName;
  final String? leftFolder;
  final String? rightFolder;
  final String? leftLabel;
  final String? rightLabel;
  final bool directionalVisual;
  final String? rePKGPath;
  final Color colour;
  final Color foreground;
  final String? leftOnlyLabel;
  final String? rightOnlyLabel;
  final BackupUpdateSelection? selection;
  final String? groupChoiceKey;

  @override
  Widget build(BuildContext context) {
    final List<String> ordered = List<String>.from(
      paths,
    )..sort((String a, String b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final String? firstFolder = directionalVisual ? rightFolder : leftFolder;
    final String? firstLabel = directionalVisual
        ? _oldImageLabel(rightLabel)
        : leftLabel;
    final String? secondFolder = directionalVisual ? leftFolder : rightFolder;
    final String? secondLabel = directionalVisual
        ? _newImageLabel(leftLabel)
        : rightLabel;
    final BackupUpdateSelection? activeSelection = selection;
    final String? activeGroupChoiceKey = groupChoiceKey;
    return FileTreeGroup(
      title: title,
      count: ordered.length,
      accent: colour,
      foreground: foreground,
      trailing: activeSelection == null || activeGroupChoiceKey == null
          ? null
          : _copyGroupChoice(
              activeSelection,
              ordered,
              foreground,
              keyBase: activeGroupChoiceKey,
            ),
      children: <Widget>[
        for (final String filePath in ordered)
          if (_pathNamed(filePath, WallpaperFiles.packedScene) &&
              leftFolder != null &&
              rightFolder != null)
            _ScenePkgInspector(
              wallpaperName: wallpaperName,
              filePath: filePath,
              leftFolder: leftFolder!,
              rightFolder: rightFolder!,
              leftLabel: leftLabel,
              rightLabel: rightLabel,
              directionalVisual: directionalVisual,
              rePKGPath: rePKGPath,
              foreground: foreground,
              accent: colour,
              leftOnlyLabel: leftOnlyLabel,
              rightOnlyLabel: rightOnlyLabel,
              selection: selection,
            )
          else
            _differenceFileEntry(
              depth: 1,
              filePath: filePath,
              colour: colour,
              foreground: foreground,
              firstFolder: firstFolder,
              firstLabel: firstLabel,
              secondFolder: secondFolder,
              secondLabel: secondLabel,
              directional: directionalVisual,
              choice: selection == null
                  ? null
                  : _copyChoice(selection!, filePath, foreground),
            ),
      ],
    );
  }
}

bool _isJsonPath(String filePath) =>
    path.extension(filePath).toLowerCase() == '.json';

const int _inlineJsonChangePreviewLimit = 20;
