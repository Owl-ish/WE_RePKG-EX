import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:we_repkg/constants/i10n.dart';
import 'package:we_repkg/utils/backup_diff.dart';
import 'package:we_repkg/views/backup/details/detail_layout.dart';
import 'package:we_repkg/views/backup/details/sync_details.dart';
import 'package:we_repkg/views/backup/details/update_file_changes.dart';

/// Presents the content refresh and placement work in an Update plan.
class UpdatePlanDetailContent extends StatelessWidget {
  const UpdatePlanDetailContent({
    super.key,
    required this.plan,
    required this.card,
    required this.foreground,
    required this.focused,
    required this.needsFocus,
    this.liveFolder,
    this.backupFolder,
    this.loadFileChanges,
    this.onRequestFocus,
  });

  final BackupUpdatePlan plan;
  final BackupCard card;
  final Color foreground;
  final bool focused;
  final bool needsFocus;
  final String? liveFolder;
  final String? backupFolder;
  final BackupFileChangesLoader? loadFileChanges;
  final VoidCallback? onRequestFocus;

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
        if (plan.updateContent &&
            (!needsFocus || focused) &&
            liveFolder != null &&
            backupFolder != null)
          Expanded(
            child: UpdateFileChanges(
              liveFolder: liveFolder!,
              backupFolder: backupFolder!,
              foreground: foreground,
              loader: loadFileChanges,
            ),
          ),
        if (!plan.updateContent && syncDetail != null)
          Expanded(
            child: Align(
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
