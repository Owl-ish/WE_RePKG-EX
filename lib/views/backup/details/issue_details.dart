// Backup diagnostic detail presentation.
//
// Owns Junk and Reconcile explanations and evidence rendering. Classification
// and filesystem decisions remain in the Backup core and differ layers.

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

bool reconcileNeedsFileFocus(
  ReconcileEntry? entry, {
  bool ignored = false,
  BackupReconcileReason? reasonOverride,
}) {
  final BackupReconcileReason? reason = entry == null
      ? null
      : reasonOverride ??
            (ignored ? entry.ignoredPrimaryReason : entry.activePrimaryReason);
  if (entry == null ||
      reason != BackupReconcileReason.conflictingBackupCopies) {
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

String _reconcileExplanation(
  ReconcileEntry entry,
  BackupReconcileReason reason, {
  bool ignored = false,
}) {
  final String key = switch (reason) {
    BackupReconcileReason.duplicateLiveCopies =>
      ignored
          ? AppI10n.backupReconcileDuplicateLiveIgnoredAbout
          : AppI10n.backupReconcileDuplicateLiveAbout,
    BackupReconcileReason.conflictingBackupCopies =>
      ignored
          ? AppI10n.backupReconcileConflictingBackupsIgnoredAbout
          : AppI10n.backupReconcileConflictingBackupsAbout,
    BackupReconcileReason.comparisonUnavailable =>
      AppI10n.backupReconcileComparisonUnavailableAbout,
  };
  final List<String> locations = <String>[
    if (entry.liveWorkshop) tr(AppI10n.homeLibraryWorkshop),
    if (entry.liveMyProjects) tr(AppI10n.homeLibraryMyProjects),
  ];
  return tr(
    key,
    namedArgs:
        reason == BackupReconcileReason.duplicateLiveCopies &&
            locations.length >= 2
        ? <String, String>{'location1': locations[0], 'location2': locations[1]}
        : const <String, String>{},
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
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
            ),
          ],
        ],
      ),
    );
  }
}

class ReconcileDetailContent extends StatefulWidget {
  const ReconcileDetailContent({
    super.key,
    required this.entry,
    this.primaryReasonOverride,
    required this.foreground,
    required this.needsFocus,
    required this.workshopLiveFolder,
    required this.myProjectsLiveFolder,
    required this.workshopBackupFolder,
    required this.myProjectsBackupFolder,
    this.ignoredMode = false,
    this.loadDuplicateLiveChanges,
    this.onRequestFocus,
  });

  final ReconcileEntry entry;
  final BackupReconcileReason? primaryReasonOverride;
  final Color foreground;
  final bool needsFocus;
  final String? workshopLiveFolder;
  final String? myProjectsLiveFolder;
  final String? workshopBackupFolder;
  final String? myProjectsBackupFolder;
  final bool ignoredMode;
  final Future<FolderFileComparison?> Function()? loadDuplicateLiveChanges;
  final VoidCallback? onRequestFocus;

  @override
  State<ReconcileDetailContent> createState() => _ReconcileDetailContentState();
}

class _ReconcileDetailContentState extends State<ReconcileDetailContent> {
  bool _differencesRequested = false;
  Future<FolderFileComparison?>? _duplicateLiveComparison;

  BackupReconcileReason get _primaryReason =>
      widget.primaryReasonOverride ??
      (widget.ignoredMode
          ? widget.entry.ignoredPrimaryReason
          : widget.entry.activePrimaryReason) ??
      widget.entry.reason;

  void _requestDifferences() {
    if (_differencesRequested) return;
    final Future<FolderFileComparison?> Function()? load =
        _primaryReason == BackupReconcileReason.duplicateLiveCopies
        ? widget.loadDuplicateLiveChanges
        : null;
    setState(() {
      _differencesRequested = true;
      _duplicateLiveComparison = load == null
          ? null
          : Future<FolderFileComparison?>.sync(load);
    });
    widget.onRequestFocus?.call();
  }

