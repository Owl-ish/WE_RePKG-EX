import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:we_repkg/config/theme_extensions.dart';
import 'package:we_repkg/constants/i10n.dart';
import 'package:we_repkg/cores/backup.dart';
import 'package:we_repkg/widgets/file_tree_panel.dart';

typedef BackupFileChangesLoader = Future<BackupFileChanges?> Function();

/// Loads and presents the live-to-backup file changes for one Update.
///
/// This widget is intentionally mounted only after the user expands the file
/// pane. Constructing ordinary wallpaper details therefore does no recursive
/// filesystem work.
class UpdateFileChanges extends StatefulWidget {
  const UpdateFileChanges({
    super.key,
    required this.liveFolder,
    required this.backupFolder,
    required this.foreground,
    this.loader,
  });

  final String liveFolder;
  final String backupFolder;
  final Color foreground;

  /// Optional seam for callers that already own the comparison or for tests.
  final BackupFileChangesLoader? loader;

  @override
  State<UpdateFileChanges> createState() => _UpdateFileChangesState();
}

class _UpdateFileChangesState extends State<UpdateFileChanges> {
  late Future<BackupFileChanges?> _changes;

  @override
  void initState() {
    super.initState();
    _changes = _load();
  }

  @override
  void didUpdateWidget(covariant UpdateFileChanges oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.liveFolder != widget.liveFolder ||
        oldWidget.backupFolder != widget.backupFolder ||
        oldWidget.loader != widget.loader) {
      _changes = _load();
    }
  }

  Future<BackupFileChanges?> _load() =>
      widget.loader?.call() ??
      compareBackupFileChanges(
        liveFolder: widget.liveFolder,
        backupFolder: widget.backupFolder,
      );

  @override
  Widget build(BuildContext context) => FutureBuilder<BackupFileChanges?>(
    future: _changes,
    builder:
        (BuildContext context, AsyncSnapshot<BackupFileChanges?> snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return _message(
              tr(AppI10n.backupDetailComparingFiles),
              progress: true,
            );
          }
          final BackupFileChanges? changes = snapshot.data;
          if (snapshot.hasError || changes == null) {
            return _message(tr(AppI10n.backupDetailFileComparisonUnavailable));
          }
          final int total =
              changes.modified.length +
              changes.onlyLive.length +
              changes.onlyBackup.length;
          if (total == 0) {
            return _message(tr(AppI10n.backupDetailNoFileDifferences));
          }

          final StatusPalette colours = Theme.of(context).status;
          return FileTreeScrollView(
            key: const ValueKey<String>('backup-update-file-tree'),
            foreground: widget.foreground,
            semanticLabel: '${tr(AppI10n.backupDetailFileChanges)}: $total',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (changes.modified.isNotEmpty)
                  _group(
                    title: tr(AppI10n.backupDetailModified),
                    paths: changes.modified,
                    accent: colours.warn,
                  ),
                if (changes.onlyLive.isNotEmpty)
                  _group(
                    title: tr(AppI10n.backupDetailAddedFiles),
                    paths: changes.onlyLive,
                    accent: colours.good,
                  ),
                if (changes.onlyBackup.isNotEmpty)
                  _group(
                    title: tr(AppI10n.backupDetailRemovedFiles),
                    paths: changes.onlyBackup,
                    accent: colours.note,
                  ),
              ],
            ),
          );
        },
  );

  Widget _group({
    required String title,
    required List<String> paths,
    required Color accent,
  }) => FileTreeGroup(
    title: title,
    count: paths.length,
    accent: accent,
    foreground: widget.foreground,
    children: <Widget>[
      for (final String filePath in paths)
        FileTreeRow(
          key: ValueKey<String>('backup-update-file-$title-$filePath'),
          depth: 1,
          icon: Icons.insert_drive_file_outlined,
          label: filePath,
          foreground: widget.foreground,
          iconColor: accent,
          hoverHighlight: false,
        ),
    ],
  );

  Widget _message(String text, {bool progress = false}) => FileTreeSurface(
    foreground: widget.foreground,
    child: Padding(
      padding: const EdgeInsets.all(10),
      child: Row(
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
              text,
              style: TextStyle(color: widget.foreground, height: 1.3),
            ),
          ),
        ],
      ),
    ),
  );
}
