// Backup diagnostic and non-content detail presentation.
//
// Owns explanatory, Empty/Junk, and Reconcile views. File-level Reconcile
// differences reuse the shared content explorer; scanning and disk mutations
// remain outside this UI module.

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:we_repkg/constants/i10n.dart';
import 'package:we_repkg/cores/backup.dart';
import 'package:we_repkg/cores/base.dart';
import 'package:we_repkg/utils/backup_diff.dart';
import 'package:we_repkg/utils/wallpaper_junk.dart';
import 'package:we_repkg/views/backup/details/content_details.dart';
import 'package:we_repkg/widgets/file_tree_panel.dart';
import 'package:we_repkg/widgets/input_controls.dart';

/// Displays a localized explanatory message for a simple Backup detail state.
class BackupDetailContent extends StatelessWidget {
  const BackupDetailContent({
    super.key,
    required this.text,
    required this.foreground,
  });

  final String text;
  final Color foreground;

  @override
  Widget build(BuildContext context) =>
      Text(tr(text), style: TextStyle(color: foreground, height: 1.35));
}

FileTreeLibrary _fileTreeLibrary(WallpaperLibrary library) => switch (library) {
  WallpaperLibrary.workshop => FileTreeLibrary.workshop,
  WallpaperLibrary.myProjects => FileTreeLibrary.myProjects,
};

String _reconcileReasonExplanationKey(
  BackupReconcileReason reason, {
  required bool ignored,
}) => switch (reason) {
  BackupReconcileReason.duplicateLiveCopies =>
    ignored
        ? AppI10n.backupReconcileReasonDuplicateLiveIgnoredAbout
        : AppI10n.backupReconcileReasonDuplicateLiveAbout,
  BackupReconcileReason.conflictingBackupCopies =>
    ignored
        ? AppI10n.backupReconcileReasonConflictingBackupsIgnoredAbout
        : AppI10n.backupReconcileReasonConflictingBackupsAbout,
  BackupReconcileReason.comparisonUnavailable =>
    AppI10n.backupReconcileReasonComparisonUnavailableAbout,
};

String _reconcileReasonExplanationText(
  ReconcileEntry entry,
  BackupReconcileReason reason, {
  required bool ignored,
}) {
  final Map<String, String> args = <String, String>{};
  if (reason == BackupReconcileReason.duplicateLiveCopies) {
    final List<String> locations = <String>[
      if (entry.liveWorkshop) tr(AppI10n.homeLibraryWorkshop),
      if (entry.liveMyProjects) tr(AppI10n.homeLibraryMyProjects),
    ];
    if (locations.length >= 2) {
      args['location1'] = locations[0];
      args['location2'] = locations[1];
    }
  }
  return tr(
    _reconcileReasonExplanationKey(reason, ignored: ignored),
    namedArgs: args,
  );
}

String _reconcileStateLabel(BackupState state) => switch (state) {
  BackupState.synced => AppI10n.backupStateSynced,
  BackupState.notBackedUp => AppI10n.backupStateNotBackedUp,
  BackupState.vanished => AppI10n.backupStateVanished,
  BackupState.updateAvailable => AppI10n.backupStateUpdateAvailable,
  BackupState.updateDismissed => AppI10n.backupStateUpdateDismissed,
  BackupState.emptyBackup => AppI10n.backupStateEmptyBackup,
};

/// Explains why a folder is disposable and shows the files that produced it.
class JunkDetailContent extends StatelessWidget {
  const JunkDetailContent({
    super.key,
    required this.folderPath,
    required this.kind,
    required this.library,
    required this.foreground,
  });

