import 'package:bot_toast/bot_toast.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:we_repkg/constants/i10n.dart';
import 'package:we_repkg/cores/backup.dart';
import 'package:we_repkg/cores/backup_action.dart';
import 'package:we_repkg/cores/toast.dart';
import 'package:we_repkg/models/enums.dart';
import 'package:we_repkg/provider/backup.dart';
import 'package:we_repkg/provider/integrity.dart';
import 'package:we_repkg/provider/system.dart';
import 'package:we_repkg/provider/wallpaper.dart';
import 'package:we_repkg/utils/backup_diff.dart';
import 'package:we_repkg/utils/backup_tiles.dart';
import 'package:we_repkg/widgets/confirm_dialog.dart';

typedef BackupActionRunner =
    Future<BackupActionResult> Function(
      BackupAction action,
      List<BackupCard> cards,
    );

Future<bool> applyBackupAction(
  BuildContext context,
  BackupAction action,
  List<BackupCard> cards, {
  BackupActionRunner? runAction,
  BackupSelectiveUpdatePlan? selectiveUpdate,
}) async {
  if (cards.isEmpty) return false;
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
      selectiveUpdate != null
          ? AppI10n.backupActionSelectiveUpdateOne
          : _message(action, targets.length == 1),
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
  if (!confirmed) return false;

  final CancelFunc close = BotToast.showLoading();
  final List<String> errors = <String>[];
  int completed = 0;
  bool mutated = false;
  final Set<BackupCard> changedCards = <BackupCard>{};
  try {
    for (final List<BackupCard> target in targets) {
      final BackupActionResult result = runAction != null
          ? await runAction(action, target)
          : await _runOne(
              container,
              action,
              target,
              selectiveUpdate: selectiveUpdate,
            );
      mutated = mutated || result.changed;
      if (result.changed) changedCards.addAll(target);
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
    _completeCachedIssues(
      container,
      action: action,
      cards: changedCards,
      refreshIntegrity:
          action != BackupAction.showUpdateAgain &&
          action != BackupAction.ignoreUpdate,
    );
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
  return mutated;
}

Future<BackupActionResult> _runOne(
  ProviderContainer container,
  BackupAction action,
  List<BackupCard> cards, {
  BackupSelectiveUpdatePlan? selectiveUpdate,
}) => switch (action) {
  BackupAction.backUp || BackupAction.update => backUpWallpaper(
    card: cards.single,
    backupRoot: container.read(backupRootProvider),
    liveWorkshopPath: container.read(wallpaperPathProvider),
    liveMyProjectsPath: container.read(myProjectsLibraryProvider),
    acfPath: container.read(acfPathProvider),
    mirror: action == BackupAction.update,
    selectiveUpdate: action == BackupAction.update ? selectiveUpdate : null,
  ),
  BackupAction.sync => syncBackupWallpaper(
    card: cards.single,
    backupRoot: container.read(backupRootProvider),
    liveWorkshopPath: container.read(wallpaperPathProvider),
    liveMyProjectsPath: container.read(myProjectsLibraryProvider),
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
  BackupAction.ignoreUpdate => ignoreBackupUpdate(
    card: cards.single,
    backupRoot: container.read(backupRootProvider),
    liveWorkshopPath: container.read(wallpaperPathProvider),
    liveMyProjectsPath: container.read(myProjectsLibraryProvider),
    acfPath: container.read(acfPathProvider),
  ),
  BackupAction.showUpdateAgain => showBackupUpdateAgain(
    card: cards.single,
    backupRoot: container.read(backupRootProvider),
  ),
};

Future<bool> ignoreReconcileDetections(
  BuildContext context,
  ReconcileEntry entry,
) async {
  final Map<BackupReconcileReason, String> fingerprints =
      <BackupReconcileReason, String>{
        for (final BackupReconcileReason reason in entry.activeReasons)
          if (reconcileReasonCanBeIgnored(reason))
            if (entry.issueFingerprints[reason] case final String fingerprint)
              reason: fingerprint,
      };
  if (fingerprints.isEmpty) return false;
  final bool confirmed = await showConfirmDialog(
    title: tr(AppI10n.backupActionIgnoreReconcileTitle),
    message: tr(AppI10n.backupActionIgnoreReconcileOne),
    confirmLabel: tr(AppI10n.backupActionIgnore),
    details: <ConfirmDetail>[
      (label: tr(AppI10n.backupActionWallpaper), value: entry.name),
    ],
  );
  if (!confirmed || !context.mounted) return false;
  final ProviderContainer container = ProviderScope.containerOf(
    context,
    listen: false,
  );
  final BackupActionResult result = await ignoreReconcileIssues(
    name: entry.name,
    fingerprints: fingerprints,
    backupRoot: container.read(backupRootProvider),
  );
  if (!context.mounted) return false;
  return _finishIgnoredMetadataAction(
    container,
    result,
    completed: fingerprints.length,
    ignoredReconcileReasons: <String, Set<BackupReconcileReason>>{
      entry.name: fingerprints.keys.toSet(),
    },
  );
}

Future<bool> showReconcileDetectionAgain(
  BuildContext context,
  ReconcileEntry entry,
  BackupReconcileReason reason,
) async {
  final bool confirmed = await showConfirmDialog(
    title: tr(AppI10n.backupActionShowAgainTitle),
    message: tr(AppI10n.backupActionShowReconcileAgainOne),
    confirmLabel: tr(AppI10n.backupActionShowAgain),
    details: <ConfirmDetail>[
      (label: tr(AppI10n.backupActionWallpaper), value: entry.name),
    ],
  );
  if (!confirmed || !context.mounted) return false;
  final ProviderContainer container = ProviderScope.containerOf(
    context,
    listen: false,
  );
  final BackupActionResult result = await showReconcileIssuesAgain(
    name: entry.name,
    reasons: <BackupReconcileReason>{reason},
    backupRoot: container.read(backupRootProvider),
  );
  if (!context.mounted) return false;
  return _finishIgnoredMetadataAction(
    container,
    result,
    shownReconcileReasons: <String, Set<BackupReconcileReason>>{
      entry.name: <BackupReconcileReason>{reason},
    },
  );
}

Future<bool> showAllIgnoredDetections(
  BuildContext context, {
  required Set<BackupCard> ignoredUpdates,
  required List<ReconcileEntry> reconcileEntries,
}) async {
  final int count = ignoredDetectionCount(
    updates: ignoredUpdates,
    reconcile: reconcileEntries,
  );
  if (count == 0) return false;
  final bool confirmed = await showConfirmDialog(
    title: tr(AppI10n.backupActionShowAgainTitle),
    message: tr(
      AppI10n.backupActionShowAgainMany,
      namedArgs: <String, String>{'count': '$count'},
    ),
    confirmLabel: tr(AppI10n.backupActionShowAgain),
  );
  if (!confirmed || !context.mounted) return false;
  final ProviderContainer container = ProviderScope.containerOf(
    context,
    listen: false,
  );
  final BackupActionResult result = await showAllIgnoredIssues(
    backupRoot: container.read(backupRootProvider),
    ignoredUpdates: ignoredUpdates,
    reconcileEntries: reconcileEntries,
  );
  if (!context.mounted) return false;
  return _finishIgnoredMetadataAction(
    container,
    result,
    completed: count,
    action: BackupAction.showUpdateAgain,
    cards: ignoredUpdates,
    shownReconcileReasons: <String, Set<BackupReconcileReason>>{
      for (final ReconcileEntry entry in reconcileEntries)
        if (entry.ignoredReasons.isNotEmpty) entry.name: entry.ignoredReasons,
    },
  );
}

bool _finishIgnoredMetadataAction(
  ProviderContainer container,
  BackupActionResult result, {
  int completed = 1,
  BackupAction? action,
  Iterable<BackupCard> cards = const <BackupCard>[],
  Map<String, Set<BackupReconcileReason>> ignoredReconcileReasons =
      const <String, Set<BackupReconcileReason>>{},
  Map<String, Set<BackupReconcileReason>> shownReconcileReasons =
      const <String, Set<BackupReconcileReason>>{},
}) {
  if (result.error case final String error) {
    showErrorToast(error);
    return false;
  }
  if (!result.changed) return false;
  _completeCachedIssues(
    container,
    action: action,
    cards: cards,
    ignoredReconcileReasons: ignoredReconcileReasons,
    shownReconcileReasons: shownReconcileReasons,
  );
  showNoticeToast(
    tr(
      AppI10n.backupActionDone,
      namedArgs: <String, String>{'count': '$completed'},
    ),
  );
  return true;
}

void _completeCachedIssues(
  ProviderContainer container, {
  BackupAction? action,
  Iterable<BackupCard> cards = const <BackupCard>[],
  Map<String, Set<BackupReconcileReason>> resolvedReconcileReasons =
      const <String, Set<BackupReconcileReason>>{},
  Map<String, Set<BackupReconcileReason>> ignoredReconcileReasons =
      const <String, Set<BackupReconcileReason>>{},
  Map<String, Set<BackupReconcileReason>> shownReconcileReasons =
      const <String, Set<BackupReconcileReason>>{},
  bool refreshIntegrity = false,
}) {
  container.read(backupSelectionProvider.notifier).setExactly(const <String>{});
  if (container.read(backupScanProvider) case AsyncData<BackupScan>(
    :final BackupScan value,
  )) {
    final BackupResolvedIssues resolved = container.read(
      backupResolvedIssuesProvider.notifier,
    );
    if (action != null) resolved.completeCards(value, action, cards);
    for (final MapEntry<String, Set<BackupReconcileReason>> entry
        in resolvedReconcileReasons.entries) {
      resolved.resolveReconcile(value, entry.key, entry.value);
    }
    for (final MapEntry<String, Set<BackupReconcileReason>> entry
        in ignoredReconcileReasons.entries) {
      resolved.ignoreReconcile(value, entry.key, entry.value);
    }
    for (final MapEntry<String, Set<BackupReconcileReason>> entry
        in shownReconcileReasons.entries) {
      resolved.showReconcile(value, entry.key, entry.value);
    }
  }
  if (refreshIntegrity) container.invalidate(integrityScanProvider);
}

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
  BackupAction.sync => AppI10n.backupTileSync,
  BackupAction.restore => AppI10n.backupActionRestore,
  BackupAction.recycleJunk => AppI10n.backupActionRecycle,
  BackupAction.ignoreUpdate => AppI10n.backupActionIgnore,
  BackupAction.showUpdateAgain => AppI10n.backupActionShowAgain,
};

String _title(BackupAction action) => switch (action) {
  BackupAction.backUp => AppI10n.backupActionBackUpTitle,
  BackupAction.update => AppI10n.backupActionUpdateTitle,
  BackupAction.sync => AppI10n.backupActionSyncTitle,
  BackupAction.restore => AppI10n.backupActionRestoreTitle,
  BackupAction.recycleJunk => AppI10n.backupActionRecycleTitle,
  BackupAction.ignoreUpdate => AppI10n.backupActionIgnoreUpdateTitle,
  BackupAction.showUpdateAgain => AppI10n.backupActionShowAgainTitle,
};

String _message(BackupAction action, bool one) => switch (action) {
  BackupAction.backUp =>
    one ? AppI10n.backupActionBackUpOne : AppI10n.backupActionBackUpMany,
  BackupAction.update =>
    one ? AppI10n.backupActionUpdateOne : AppI10n.backupActionUpdateMany,
  BackupAction.sync =>
    one ? AppI10n.backupActionSyncOne : AppI10n.backupActionSyncMany,
  BackupAction.restore =>
    one ? AppI10n.backupActionRestoreOne : AppI10n.backupActionRestoreMany,
  BackupAction.recycleJunk =>
    one ? AppI10n.backupActionRecycleOne : AppI10n.backupActionRecycleMany,
  BackupAction.ignoreUpdate =>
    one
        ? AppI10n.backupActionIgnoreUpdateOne
        : AppI10n.backupActionIgnoreUpdateMany,
  BackupAction.showUpdateAgain =>
    one ? AppI10n.backupActionShowAgainOne : AppI10n.backupActionShowAgainMany,
};

bool backupActionIsDestructive(BackupAction action) =>
    action == BackupAction.recycleJunk;

String backupActionLabel(BackupAction action) => tr(_label(action));
