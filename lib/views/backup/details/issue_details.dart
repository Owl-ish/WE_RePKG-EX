// Backup diagnostic detail presentation.
//
// Owns Junk and Reconcile explanations and evidence rendering. Classification
// and filesystem decisions remain in the Backup core and differ layers.

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:we_repkg/config/theme_extensions.dart';
import 'package:we_repkg/constants/i10n.dart';
import 'package:we_repkg/utils/backup_diff.dart';
import 'package:we_repkg/utils/wallpaper_junk.dart';
import 'package:we_repkg/views/backup/details/detail_layout.dart';
import 'package:we_repkg/widgets/file_tree_panel.dart';

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

bool reconcileNeedsFileFocus(ReconcileEntry? entry) {
  if (entry == null ||
      entry.reason != BackupReconcileReason.conflictingBackupCopies) {
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

class ReconcileDetailContent extends StatelessWidget {
  const ReconcileDetailContent({
    super.key,
    required this.entry,
    required this.foreground,
    required this.focused,
    required this.needsFocus,
  });

  final ReconcileEntry entry;
  final Color foreground;
  final bool focused;
  final bool needsFocus;

  @override
  Widget build(BuildContext context) {
    final String explanation = switch (entry.reason) {
      BackupReconcileReason.duplicateLiveCopies =>
        AppI10n.backupReconcileDuplicateLiveAbout,
      BackupReconcileReason.conflictingBackupCopies =>
        AppI10n.backupReconcileConflictingBackupsAbout,
      BackupReconcileReason.comparisonUnavailable =>
        AppI10n.backupReconcileComparisonUnavailableAbout,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          tr(explanation),
          style: TextStyle(color: foreground, height: 1.35),
        ),
        const SizedBox(height: 12),
        Expanded(child: _details(context)),
      ],
    );
  }

  Widget _details(BuildContext context) => switch (entry.reason) {
    BackupReconcileReason.duplicateLiveCopies => SingleChildScrollView(
      child: BackupDetailGroup(
        title: tr(AppI10n.backupDetailDetectedCopies),
        items: <String>[
          tr(AppI10n.backupDetailWorkshopLive),
          tr(AppI10n.backupDetailMyProjectsLive),
        ],
        foreground: foreground,
      ),
    ),
    BackupReconcileReason.comparisonUnavailable => SingleChildScrollView(
      child: BackupDetailGroup(
        title: tr(AppI10n.backupDetailComparisonFailed),
        items: <String>[tr(AppI10n.backupDetailRescanAdvice)],
        foreground: foreground,
      ),
    ),
    BackupReconcileReason.conflictingBackupCopies when needsFocus && !focused =>
      FileTreeSurface(
        key: const ValueKey<String>('backup-reconcile-expand-differences'),
        foreground: foreground,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            child: Row(
              children: <Widget>[
                Icon(
                  Icons.unfold_more_rounded,
                  size: 18,
                  color: foreground.withValues(alpha: .75),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tr(AppI10n.backupDetailExpandDifferences),
                    textAlign: TextAlign.center,
                    softWrap: true,
                    style: TextStyle(
                      color: foreground,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    BackupReconcileReason.conflictingBackupCopies => _DifferenceFileTree(
      difference: entry.backupDifference,
      foreground: foreground,
    ),
  };
}

class _DifferenceFileTree extends StatelessWidget {
  const _DifferenceFileTree({
    required this.difference,
    required this.foreground,
  });

  final BackupCopyDifference? difference;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final BackupCopyDifference? value = difference;
    if (value == null || value.total == 0) {
      return FileTreeSurface(
        foreground: foreground,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Text(
            tr(AppI10n.backupDetailDifferenceUnavailable),
            style: TextStyle(color: foreground, height: 1.3),
          ),
        ),
      );
    }
    final StatusPalette colours = Theme.of(context).status;
    return FileTreeScrollView(
      key: const ValueKey<String>('backup-reconcile-detail-scroll'),
      foreground: foreground,
      semanticLabel:
          '${tr(AppI10n.backupDetailDetectedDifferences)}: ${value.total}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (value.differentSize.isNotEmpty)
            _differenceGroup(
              title: tr(AppI10n.backupDetailDifferentSize),
              paths: value.differentSize,
              colour: colours.warn,
            ),
          if (value.onlyWorkshop.isNotEmpty)
            _differenceGroup(
              title: tr(AppI10n.backupDetailOnlyWorkshop),
              paths: value.onlyWorkshop,
              colour: fileTreeLibraryColour(context, FileTreeLibrary.workshop),
            ),
          if (value.onlyMyProjects.isNotEmpty)
            _differenceGroup(
              title: tr(AppI10n.backupDetailOnlyMyProjects),
              paths: value.onlyMyProjects,
              colour: fileTreeLibraryColour(
                context,
                FileTreeLibrary.myProjects,
              ),
            ),
        ],
      ),
    );
  }

  Widget _differenceGroup({
    required String title,
    required List<String> paths,
    required Color colour,
  }) {
    final List<String> ordered = List<String>.from(
      paths,
    )..sort((String a, String b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return FileTreeGroup(
      title: title,
      count: ordered.length,
      accent: colour,
      foreground: foreground,
      children: <Widget>[
        for (final String filePath in ordered)
          FileTreeRow(
            depth: 1,
            icon: Icons.insert_drive_file_outlined,
            iconColor: colour,
            label: filePath.replaceAll('\\', '  ›  ').replaceAll('/', '  ›  '),
            foreground: foreground,
          ),
      ],
    );
  }
}