  final String folderPath;
  final WallpaperJunkKind kind;
  final WallpaperLibrary library;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final String explanation = switch (kind) {
      WallpaperJunkKind.empty => AppI10n.backupJunkDetailsEmpty,
      WallpaperJunkKind.shaderCacheOnly => AppI10n.backupJunkDetailsShader,
      WallpaperJunkKind.mixed => AppI10n.backupJunkDetailsMixed,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          tr(explanation),
          style: TextStyle(color: foreground, height: 1.35),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: FileTreePanel(
            key: const ValueKey<String>('backup-junk-file-tree'),
            folderPath: folderPath,
            foreground: foreground,
            library: _fileTreeLibrary(library),
          ),
        ),
      ],
    );
  }
}

/// Decides whether a Reconcile difference tree is dense enough to defer until focus.
bool reconcileNeedsFileFocus(
  ReconcileEntry? entry, {
  bool ignored = false,
  BackupReconcileReason? reasonOverride,
}) {
  final BackupReconcileReason? primary =
      reasonOverride ??
      (ignored ? entry?.ignoredPrimaryReason : entry?.activePrimaryReason);
  if (entry == null ||
      primary != BackupReconcileReason.conflictingBackupCopies) {
    return false;
  }
  final BackupCopyDifference? difference = entry.backupDifference;
  if (difference == null || difference.total == 0) return false;
  final int groups = <List<String>>[
    difference.differentSize,
    difference.onlyWorkshop,
    difference.onlyMyProjects,
  ].where((List<String> paths) => paths.isNotEmpty).length;
  final Iterable<String> paths = <String>[
    ...difference.differentSize,
    ...difference.onlyWorkshop,
    ...difference.onlyMyProjects,
  ];
  final int longest = paths.fold<int>(
    0,
    (int length, String path) => path.length > length ? path.length : length,
  );
  return difference.total + groups > 4 || longest > 58;
}

class _DetectedFolderCopy extends StatelessWidget {
  const _DetectedFolderCopy({
    super.key,
    required this.label,
    required this.folder,
    required this.foreground,
    required this.openTooltip,
  });

  final String label;
  final String? folder;
  final Color foreground;
  final String openTooltip;

  @override
  Widget build(BuildContext context) {
    final String? folder = this.folder;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          label,
          style: TextStyle(
            color: foreground,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (folder != null) ...<Widget>[
          const SizedBox(height: 4),
          PathActionBox(
            path: folder,
            copyTooltip: tr(AppI10n.backupDetailCopyFolderPath),
            openTooltip: tr(openTooltip),
            onOpen: () => browserFolder(folder),
            foreground: foreground,
            compact: true,
          ),
        ],
      ],
    );
  }
}

typedef _DeferredFolderComparisonBuilder =
    Widget Function(
      FolderFileComparison? comparison,
      bool comparing,
      bool comparisonFailed,
    );

/// Starts an exact folder comparison only after the user presses Compare Files.
/// Expanding the surrounding detail pane alone never starts disk work. The result
/// is retained while that dialog is open, so restoring the preview does not rescan.
class _DeferredFolderComparison extends StatefulWidget {
  const _DeferredFolderComparison({
    required this.active,
    required this.load,
    required this.builder,
  });

  final bool active;
  final Future<FolderFileComparison?> Function()? load;
  final _DeferredFolderComparisonBuilder builder;

  @override
  State<_DeferredFolderComparison> createState() =>
      _DeferredFolderComparisonState();
}

class _DeferredFolderComparisonState extends State<_DeferredFolderComparison> {
  Future<FolderFileComparison?>? _comparison;

  void _startIfNeeded() {
    if (!widget.active || _comparison != null) return;
    final Future<FolderFileComparison?> Function()? load = widget.load;
    if (load != null) _comparison = load();
  }

  @override
  void initState() {
    super.initState();
    _startIfNeeded();
  }

