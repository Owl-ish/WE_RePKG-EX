import 'dart:io';

import 'package:bot_toast/bot_toast.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:we_repkg/constants/i10n.dart';
import 'package:we_repkg/cores/backup.dart';
import 'package:we_repkg/cores/backup_action.dart';
import 'package:we_repkg/cores/scene_pkg_inspection.dart';
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

bool _deletingMatchedBackups = false;

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

/// Resolves Duplicate Live only after the user chooses the copy to recycle.
Future<bool> deleteDuplicateLiveVersion(
  BuildContext context, {
  required String name,
  required WallpaperLibrary library,
  required String versionLabel,
}) async {
  final ProviderContainer container = ProviderScope.containerOf(
    context,
    listen: false,
  );
  final String? libraryRoot = switch (library) {
    WallpaperLibrary.workshop => container.read(wallpaperPathProvider),
    WallpaperLibrary.myProjects => container.read(myProjectsLibraryProvider),
  };
  if (libraryRoot == null) {
    showErrorToast(tr(AppI10n.backupActionFolderUnavailable));
    return false;
  }
  final String folder = path.join(libraryRoot, name);
  final bool confirmed = await showConfirmDialog(
    title: tr(
      AppI10n.backupActionDeleteLiveVersionTitle,
      namedArgs: <String, String>{'version': versionLabel},
    ),
    message: tr(
      AppI10n.backupActionDeleteLiveVersionMessage,
      namedArgs: <String, String>{'version': versionLabel},
    ),
    confirmLabel: tr(AppI10n.backupActionDeleteLiveVersion),
    details: <ConfirmDetail>[(label: versionLabel, value: folder)],
  );
  if (!confirmed || !context.mounted) return false;

  final CancelFunc close = BotToast.showLoading();
  late final BackupActionResult result;
  try {
    result = await recycleDuplicateLiveCopy(
      name: name,
      removedLibrary: library,
      liveWorkshopPath: container.read(wallpaperPathProvider),
      liveMyProjectsPath: container.read(myProjectsLibraryProvider),
    );
  } catch (error) {
    result = (changed: false, error: '$error');
  } finally {
    close();
  }
  if (result.changed) {
    _completeCachedIssues(
      container,
      resolvedReconcileReasons: <String, Set<BackupReconcileReason>>{
        name: <BackupReconcileReason>{
          BackupReconcileReason.duplicateLiveCopies,
        },
      },
      refreshIntegrity: true,
    );
    if (container.read(currentLibraryProvider) == library) {
      container.read(wallpaperListProvider.notifier).clear();
      container.read(checkedIdsProvider.notifier).clear();
      container.read(selectedWallpaperProvider.notifier).update(null);
      container.read(currentStateProvider.notifier).update(RunState.initial);
    }
  }
  if (result.error case final String error) {
    showErrorToast('${tr(AppI10n.dialogDeleteFailed)} $error');
  } else if (result.changed) {
    showDeleteToast();
  }
  return result.changed;
}

