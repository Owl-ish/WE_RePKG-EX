import 'dart:math';

import 'package:bot_toast/bot_toast.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:we_repkg/constants/i10n.dart';
import 'package:we_repkg/cores/backup_action.dart';
import 'package:we_repkg/cores/toast.dart';
import 'package:we_repkg/models/enums.dart';
import 'package:we_repkg/provider/backup.dart';
import 'package:we_repkg/provider/integrity.dart';
import 'package:we_repkg/provider/system.dart';
import 'package:we_repkg/provider/wallpaper.dart';
import 'package:we_repkg/utils/backup_diff.dart';
import 'package:we_repkg/widgets/confirm_dialog.dart';

typedef BackupActionRunner =
    Future<BackupActionResult> Function(
      BackupAction action,
      List<BackupCard> cards,
    );

/// Shared attention halo for backup actions. The control inside keeps its own
/// shape and fill; this only supplies the outward pulse.
class BackupActionGlow extends StatefulWidget {
  const BackupActionGlow({
    super.key,
    required this.colour,
    required this.enabled,
    required this.borderRadius,
    required this.child,
    this.glowKey,
    this.scale = 1,
  });

  final Color colour;
  final bool enabled;
  final BorderRadiusGeometry borderRadius;
  final Widget child;
  final Key? glowKey;
  final double scale;

  @override
  State<BackupActionGlow> createState() => _BackupActionGlowState();
}

class _BackupActionGlowState extends State<BackupActionGlow>
    with SingleTickerProviderStateMixin {
  static const Duration _period = Duration(milliseconds: 2200);
  late final AnimationController _glow = AnimationController(
    vsync: this,
    duration: _period,
  );

  @override
  void initState() {
    super.initState();
    if (widget.enabled) _glow.repeat();
  }

  @override
  void didUpdateWidget(BackupActionGlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled && !_glow.isAnimating) {
      _glow.repeat();
    } else if (!widget.enabled && _glow.isAnimating) {
      _glow.stop();
      _glow.value = 0;
    }
  }

  @override
  void dispose() {
    _glow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _glow,
    builder: (BuildContext context, Widget? child) {
      // Same slow swell as the status pills. At rest there is no halo; the
      // action keeps its normal pill surface and the emphasis grows outward.
      final double pulse = (1 - cos(_glow.value * 2 * pi)) / 2;
      final double scale = widget.scale;
      return DecoratedBox(
        key: widget.glowKey,
        decoration: BoxDecoration(
          borderRadius: widget.borderRadius,
          boxShadow: widget.enabled
              ? <BoxShadow>[
                  BoxShadow(
                    color: widget.colour.withValues(alpha: .14 * pulse),
                    blurRadius: 8 * pulse * scale,
                    spreadRadius: .4 * pulse * scale,
                  ),
                  BoxShadow(
                    color: widget.colour.withValues(alpha: .22 * pulse),
                    blurRadius: 20 * pulse * scale,
                    spreadRadius: 2 * pulse * scale,
                  ),
                ]
              : const <BoxShadow>[],
        ),
        child: child,
      );
    },
    child: widget.child,
  );
}

Future<void> applyBackupAction(
  BuildContext context,
  BackupAction action,
  List<BackupCard> cards, {
  BackupActionRunner? runAction,
}) async {
  if (cards.isEmpty) return;
  final ProviderContainer container = ProviderScope.containerOf(
    context,
    listen: false,
  );
  final List<List<BackupCard>> targets = action == BackupAction.restore
      ? _restoreTargets(cards)
      : <List<BackupCard>>[
          for (final BackupCard card in cards) <BackupCard>[card],
        ];
  final bool confirmed = await showConfirmDialog(
    title: tr(_title(action)),
    message: tr(
      _message(action, targets.length == 1),
      namedArgs: <String, String>{'count': '${targets.length}'},
    ),
    confirmLabel: tr(_label(action)),
    destructive: backupActionIsDestructive(action),
    details: targets.length == 1
        ? <ConfirmDetail>[
            (
              label: tr(AppI10n.backupActionWallpaper),
              value: targets.first.first.name,
            ),
          ]
        : const <ConfirmDetail>[],
  );
  if (!confirmed) return;

  final CancelFunc close = BotToast.showLoading();
  final List<String> errors = <String>[];
  int completed = 0;
  bool mutated = false;
  try {
    for (final List<BackupCard> target in targets) {
      final BackupActionResult result = runAction != null
          ? await runAction(action, target)
          : await _runOne(container, action, target);
      mutated = mutated || result.changed;
      if (result.error != null) {
        errors.add('${target.first.name}: ${result.error}');
      } else if (result.changed) {
        completed++;
      }
    }
  } finally {
    close();
  }
  if (mutated) {
    container
        .read(backupSelectionProvider.notifier)
        .setExactly(const <String>{});
    container.invalidate(backupScanProvider);
    container.invalidate(backupTilesProvider);
    if (action != BackupAction.showUpdateAgain) {
      container.invalidate(integrityScanProvider);
    }
    if (action == BackupAction.restore &&
        container.read(currentLibraryProvider) == WallpaperLibrary.myProjects) {
      container.read(wallpaperListProvider.notifier).clear();
      container.read(checkedIdsProvider.notifier).clear();
      container.read(selectedWallpaperProvider.notifier).update(null);
      container.read(currentStateProvider.notifier).update(RunState.initial);
    }
    if (completed > 0) {
      showNoticeToast(
        tr(
          AppI10n.backupActionDone,
          namedArgs: <String, String>{'count': '$completed'},
        ),
      );
    }
  }
  if (errors.isNotEmpty) showErrorToast(errors.join('\n'));
}