  @override
  void didUpdateWidget(covariant _DeferredFolderComparison oldWidget) {
    super.didUpdateWidget(oldWidget);
    _startIfNeeded();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) {
      return widget.builder(null, false, false);
    }
    final Future<FolderFileComparison?>? comparison = _comparison;
    if (comparison == null) {
      return widget.builder(null, false, true);
    }
    return FutureBuilder<FolderFileComparison?>(
      future: comparison,
      builder:
          (
            BuildContext context,
            AsyncSnapshot<FolderFileComparison?> snapshot,
          ) {
            if (snapshot.connectionState != ConnectionState.done) {
              return widget.builder(null, true, false);
            }
            if (snapshot.hasError || snapshot.data == null) {
              return widget.builder(null, false, true);
            }
            return widget.builder(snapshot.data, false, false);
          },
    );
  }
}

/// Presents the safe diagnostic detail for one unresolved Reconcile state.
///
/// Reconcile remains view-only here; this widget does not choose or mutate an
/// authoritative copy when the filesystem state is ambiguous.
class ReconcileDetailContent extends StatefulWidget {
  const ReconcileDetailContent({
    super.key,
    required this.entry,
    this.primaryReasonOverride,
    required this.foreground,
    required this.focused,
    required this.needsFocus,
    required this.workshopLiveFolder,
    required this.myProjectsLiveFolder,
    required this.workshopBackupFolder,
    required this.myProjectsBackupFolder,
    required this.rePKGPath,
    this.ignoredMode = false,
    this.loadDuplicateLiveChanges,
    this.onRequestFocus,
  });

  final ReconcileEntry entry;
  final BackupReconcileReason? primaryReasonOverride;
  final Color foreground;
  final bool focused;
  final bool needsFocus;
  final String? workshopLiveFolder;
  final String? myProjectsLiveFolder;
  final String? workshopBackupFolder;
  final String? myProjectsBackupFolder;
  final String? rePKGPath;
  final bool ignoredMode;
  final Future<FolderFileComparison?> Function()? loadDuplicateLiveChanges;
  final VoidCallback? onRequestFocus;

  @override
  State<ReconcileDetailContent> createState() => _ReconcileDetailContentState();
}

class _ReconcileDetailContentState extends State<ReconcileDetailContent> {
  bool _compareRequested = false;

  ReconcileEntry get entry => widget.entry;
  Color get foreground => widget.foreground;
  bool get needsFocus => widget.needsFocus;
  String? get workshopLiveFolder => widget.workshopLiveFolder;
  String? get myProjectsLiveFolder => widget.myProjectsLiveFolder;
  String? get workshopBackupFolder => widget.workshopBackupFolder;
  String? get myProjectsBackupFolder => widget.myProjectsBackupFolder;
  String? get rePKGPath => widget.rePKGPath;
  Future<FolderFileComparison?> Function()? get loadDuplicateLiveChanges =>
      widget.loadDuplicateLiveChanges;

  void _requestComparison() {
    if (_compareRequested) return;
    setState(() => _compareRequested = true);
    widget.onRequestFocus?.call();
  }