  @override
  void didUpdateWidget(covariant ReconcileDetailContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entry.name != widget.entry.name ||
        oldWidget.entry.reason != widget.entry.reason ||
        oldWidget.ignoredMode != widget.ignoredMode ||
        oldWidget.primaryReasonOverride != widget.primaryReasonOverride ||
        oldWidget.loadDuplicateLiveChanges != widget.loadDuplicateLiveChanges) {
      _differencesRequested = false;
      _duplicateLiveComparison = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final Set<BackupReconcileReason> displayReasons =
        widget.primaryReasonOverride == null
        ? (widget.ignoredMode
              ? widget.entry.ignoredReasons
              : widget.entry.activeReasons)
        : <BackupReconcileReason>{widget.primaryReasonOverride!};
    final BackupReconcileReason primary = _primaryReason;
    final List<BackupReconcileReason> secondaryReasons =
        displayReasons.difference(<BackupReconcileReason>{primary}).toList()
          ..sort((a, b) => a.index.compareTo(b.index));
    final List<BackupState> attentionStates =
        widget.entry.evidence.attentionStates.toList()..sort(
          (a, b) => (backupSeverity[a] ?? 0).compareTo(backupSeverity[b] ?? 0),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          _reconcileExplanation(
            widget.entry,
            primary,
            ignored: widget.ignoredMode,
          ),
          style: TextStyle(color: widget.foreground, height: 1.35),
        ),
        if (secondaryReasons.isNotEmpty || attentionStates.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final BackupReconcileReason reason in secondaryReasons)
            Text(
              '• ${_reconcileExplanation(widget.entry, reason, ignored: widget.ignoredMode)}',
              style: TextStyle(
                color: widget.foreground,
                height: 1.3,
                fontSize: 12,
              ),
            ),
          for (final BackupState state in attentionStates)
            Text(
              '• ${tr(_reconcileStateLabel(state))}',
              style: TextStyle(
                color: widget.foreground,
                height: 1.3,
                fontSize: 12,
              ),
            ),
        ],
        const SizedBox(height: 12),
        Expanded(child: _details(context)),
      ],
    );
  }

  Widget _details(BuildContext context) {
    final BackupReconcileReason primary = _primaryReason;
    return switch (primary) {
      BackupReconcileReason.duplicateLiveCopies => _duplicateLiveDetails(),
      BackupReconcileReason.comparisonUnavailable => SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _detectedLocations(includeLive: true, includeBackup: true),
            BackupDetailGroup(
              title: tr(AppI10n.backupDetailComparisonFailed),
              items: <String>[tr(AppI10n.backupDetailRescanAdvice)],
              foreground: widget.foreground,
            ),
          ],
        ),
      ),
      BackupReconcileReason.conflictingBackupCopies
          when widget.needsFocus && !_differencesRequested =>
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _detectedLocations(includeLive: false, includeBackup: true),
            Semantics(
              button: true,
              label: tr(AppI10n.backupDetailExpandDifferences),
              onTap: _requestDifferences,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  excludeFromSemantics: true,
                  onTap: _requestDifferences,
                  child: FileTreeSurface(
                    key: const ValueKey<String>(
                      'backup-reconcile-expand-differences',
                    ),
                    foreground: widget.foreground,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 14,
                      ),
                      child: Row(
                        children: <Widget>[
                          Icon(
                            Icons.unfold_more_rounded,
                            size: 18,
                            color: widget.foreground.withValues(alpha: .75),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              tr(AppI10n.backupDetailExpandDifferences),
                              textAlign: TextAlign.center,
                              softWrap: true,
                              style: TextStyle(
                                color: widget.foreground,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      BackupReconcileReason.conflictingBackupCopies => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _detectedLocations(includeLive: false, includeBackup: true),
          Expanded(
            child: BackupDifferenceFileTree(
              difference: widget.entry.backupDifference,
              foreground: widget.foreground,
            ),
          ),
        ],
      ),
    };
  }

  Widget _duplicateLiveDetails() {
    final Future<FolderFileComparison?> Function()? load =
        widget.loadDuplicateLiveChanges;
    if (!_differencesRequested || load == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(
            child: BackupDetailScrollView(
              padding: const EdgeInsets.only(right: 10),
              child: _detectedLocations(includeLive: true, includeBackup: true),
            ),
          ),
          if (load != null) ...<Widget>[
            const SizedBox(height: 8),
            BackupDetailExpandPrompt(
              key: const ValueKey<String>(
                'backup-reconcile-expand-live-differences',
              ),
              title: tr(AppI10n.backupDetailCompareFiles),
              subtitle: tr(AppI10n.backupDetailCompareFilesHint),
              foreground: widget.foreground,
              onPressed: _requestDifferences,
            ),
          ],
        ],
      );
    }

    return FutureBuilder<FolderFileComparison?>(
      future: _duplicateLiveComparison,
      builder:
          (
            BuildContext context,
            AsyncSnapshot<FolderFileComparison?> snapshot,
          ) {
            if (snapshot.connectionState != ConnectionState.done) {
              return _duplicateLiveMessage(
                tr(AppI10n.backupDetailComparingFiles),
                progress: true,
              );
            }
            final FolderFileComparison? comparison = snapshot.data;
            if (snapshot.hasError || comparison == null) {
              return _duplicateLiveMessage(
                tr(AppI10n.backupDetailFileComparisonUnavailable),
              );
            }
            final FolderFileChanges changes = comparison.changes;
            final bool hasDifferences =
                changes.modified.isNotEmpty ||
                changes.onlyFirst.isNotEmpty ||
                changes.onlySecond.isNotEmpty;
            if (!hasDifferences) {
              return BackupDetailScrollView(
                padding: const EdgeInsets.only(right: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _detectedLocations(includeLive: true, includeBackup: true),
                    const SizedBox(height: 10),
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
                      foreground: widget.foreground,
                    ),
                  ],
                ),
              );
            }

            final bool hasBackup =
                widget.entry.evidence.backupWorkshop ||
                widget.entry.evidence.backupMyProjects;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (hasBackup) ...<Widget>[
                  _detectedLocations(includeLive: false, includeBackup: true),
                  const SizedBox(height: 10),
                ],
                Expanded(
                  child: FolderDifferenceFileTree(
                    key: const ValueKey<String>(
                      'backup-duplicate-live-file-tree',
                    ),
                    changes: changes,
                    modifiedTitle: tr(AppI10n.backupDetailModified),
                    firstOnlyTitle: tr(AppI10n.backupDetailInWorkshopLive),
                    secondOnlyTitle: tr(AppI10n.backupDetailInMyProjectsLive),
                    semanticLabel: tr(AppI10n.backupDetailLiveDifferences),
                    unavailableText: tr(
                      AppI10n.backupDetailFileComparisonUnavailable,
                    ),
                    keyBase: 'backup-duplicate-live',
                    foreground: widget.foreground,
                  ),
                ),
              ],
            );
          },
    );
  }

  Widget _duplicateLiveMessage(String message, {bool progress = false}) =>
      BackupDetailScrollView(
        padding: const EdgeInsets.only(right: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _detectedLocations(includeLive: true, includeBackup: true),
            const SizedBox(height: 10),
            FileTreeSurface(
              foreground: widget.foreground,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  key: progress
                      ? const ValueKey<String>(
                          'backup-duplicate-live-comparison-progress',
                        )
                      : null,
                  children: <Widget>[
                    if (progress) ...<Widget>[
                      SizedBox.square(
                        dimension: 15,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: widget.foreground.withValues(alpha: .7),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Text(
                        message,
                        style: TextStyle(color: widget.foreground, height: 1.3),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );

  Widget _detectedLocations({
    required bool includeLive,
    required bool includeBackup,
  }) {
    final BackupIssueEvidence evidence = widget.entry.evidence;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          tr(AppI10n.backupDetailDetectedCopies),
          style: TextStyle(
            color: widget.foreground,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        if (includeLive && evidence.liveWorkshop)
          _DetectedFolderCopy(
            key: const ValueKey<String>('backup-reconcile-live-workshop'),
            label: tr(AppI10n.backupDetailWorkshopLive),
            folder: widget.workshopLiveFolder,
            foreground: widget.foreground,
            openTooltip: AppI10n.backupOpenWorkshopLiveFolder,
          ),
        if (includeLive && evidence.liveMyProjects)
          _DetectedFolderCopy(
            key: const ValueKey<String>('backup-reconcile-live-myprojects'),
            label: tr(AppI10n.backupDetailMyProjectsLive),
            folder: widget.myProjectsLiveFolder,
            foreground: widget.foreground,
            openTooltip: AppI10n.backupOpenMyProjectsLiveFolder,
          ),
        if (includeBackup && evidence.backupWorkshop)
          _DetectedFolderCopy(
            key: const ValueKey<String>('backup-reconcile-backup-workshop'),
            label: tr(AppI10n.backupFolderBackupWorkshop),
            folder: widget.workshopBackupFolder,
            foreground: widget.foreground,
            openTooltip: AppI10n.backupOpenWorkshopBackupFolder,
          ),
        if (includeBackup && evidence.backupMyProjects)
          _DetectedFolderCopy(
            key: const ValueKey<String>('backup-reconcile-backup-myprojects'),
            label: tr(AppI10n.backupFolderBackupMyProjects),
            folder: widget.myProjectsBackupFolder,
            foreground: widget.foreground,
            openTooltip: AppI10n.backupOpenMyProjectsBackupFolder,
          ),
      ],
    );
  }
}