/// Resolves a packed/unpacked backup conflict after the user chooses a copy.
Future<bool> deleteConflictingBackupVersion(
  BuildContext context, {
  required String name,
  required WallpaperLibrary library,
  required BackupCopyFormat format,
  required BackupCopyFormat survivingFormat,
  required String versionLabel,
}) async {
  if (_deletingMatchedBackups) return false;
  final ProviderContainer container = ProviderScope.containerOf(
    context,
    listen: false,
  );
  final String? backupRoot = container.read(backupRootProvider);
  final List<ReconcileEntry> matches = _currentMatchedBackupConflicts(
    container,
  );
  if (!matches.any((entry) => entry.name.toLowerCase() == name.toLowerCase())) {
    return false;
  }
  final String? libraryRoot = switch (library) {
    WallpaperLibrary.workshop => backupWorkshopPath(backupRoot),
    WallpaperLibrary.myProjects => backupMyProjectsPath(backupRoot),
  };
  if (libraryRoot == null) {
    showErrorToast(tr(AppI10n.backupActionFolderUnavailable));
    return false;
  }
  final String folder = path.join(libraryRoot, name);
  final bool confirmed = await showConfirmDialog(
    title: tr(
      AppI10n.backupActionDeleteBackupVersionTitle,
      namedArgs: <String, String>{'version': versionLabel},
    ),
    message: tr(
      AppI10n.backupActionDeleteBackupVersionMessage,
      namedArgs: <String, String>{'version': versionLabel},
    ),
    confirmLabel: tr(AppI10n.backupActionDeleteBackupVersion),
    details: <ConfirmDetail>[(label: versionLabel, value: folder)],
  );
  if (!confirmed || !context.mounted) return false;
  if (!_currentMatchedBackupConflicts(
    container,
  ).any((entry) => entry.name.toLowerCase() == name.toLowerCase())) {
    showErrorToast(tr(AppI10n.backupActionStateChanged));
    return false;
  }

  _deletingMatchedBackups = true;
  final CancelFunc close = BotToast.showLoading();
  late final BackupActionResult result;
  try {
    result = await recycleConflictingBackupCopy(
      name: name,
      removedLibrary: library,
      expectedRemovedFormat: format,
      expectedSurvivingFormat: survivingFormat,
      backupRoot: backupRoot,
      verifyEquivalent: _directPairEquivalent,
    );
  } catch (error) {
    result = (changed: false, error: '$error');
  } finally {
    close();
    _deletingMatchedBackups = false;
  }
  if (result.changed) {
    _completeCachedIssues(
      container,
      resolvedReconcileReasons: <String, Set<BackupReconcileReason>>{
        name: <BackupReconcileReason>{
          BackupReconcileReason.conflictingBackupCopies,
        },
      },
      refreshIntegrity: true,
    );
  }
  if (result.error case final String error) {
    showErrorToast('${tr(AppI10n.dialogDeleteFailed)} $error');
  } else if (result.changed) {
    showDeleteToast();
  }
  return result.changed;
}

