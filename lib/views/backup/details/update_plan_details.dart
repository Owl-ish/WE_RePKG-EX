import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:we_repkg/constants/i10n.dart';
import 'package:we_repkg/utils/backup_diff.dart';
import 'package:we_repkg/views/backup/details/detail_layout.dart';
import 'package:we_repkg/views/backup/details/sync_details.dart';

/// Presents the content refresh and placement work in an Update plan.
class UpdatePlanDetailContent extends StatelessWidget {
  const UpdatePlanDetailContent({
    super.key,
    required this.plan,
    required this.card,
    required this.foreground,
  });

  final BackupUpdatePlan plan;
  final BackupCard card;
  final Color foreground;

  String _backupPath(WallpaperLibrary library) {
    final String root = tr(switch (library) {
      WallpaperLibrary.workshop => AppI10n.backupFolderBackupWorkshop,
      WallpaperLibrary.myProjects => AppI10n.backupFolderBackupMyProjects,
    });
    return '$root\\${card.name}';
  }

  @override
  Widget build(BuildContext context) {
    final BackupSyncPlan? sync = plan.sync;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (plan.updateContent)
          BackupDetailGroup(
            title: tr(AppI10n.backupTileUpdate),
            items: <String>[tr(AppI10n.backupDetailUpdateToLive)],
            foreground: foreground,
          ),
        if (sync != null && sync.kind == BackupSyncKind.relocate)
          SyncMoveDetail(
            fromPath: _backupPath(sync.from),
            toPath: _backupPath(sync.to),
            foreground: foreground,
          ),
        if (sync != null && sync.kind == BackupSyncKind.removeDuplicate)
          SyncDuplicateDetail(
            keepPath: _backupPath(sync.to),
            removePath: _backupPath(sync.from),
            foreground: foreground,
          ),
      ],
    );
  }
}