  @override
  void didUpdateWidget(covariant ReconcileDetailContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entry.name != widget.entry.name ||
        oldWidget.entry.reason != widget.entry.reason ||
        oldWidget.ignoredMode != widget.ignoredMode ||
        oldWidget.primaryReasonOverride != widget.primaryReasonOverride) {
      _compareRequested = false;
    }
  }

  bool _hasDuplicateLiveDifferences(FolderFileChanges? changes) =>
      changes != null &&
      (changes.modified.isNotEmpty ||
          changes.onlyFirst.isNotEmpty ||
          changes.onlySecond.isNotEmpty);

  @override
  Widget build(BuildContext context) {
    final BackupIssueEvidence evidence = entry.evidence;
    final Set<BackupReconcileReason> displayReasons =
        widget.primaryReasonOverride == null
        ? (widget.ignoredMode ? entry.ignoredReasons : entry.activeReasons)
        : <BackupReconcileReason>{widget.primaryReasonOverride!};
    final BackupReconcileReason primary =
        widget.primaryReasonOverride ??
        (widget.ignoredMode
            ? entry.ignoredPrimaryReason
            : entry.activePrimaryReason) ??
        entry.reason;
    final List<BackupReconcileReason> secondaryReasons =
        displayReasons.difference(<BackupReconcileReason>{primary}).toList()
          ..sort(
            (BackupReconcileReason a, BackupReconcileReason b) =>
                a.index.compareTo(b.index),
          );
    final List<BackupState> attentionStates = evidence.attentionStates.toList()
      ..sort(
        (BackupState a, BackupState b) =>
            (backupSeverity[a] ?? 0).compareTo(backupSeverity[b] ?? 0),
      );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          _reconcileReasonExplanationText(
            entry,
            primary,
            ignored: widget.ignoredMode,
          ),
          style: TextStyle(color: foreground, height: 1.35),
        ),
        if (secondaryReasons.isNotEmpty ||
            attentionStates.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          for (final BackupReconcileReason reason in secondaryReasons)
            Text(
              '• ${_reconcileReasonExplanationText(entry, reason, ignored: widget.ignoredMode)}',
              style: TextStyle(color: foreground, height: 1.3, fontSize: 12),
            ),
          for (final BackupState state in attentionStates)
            Text(
              '• ${tr(_reconcileStateLabel(state))}',
              style: TextStyle(color: foreground, height: 1.3, fontSize: 12),
            ),
        ],
        const SizedBox(height: 12),
        Expanded(child: _details(context)),
      ],
    );
  }

  Widget _details(BuildContext context) {
    final BackupReconcileReason primary =
        widget.primaryReasonOverride ??
        (widget.ignoredMode
            ? entry.ignoredPrimaryReason
            : entry.activePrimaryReason) ??
        entry.reason;
    return switch (primary) {
      BackupReconcileReason.duplicateLiveCopies => _duplicateLiveAsyncDetails(),
      BackupReconcileReason.comparisonUnavailable =>
        _comparisonUnavailableDetails(),
      BackupReconcileReason.conflictingBackupCopies
          when needsFocus && !_compareRequested =>
        _conflictingBackupDetails(showTree: false),
      BackupReconcileReason.conflictingBackupCopies =>
        _conflictingBackupDetails(showTree: true),
    };
  }

  List<Widget> _detectedLocationCards({
    required bool includeLive,
    required bool includeBackup,
  }) {
    final BackupIssueEvidence evidence = entry.evidence;
    return <Widget>[
      if (includeLive && evidence.liveWorkshop)
        _DetectedFolderCopy(
          key: const ValueKey<String>('backup-reconcile-live-workshop'),
          label: tr(AppI10n.backupDetailWorkshopLive),
          folder: workshopLiveFolder,
          foreground: foreground,
          openTooltip: AppI10n.backupOpenLiveFolder,
        ),
      if (includeLive && evidence.liveMyProjects)
        _DetectedFolderCopy(
          key: const ValueKey<String>('backup-reconcile-live-myprojects'),
          label: tr(AppI10n.backupDetailMyProjectsLive),
          folder: myProjectsLiveFolder,
          foreground: foreground,
          openTooltip: AppI10n.backupOpenLiveFolder,
        ),
      if (includeBackup && evidence.backupWorkshop)
        _DetectedFolderCopy(
          key: const ValueKey<String>('backup-reconcile-backup-workshop'),
          label: tr(AppI10n.backupFolderBackupWorkshop),
          folder: workshopBackupFolder,
          foreground: foreground,
          openTooltip: AppI10n.backupOpenBackupFolder,
        ),
      if (includeBackup && evidence.backupMyProjects)
        _DetectedFolderCopy(
          key: const ValueKey<String>('backup-reconcile-backup-myprojects'),
          label: tr(AppI10n.backupFolderBackupMyProjects),
          folder: myProjectsBackupFolder,
          foreground: foreground,
          openTooltip: AppI10n.backupOpenBackupFolder,
        ),
    ];
  }

  Widget _compareFilesPrompt(Key key) => BackupDetailExpandPrompt(
    key: key,
    title: tr(AppI10n.backupDetailCompareFiles),
    subtitle: tr(AppI10n.backupDetailCompareFilesHint),
    foreground: foreground,
    onPressed: _requestComparison,
  );

  /// Keeps the shared Compare Files control visible while longer location lists
  /// scroll above it. Three-copy Reconcile states should not hide the action just
  /// because they carry more evidence than a two-copy conflict.
  Widget _locationsWithComparePrompt(
    List<Widget> copies, {
    required Key promptKey,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (copies.isNotEmpty)
          Expanded(
            child: BackupDetailScrollView(
              padding: const EdgeInsets.only(right: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  for (
                    int index = 0;
                    index < copies.length;
                    index++
                  ) ...<Widget>[
                    copies[index],
                    if (index != copies.length - 1) const SizedBox(height: 5),
                  ],
                ],
              ),
            ),
          ),
        if (copies.isNotEmpty) const SizedBox(height: 8),
        _compareFilesPrompt(promptKey),
      ],
    );
  }

  Widget _duplicateLiveAsyncDetails() {
    final Future<FolderFileComparison?> Function()? load =
        loadDuplicateLiveChanges;
    return _DeferredFolderComparison(
      active: _compareRequested,
      load: load,
      builder:
          (
            FolderFileComparison? comparison,
            bool comparing,
            bool comparisonFailed,
          ) {
            if (comparing) {
              return _duplicateLiveOverview(comparing: true);
            }
            if (comparisonFailed) {
              return _duplicateLiveOverview(comparisonFailed: true);
            }
            if (!_compareRequested) {
              return _duplicateLiveOverview(showComparePrompt: load != null);
            }
            return _duplicateLiveDetails(
              comparison: comparison,
              showTree: _hasDuplicateLiveDifferences(comparison?.changes),
            );
          },
    );
  }

  Widget _duplicateLiveOverview({
    FolderFileComparison? comparison,
    bool comparing = false,
    bool comparisonFailed = false,
    bool showComparePrompt = false,
  }) {
    final List<Widget> copies = _detectedLocationCards(
      includeLive: true,
      includeBackup: true,
    );
    if (showComparePrompt) {
      return _locationsWithComparePrompt(
        copies,
        promptKey: const ValueKey<String>(
          'backup-reconcile-expand-live-differences',
        ),
      );
    }

    final FolderFileChanges? changes = comparison?.changes;
    final bool hasDifferences = _hasDuplicateLiveDifferences(changes);
    return BackupDetailScrollView(
      padding: const EdgeInsets.only(right: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (int index = 0; index < copies.length; index++) ...<Widget>[
            copies[index],
            if (index != copies.length - 1) const SizedBox(height: 5),
          ],
          if (comparing) ...<Widget>[
            if (copies.isNotEmpty) const SizedBox(height: 12),
            Row(
              key: const ValueKey<String>(
                'backup-duplicate-live-comparison-progress',
              ),
              children: <Widget>[
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: foreground,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tr(AppI10n.backupDetailComparingFiles),
                    style: TextStyle(
                      color: foreground,
                      fontSize: 12,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ] else if (comparisonFailed) ...<Widget>[
            if (copies.isNotEmpty) const SizedBox(height: 12),
            BackupDetailGroup(
              title: tr(AppI10n.backupDetailFileChanges),
              items: <String>[
                tr(AppI10n.backupDetailFileComparisonUnavailable),
              ],
              foreground: foreground,
            ),
          ] else if (comparison != null && !hasDifferences) ...<Widget>[
            if (copies.isNotEmpty) const SizedBox(height: 10),
            BackupDetailGroup(
              key: const ValueKey<String>(
                'backup-duplicate-live-matching-files',
              ),
              title: tr(AppI10n.backupDetailMatchingFiles),
              items: comparison.matching.isEmpty
                  ? <String>[tr(AppI10n.backupDetailSame)]
                  : <String>[
                      for (final String filePath in comparison.matching)
                        '✓ $filePath',
                    ],
              foreground: foreground,
            ),
          ],
        ],
      ),
    );
  }

  Widget _duplicateLiveDetails({
    required FolderFileComparison? comparison,
    required bool showTree,
  }) {
    final FolderFileChanges? changes = comparison?.changes;
    if (showTree && changes != null) {
      final String workshopLabel =
          '${tr(AppI10n.backupDetailWorkshopLive)} / ${entry.name}';
      final String myProjectsLabel =
          '${tr(AppI10n.backupDetailMyProjectsLive)} / ${entry.name}';
      final Widget tree = FolderDifferenceFileTree(
        key: const ValueKey<String>('backup-duplicate-live-file-tree'),
        wallpaperName: entry.name,
        changes: changes,
        firstFolder: workshopLiveFolder,
        secondFolder: myProjectsLiveFolder,
        firstLabel: workshopLabel,
        secondLabel: myProjectsLabel,
        modifiedTitle: tr(AppI10n.backupDetailModified),
        firstOnlyTitle: tr(AppI10n.backupDetailInWorkshopLive),
        secondOnlyTitle: tr(AppI10n.backupDetailInMyProjectsLive),
        semanticLabel: tr(AppI10n.backupDetailLiveDifferences),
        unavailableText: tr(AppI10n.backupDetailFileComparisonUnavailable),
        openFolderTooltip: tr(AppI10n.backupOpenLiveFolder),
        keyBase: 'backup-duplicate-live',
        firstSideId: 'duplicate-live-workshop',
        secondSideId: 'duplicate-live-myprojects',
        firstFolderActionKey: 'backup-duplicate-live-workshop-button',
        secondFolderActionKey: 'backup-duplicate-live-myprojects-button',
        rePKGPath: rePKGPath,
        foreground: foreground,
      );
      final List<Widget> backupCopies = _detectedLocationCards(
        includeLive: false,
        includeBackup: true,
      );
      if (backupCopies.isEmpty) return tree;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (int index = 0; index < backupCopies.length; index++) ...<Widget>[
            backupCopies[index],
            if (index != backupCopies.length - 1) const SizedBox(height: 5),
          ],
          const SizedBox(height: 10),
          Expanded(child: tree),
        ],
      );
    }

    return _duplicateLiveOverview(comparison: comparison);
  }

  Widget _comparisonUnavailableDetails() {
    final List<Widget> copies = _detectedLocationCards(
      includeLive: true,
      includeBackup: true,
    );
    return BackupDetailScrollView(
      padding: const EdgeInsets.only(right: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (int index = 0; index < copies.length; index++) ...<Widget>[
            copies[index],
            if (index != copies.length - 1) const SizedBox(height: 6),
          ],
          if (copies.isNotEmpty) const SizedBox(height: 12),
          BackupDetailGroup(
            title: tr(AppI10n.backupDetailComparisonFailed),
            items: <String>[tr(AppI10n.backupDetailRescanAdvice)],
            foreground: foreground,
          ),
        ],
      ),
    );
  }

  Widget _conflictingBackupDetails({required bool showTree}) {
    if (showTree) {
      return BackupDifferenceFileTree(
        wallpaperName: entry.name,
        difference: entry.backupDifference,
        workshopBackupFolder: workshopBackupFolder,
        myProjectsBackupFolder: myProjectsBackupFolder,
        rePKGPath: rePKGPath,
        foreground: foreground,
      );
    }

    final List<Widget> copies = _detectedLocationCards(
      includeLive: false,
      includeBackup: true,
    );
    return _locationsWithComparePrompt(
      copies,
      promptKey: const ValueKey<String>('backup-reconcile-expand-differences'),
    );
  }
}