/// Removes one representation from every verified-identical packed/unpacked pair.
Future<bool> deleteEquivalentBackupCopies(
  BuildContext context, {
  required BackupCopyFormat removedFormat,
}) async {
  if (_deletingMatchedBackups || removedFormat == BackupCopyFormat.unknown) {
    return false;
  }
  final ProviderContainer container = ProviderScope.containerOf(
    context,
    listen: false,
  );
  final String? backupRoot = container.read(backupRootProvider);
  if (backupRoot == null) {
    showErrorToast(tr(AppI10n.backupActionFolderUnavailable));
    return false;
  }
  final AsyncValue<BackupScan> scanValue = container.read(backupScanProvider);
  if (scanValue is! AsyncData<BackupScan>) return false;
  final BackupScan scan = scanValue.value;
  final List<ReconcileEntry> entries = _currentMatchedBackupConflicts(
    container,
  );
  if (entries.isEmpty) return false;
  _deletingMatchedBackups = true;
  try {
    final String versionLabel = tr(
      removedFormat == BackupCopyFormat.packed
          ? AppI10n.backupDetailPackedBackup
          : AppI10n.backupDetailUnpackedBackup,
    );
    final bool confirmed = await showConfirmDialog(
      title: tr(
        AppI10n.backupActionDeleteBackupVersionsTitle,
        namedArgs: <String, String>{'version': versionLabel},
      ),
      message: tr(
        AppI10n.backupActionDeleteBackupVersionsMessage,
        namedArgs: <String, String>{
          'version': versionLabel,
          'count': '${entries.length}',
        },
      ),
      confirmLabel: tr(AppI10n.backupActionDeleteBackupVersion),
      destructive: true,
    );
    if (!confirmed || !context.mounted) return false;
    final List<ReconcileEntry> stillMatched = _currentMatchedBackupConflicts(
      container,
    );
    if (!_sameBackupScan(container, scan, backupRoot) ||
        stillMatched.length != entries.length ||
        !stillMatched.every(
          (entry) => entries.any(
            (original) =>
                original.name.toLowerCase() == entry.name.toLowerCase(),
          ),
        )) {
      showErrorToast(tr(AppI10n.backupActionStateChanged));
      return false;
    }

    final CancelFunc close = BotToast.showLoading();
    final List<String> errors = <String>[];
    final Set<String> completed = <String>{};
    try {
      for (final ReconcileEntry entry in entries) {
        if (!_sameBackupScan(container, scan, backupRoot) ||
            !_currentMatchedBackupConflicts(container).any(
              (current) =>
                  current.name.toLowerCase() == entry.name.toLowerCase(),
            )) {
          errors.add('${entry.name}: ${tr(AppI10n.backupActionStateChanged)}');
          break;
        }
        final BackupCopyDifference? difference = entry.backupDifference;
        if (difference == null) continue;
        final WallpaperLibrary? removedLibrary =
            difference.workshopFormat == removedFormat
            ? WallpaperLibrary.workshop
            : difference.myProjectsFormat == removedFormat
            ? WallpaperLibrary.myProjects
            : null;
        if (removedLibrary == null) continue;
        final BackupCopyFormat survivingFormat =
            removedLibrary == WallpaperLibrary.workshop
            ? difference.myProjectsFormat
            : difference.workshopFormat;
        final BackupActionResult result = await recycleConflictingBackupCopy(
          name: entry.name,
          removedLibrary: removedLibrary,
          expectedRemovedFormat: removedFormat,
          expectedSurvivingFormat: survivingFormat,
          backupRoot: backupRoot,
          verifyEquivalent: _directPairEquivalent,
        );
        if (result.changed) completed.add(entry.name);
        if (result.error case final String error) {
          errors.add('${entry.name}: $error');
        }
      }
    } finally {
      close();
    }
    if (completed.isNotEmpty) {
      if (_sameBackupScan(container, scan, backupRoot)) {
        _completeCachedIssues(
          container,
          resolvedReconcileReasons: <String, Set<BackupReconcileReason>>{
            for (final String name in completed)
              name: <BackupReconcileReason>{
                BackupReconcileReason.conflictingBackupCopies,
              },
          },
          refreshIntegrity: true,
        );
      }
      showNoticeToast(
        tr(
          AppI10n.backupActionDone,
          namedArgs: <String, String>{'count': '${completed.length}'},
        ),
      );
    }
    if (errors.isNotEmpty) showErrorToast(errors.join('\n'));
    return completed.isNotEmpty;
  } finally {
    _deletingMatchedBackups = false;
  }
}

List<ReconcileEntry> _currentMatchedBackupConflicts(
  ProviderContainer container,
) {
  final String? backupRoot = container.read(backupRootProvider);
  if (container.read(backupScanProvider) case AsyncData<BackupScan>(
    :final BackupScan value,
  )) {
    return container
        .read(backupDirectBatchProvider)
        .matchedEntries(
          scan: value,
          backupRoot: backupRoot,
          entries: visibleBackupReconcileEntries(
            value,
            container.read(backupResolvedIssuesProvider),
          ),
        );
  }
  return const <ReconcileEntry>[];
}

Future<bool> _directPairEquivalent(
  Directory packed,
  Directory unpacked,
) async =>
    (await probePackedBackupCopyDirect(
      packedFolder: packed,
      unpackedFolder: unpacked,
    )).status ==
    DirectBackupProbeStatus.candidateMatch;

bool _sameBackupScan(
  ProviderContainer container,
  BackupScan scan,
  String backupRoot,
) {
  final AsyncValue<BackupScan> current = container.read(backupScanProvider);
  return container.read(backupRootProvider) == backupRoot &&
      current is AsyncData<BackupScan> &&
      identical(current.value, scan);
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
