import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:we_repkg/config/theme_extensions.dart';
import 'package:we_repkg/constants/i10n.dart';
import 'package:we_repkg/cores/backup.dart';
import 'package:we_repkg/utils/backup_diff.dart';
import 'package:we_repkg/widgets/file_tree_panel.dart';

/// Backup-specific wrapper around the shared read-only difference tree.
class BackupDifferenceFileTree extends StatelessWidget {
  const BackupDifferenceFileTree({
    super.key,
    required this.difference,
    required this.foreground,
  });

  final BackupCopyDifference? difference;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final BackupCopyDifference? difference = this.difference;
    return FolderDifferenceFileTree(
      changes: difference == null
          ? null
          : (
              modified: difference.differentSize,
              onlyFirst: difference.onlyWorkshop,
              onlySecond: difference.onlyMyProjects,
            ),
      modifiedTitle: tr(AppI10n.backupDetailDifferentSize),
      firstOnlyTitle: tr(AppI10n.backupDetailOnlyWorkshop),
      secondOnlyTitle: tr(AppI10n.backupDetailOnlyMyProjects),
      semanticLabel: tr(AppI10n.backupDetailDetectedDifferences),
      unavailableText: tr(AppI10n.backupDetailDifferenceUnavailable),
      keyBase: 'backup-reconcile',
      foreground: foreground,
    );
  }
}

/// Presents exact differences between two folders without changing either side.
class FolderDifferenceFileTree extends StatelessWidget {
  const FolderDifferenceFileTree({
    super.key,
    required this.changes,
    required this.modifiedTitle,
    required this.firstOnlyTitle,
    required this.secondOnlyTitle,
    required this.semanticLabel,
    required this.unavailableText,
    required this.keyBase,
    required this.foreground,
  });

  final FolderFileChanges? changes;
  final String modifiedTitle;
  final String firstOnlyTitle;
  final String secondOnlyTitle;
  final String semanticLabel;
  final String unavailableText;
  final String keyBase;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final FolderFileChanges? value = changes;
    final int total = value == null
        ? 0
        : value.modified.length +
              value.onlyFirst.length +
              value.onlySecond.length;
    if (value == null || total == 0) {
      return FileTreeSurface(
        foreground: foreground,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Text(
            unavailableText,
            style: TextStyle(color: foreground, height: 1.3),
          ),
        ),
      );
    }

    final StatusPalette colours = Theme.of(context).status;
    return FileTreeScrollView(
      key: ValueKey<String>('$keyBase-detail-scroll'),
      foreground: foreground,
      semanticLabel: '$semanticLabel: $total',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (value.modified.isNotEmpty)
            _group(
              id: 'modified',
              title: modifiedTitle,
              paths: value.modified,
              colour: colours.warn,
            ),
          if (value.onlyFirst.isNotEmpty)
            _group(
              id: 'first-only',
              title: firstOnlyTitle,
              paths: value.onlyFirst,
              colour: fileTreeLibraryColour(context, FileTreeLibrary.workshop),
            ),
          if (value.onlySecond.isNotEmpty)
            _group(
              id: 'second-only',
              title: secondOnlyTitle,
              paths: value.onlySecond,
              colour: fileTreeLibraryColour(
                context,
                FileTreeLibrary.myProjects,
              ),
            ),
        ],
      ),
    );
  }

  Widget _group({
    required String id,
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
            key: ValueKey<String>('$keyBase-file-$id-$filePath'),
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
