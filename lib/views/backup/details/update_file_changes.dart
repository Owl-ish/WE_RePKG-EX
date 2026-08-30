import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:we_repkg/config/theme_extensions.dart';
import 'package:we_repkg/constants/i10n.dart';
import 'package:we_repkg/cores/backup.dart';
import 'package:we_repkg/views/backup/details/backup_update_selection.dart';
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
    this.selection,
  });

  final String liveFolder;
  final String backupFolder;
  final Color foreground;

  /// Optional seam for callers that already own the comparison or for tests.
  final BackupFileChangesLoader? loader;
  final BackupUpdateSelection? selection;

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
        oldWidget.loader != widget.loader ||
        oldWidget.selection != widget.selection) {
      _changes = _load();
    }
  }

  Future<BackupFileChanges?> _load() =>
      widget.selection?.changes ??
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

          final BackupUpdateSelection? selection = widget.selection;
          if (selection == null) return _tree(context, changes);
          return AnimatedBuilder(
            animation: selection,
            builder: (BuildContext context, Widget? _) =>
                _tree(context, changes),
          );
        },
  );

  Widget _tree(BuildContext context, BackupFileChanges changes) {
    final StatusPalette colours = Theme.of(context).status;
    return FileTreeScrollView(
      key: const ValueKey<String>('backup-update-file-tree'),
      foreground: widget.foreground,
      semanticLabel:
          '${tr(AppI10n.backupDetailFileChanges)}: '
          '${changes.modified.length + changes.onlyLive.length + changes.onlyBackup.length}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (changes.modified.isNotEmpty)
            _group(
              id: 'modified',
              title: tr(AppI10n.backupDetailModified),
              paths: changes.modified,
              accent: colours.warn,
            ),
          if (changes.onlyLive.isNotEmpty)
            _group(
              id: 'only-live',
              title: tr(AppI10n.backupDetailAddedFiles),
              paths: changes.onlyLive,
              accent: colours.good,
            ),
          if (changes.onlyBackup.isNotEmpty)
            _group(
              id: 'only-backup',
              title: tr(AppI10n.backupDetailRemovedFiles),
              paths: changes.onlyBackup,
              accent: colours.note,
              deletion: true,
            ),
        ],
      ),
    );
  }

  Widget _group({
    required String id,
    required String title,
    required List<String> paths,
    required Color accent,
    bool deletion = false,
  }) {
    final BackupUpdateSelection? selection = widget.selection;
    final bool? groupSelected = selection == null
        ? null
        : deletion
        ? selection.deletionGroupSelected(paths)
        : selection.copyGroupSelected(paths);
    return FileTreeGroup(
      title: title,
      count: paths.length,
      accent: accent,
      foreground: widget.foreground,
      trailing: selection == null
          ? null
          : FileTreeRowChoice(
              selected: groupSelected,
              onChanged: (bool value) => deletion
                  ? selection.setDeletionGroupSelected(paths, value)
                  : selection.setCopyGroupSelected(paths, value),
              rejectTooltip: tr(AppI10n.backupDetailDeselectAll),
              acceptTooltip: tr(AppI10n.backupDetailSelectAll),
              foreground: widget.foreground,
              rejectKey: ValueKey<String>('backup-update-group-reject-$id'),
              acceptKey: ValueKey<String>('backup-update-group-accept-$id'),
            ),
      children: <Widget>[
        for (final String filePath in paths)
          FileTreeRow(
            key: ValueKey<String>('backup-update-file-$id-$filePath'),
            depth: 1,
            icon: Icons.insert_drive_file_outlined,
            label: filePath,
            subtitle: deletion && selection != null
                ? tr(
                    selection.deletionSelected(filePath)
                        ? AppI10n.backupDetailWillRemove
                        : AppI10n.backupDetailWillKeep,
                  )
                : null,
            foreground: widget.foreground,
            iconColor: accent,
            trailing: selection == null
                ? null
                : FileTreeRowChoice(
                    selected: deletion
                        ? selection.deletionSelected(filePath)
                        : selection.copySelected(filePath),
                    onChanged: (bool value) => deletion
                        ? selection.setDeletionSelected(filePath, value)
                        : selection.setCopySelected(filePath, value),
                    rejectTooltip: tr(
                      deletion
                          ? AppI10n.backupDetailKeepBackupFile
                          : AppI10n.backupDetailKeepOld,
                    ),
                    acceptTooltip: tr(
                      deletion
                          ? AppI10n.backupDetailRemoveBackupFile
                          : AppI10n.backupDetailApplyChange,
                    ),
                    foreground: widget.foreground,
                    rejectKey: ValueKey<String>(
                      'backup-update-reject-$filePath',
                    ),
                    acceptKey: ValueKey<String>(
                      'backup-update-accept-$filePath',
                    ),
                  ),
            hoverHighlight: false,
          ),
      ],
    );
  }

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