Future<BackupActionResult> _runOne(
  ProviderContainer container,
  BackupAction action,
  List<BackupCard> cards,
) => switch (action) {
  BackupAction.backUp || BackupAction.update => backUpWallpaper(
    card: cards.single,
    backupRoot: container.read(backupRootProvider),
    liveWorkshopPath: container.read(wallpaperPathProvider),
    liveMyProjectsPath: container.read(myProjectsLibraryProvider),
    acfPath: container.read(acfPathProvider),
    mirror: action == BackupAction.update,
  ),
  BackupAction.restore => restoreVanishedWallpaper(
    cards: cards,
    backupRoot: container.read(backupRootProvider),
    liveMyProjectsPath: container.read(myProjectsLibraryProvider),
  ),
  BackupAction.recycleJunk => recycleBackupJunk(
    card: cards.single,
    backupRoot: container.read(backupRootProvider),
    liveWorkshopPath: container.read(wallpaperPathProvider),
    liveMyProjectsPath: container.read(myProjectsLibraryProvider),
  ),
  BackupAction.showUpdateAgain => showBackupUpdateAgain(
    card: cards.single,
    backupRoot: container.read(backupRootProvider),
  ),
};

List<List<BackupCard>> _restoreTargets(List<BackupCard> cards) {
  final Map<String, List<BackupCard>> grouped = <String, List<BackupCard>>{};
  for (final BackupCard card in cards) {
    grouped
        .putIfAbsent(card.name.toLowerCase(), () => <BackupCard>[])
        .add(card);
  }
  return grouped.values.toList();
}

String _label(BackupAction action) => switch (action) {
  BackupAction.backUp => AppI10n.backupActionBackUp,
  BackupAction.update => AppI10n.backupActionUpdate,
  BackupAction.restore => AppI10n.backupActionRestore,
  BackupAction.recycleJunk => AppI10n.backupActionRecycle,
  BackupAction.showUpdateAgain => AppI10n.backupActionShowAgain,
};

String _title(BackupAction action) => switch (action) {
  BackupAction.backUp => AppI10n.backupActionBackUpTitle,
  BackupAction.update => AppI10n.backupActionUpdateTitle,
  BackupAction.restore => AppI10n.backupActionRestoreTitle,
  BackupAction.recycleJunk => AppI10n.backupActionRecycleTitle,
  BackupAction.showUpdateAgain => AppI10n.backupActionShowAgainTitle,
};

String _message(BackupAction action, bool one) => switch (action) {
  BackupAction.backUp =>
    one ? AppI10n.backupActionBackUpOne : AppI10n.backupActionBackUpMany,
  BackupAction.update =>
    one ? AppI10n.backupActionUpdateOne : AppI10n.backupActionUpdateMany,
  BackupAction.restore =>
    one ? AppI10n.backupActionRestoreOne : AppI10n.backupActionRestoreMany,
  BackupAction.recycleJunk =>
    one ? AppI10n.backupActionRecycleOne : AppI10n.backupActionRecycleMany,
  BackupAction.showUpdateAgain =>
    one ? AppI10n.backupActionShowAgainOne : AppI10n.backupActionShowAgainMany,
};

bool backupActionIsDestructive(BackupAction action) =>
    action == BackupAction.recycleJunk;

String backupActionLabel(BackupAction action) => tr(_label(action));

IconData backupActionIcon(BackupAction action) => switch (action) {
  BackupAction.backUp => Icons.backup_outlined,
  BackupAction.update => Icons.sync_rounded,
  BackupAction.restore => Icons.restore_rounded,
  BackupAction.recycleJunk => Icons.delete_outline_rounded,
  BackupAction.showUpdateAgain => Icons.visibility_outlined,
};
