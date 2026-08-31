// Backup Sync plan presentation.
//
// Explains where a misplaced backup will move, or which duplicate backup will
// be kept and removed. This file only presents an already-computed Sync plan;
// filesystem relocation and cleanup remain in the Backup action/core layers.

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:we_repkg/constants/i10n.dart';
import 'package:we_repkg/widgets/input_controls.dart';

class _SyncMoveHeading extends StatelessWidget {
  const _SyncMoveHeading({required this.foreground});

  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final String heading = tr(AppI10n.backupDetailSyncWillMove);
    final int separator = heading.indexOf(' - ');
    if (separator < 0) {
      return Text(heading, style: TextStyle(color: foreground));
    }
    return Text.rich(
      TextSpan(
        style: TextStyle(color: foreground),
        children: <InlineSpan>[
          TextSpan(
            text: heading.substring(0, separator),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          TextSpan(text: heading.substring(separator)),
        ],
      ),
    );
  }
}

/// Shows the source and destination paths for a backup relocation Sync.
class SyncMoveDetail extends StatelessWidget {
  const SyncMoveDetail({
    super.key,
    required this.fromPath,
    required this.toPath,
    required this.foreground,
  });

  final String fromPath;
  final String toPath;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          key: const ValueKey<String>('backup-sync-move-heading'),
          padding: const EdgeInsets.only(bottom: 8),
          child: _SyncMoveHeading(foreground: foreground),
        ),
        ReadOnlyPathBox(path: fromPath),
        const SizedBox(height: 1),
        Center(
          child: Icon(
            Icons.keyboard_arrow_down_rounded,
            color: foreground.withValues(alpha: .72),
            size: 18,
          ),
        ),
        const SizedBox(height: 1),
        ReadOnlyPathBox(path: toPath),
      ],
    );
  }
}

/// Shows which duplicate backup copy Sync will keep and which it will remove.
class SyncDuplicateDetail extends StatelessWidget {
  const SyncDuplicateDetail({
    super.key,
    required this.keepPath,
    required this.removePath,
    required this.foreground,
  });

  final String keepPath;
  final String removePath;
  final Color foreground;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      Text(
        tr(AppI10n.backupTileSync),
        style: TextStyle(color: foreground, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 6),
      Text(
        tr(AppI10n.backupDetailSyncWillKeep),
        style: TextStyle(color: foreground),
      ),
      const SizedBox(height: 4),
      ReadOnlyPathBox(path: keepPath),
      const SizedBox(height: 6),
      Text(
        tr(AppI10n.backupDetailSyncWillRemove),
        style: TextStyle(color: foreground),
      ),
      const SizedBox(height: 4),
      ReadOnlyPathBox(path: removePath),
    ],
  );
}
