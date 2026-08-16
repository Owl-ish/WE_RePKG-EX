import 'dart:async';

import 'package:bot_toast/bot_toast.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:we_repkg/config/theme_extensions.dart';
import 'package:we_repkg/constants/i10n.dart';
import 'package:we_repkg/constants/nums.dart';
import 'package:we_repkg/constants/wallpaper_files.dart';
import 'package:we_repkg/cores/backup.dart';
import 'package:we_repkg/cores/integrity_repair.dart';
import 'package:we_repkg/cores/integrity_scan.dart';
import 'package:we_repkg/cores/toast.dart';
import 'package:we_repkg/models/enums.dart';
import 'package:we_repkg/provider/backup.dart';
import 'package:we_repkg/provider/integrity.dart';
import 'package:we_repkg/provider/system.dart';
import 'package:we_repkg/provider/wallpaper.dart';
import 'package:we_repkg/utils/backup_diff.dart';
import 'package:we_repkg/widgets/app_dialog_surface.dart';
import 'package:we_repkg/widgets/confirm_dialog.dart';

enum IntegrityRepair {
  restorePayload,
  replaceProject,
  rescue,
  writeProject,
  resolveMedia,
  recycleShaderCache,
}

enum MediaRepairChoice { createProject, recycle }

typedef IntegrityRepairRunner =
    Future<IntegrityRepairResult> Function(
      IntegrityRepair repair,
      IntegrityFinding target,
    );

Future<void> applyIntegrityRepair(
  BuildContext context,
  IntegrityRepair repair,
  List<IntegrityFinding> targets, {
  IntegrityRepairRunner? runRepair,
}) async {
  if (targets.isEmpty) return;
  final ProviderContainer container = ProviderScope.containerOf(
    context,
    listen: false,
  );
  final String? myProjects = container.read(myProjectsLibraryProvider);
  final String? workshop = container.read(wallpaperPathProvider);
  final String? backupRoot = container.read(backupRootProvider);
  final String? tool = container.read(toolPathProvider);
  if (repair == IntegrityRepair.rescue) {
    if (myProjects == null || myProjects.isEmpty) {
      return showErrorToast(tr(AppI10n.integrityFixNoLibrary));
    }
    if (tool == null || tool.isEmpty) {
      return showErrorToast(tr(AppI10n.integrityFixNoTool));
    }
  }

  final MediaRepairChoice? mediaChoice = repair == IntegrityRepair.resolveMedia
      ? await _showMediaRepairChoice(targets)
      : null;
  if (repair == IntegrityRepair.resolveMedia && mediaChoice == null) return;

  final String title = targets.length == 1
      ? tr(AppI10n.integrityFixTitle)
      : tr(AppI10n.integrityFixTitleMany, args: <String>['${targets.length}']);
  final String message = _confirmationMessage(repair, targets, mediaChoice);
  final String confirmLabel = tr(AppI10n.ok);
  final bool confirmed = await showConfirmDialog(
    title: title,
    message: message,
    confirmLabel: confirmLabel,
    destructive: _isDestructive(repair, mediaChoice),
    details: _confirmationDetails(
      repair,
      targets,
      workshop: workshop,
      myProjects: myProjects,
      backupRoot: backupRoot,
    ),
  );
  if (!confirmed) return;

  final CancelFunc close = BotToast.showLoading();
  final List<String> failed = <String>[];
  final List<IntegrityFinding> changed = <IntegrityFinding>[];
  final List<ResolvedIntegrityIssue> resolved = <ResolvedIntegrityIssue>[];
  try {
    for (final IntegrityFinding target in targets) {
      final IntegrityRepairResult result = runRepair != null
          ? await runRepair(repair, target)
          : await _repairOne(
              repair,
              target,
              counterpart: integrityCounterpartFolder(
                target,
                workshop: workshop,
                myProjects: myProjects,
                backupRoot: backupRoot,
              ),
              library: myProjects,
              tool: tool,
              mediaChoice: mediaChoice,
            );
      if (result.changed) changed.add(target);
      if (result.error case final String error) {
        failed.add(
          tr(
            AppI10n.integrityFixFailed,
            namedArgs: <String, String>{'name': target.name, 'error': error},
          ),
        );
      } else if (result.changed) {
        resolved.add((
          finding: target,
          resolution: _resolutionFor(repair, mediaChoice),
        ));
      }
    }
  } finally {
    close();
  }

  if (resolved.isNotEmpty) {
    container.read(integrityResolvedProvider.notifier).addAll(resolved);
  }
  markExtractGridStaleAfterIntegrityRepair(container, repair, changed);
  container.invalidate(backupScanProvider);
  container.invalidate(integrityScanProvider);

  final int done = targets.length - failed.length;
  if (done > 0) {
    showNoticeToast(tr(AppI10n.integrityFixDone, args: <String>['$done']));
  }
  if (failed.isNotEmpty) {
    showErrorToast(
      failed.length == 1
          ? failed.single
          : '${failed.length}\n${failed.join('\n')}',
    );
  }
}

IntegrityResolution _resolutionFor(
  IntegrityRepair repair,
  MediaRepairChoice? mediaChoice,
) => switch (repair) {
  IntegrityRepair.restorePayload => IntegrityResolution.restoredFile,
  IntegrityRepair.replaceProject => IntegrityResolution.replacedProject,
  IntegrityRepair.rescue => IntegrityResolution.extractedProject,
  IntegrityRepair.writeProject => IntegrityResolution.createdProject,
  IntegrityRepair.resolveMedia =>
    mediaChoice == MediaRepairChoice.createProject
        ? IntegrityResolution.createdProject
        : IntegrityResolution.recycled,
  IntegrityRepair.recycleShaderCache => IntegrityResolution.recycled,
};

bool integrityRepairIsDestructive(IntegrityRepair repair) =>
    repair == IntegrityRepair.rescue ||
    repair == IntegrityRepair.recycleShaderCache;

bool _isDestructive(IntegrityRepair repair, MediaRepairChoice? mediaChoice) =>
    integrityRepairIsDestructive(repair) ||
    (repair == IntegrityRepair.resolveMedia &&
        mediaChoice == MediaRepairChoice.recycle);

Future<IntegrityRepairResult> _repairOne(
  IntegrityRepair repair,
  IntegrityFinding target, {
  String? counterpart,
  String? library,
  String? tool,
  MediaRepairChoice? mediaChoice,
}) => switch (repair) {
  IntegrityRepair.restorePayload => restoreMissingPayload(
    folder: target.folder,
    counterpart: counterpart,
    missing: target.missing,
  ),
  IntegrityRepair.replaceProject => replaceProjectFromCounterpart(
    folder: target.folder,
    counterpart: counterpart,
  ),
  IntegrityRepair.rescue => rescuePackedScene(
    folder: target.folder,
    intoLibrary: library!,
    rePKGPath: tool!,
  ),
  IntegrityRepair.writeProject => _writeSceneProject(target.folder),
  IntegrityRepair.resolveMedia =>
    mediaChoice == MediaRepairChoice.createProject
        ? writeMediaProject(target.folder)
        : recycleMediaFolder(folder: target.folder),
  IntegrityRepair.recycleShaderCache => recycleShaderCacheFolder(
    folder: target.folder,
  ),
};

Future<IntegrityRepairResult> _writeSceneProject(String folder) async {
  final String? error = await writeSceneProject(folder);
  return (changed: error == null, error: error);
}

void markExtractGridStaleAfterIntegrityRepair(
  ProviderContainer container,
  IntegrityRepair repair,
  Iterable<IntegrityFinding> changed,
) {
  final WallpaperLibrary shown = container.read(currentLibraryProvider);
  if (!changed.any(
    (IntegrityFinding finding) => _changesLibrary(repair, finding.root, shown),
  )) {
    return;
  }
  container.read(wallpaperListProvider.notifier).clear();
  container.read(checkedIdsProvider.notifier).clear();
  container.read(selectedWallpaperProvider.notifier).update(null);
  container.read(currentStateProvider.notifier).update(RunState.initial);
}

bool _changesLibrary(
  IntegrityRepair repair,
  IntegrityRoot root,
  WallpaperLibrary library,
) => switch (repair) {
  IntegrityRepair.rescue =>
    library == WallpaperLibrary.myProjects ||
        (library == WallpaperLibrary.workshop &&
            root == IntegrityRoot.liveWorkshop),
  IntegrityRepair.restorePayload ||
  IntegrityRepair.replaceProject ||
  IntegrityRepair.writeProject ||
  IntegrityRepair.resolveMedia ||
  IntegrityRepair.recycleShaderCache => switch (root) {
    IntegrityRoot.liveWorkshop => library == WallpaperLibrary.workshop,
    IntegrityRoot.liveMyProjects => library == WallpaperLibrary.myProjects,
    IntegrityRoot.backupWorkshop || IntegrityRoot.backupMyProjects => false,
  },
};

String _confirmationMessage(
  IntegrityRepair repair,
  List<IntegrityFinding> targets,
  MediaRepairChoice? mediaChoice,
) {
  final bool one = targets.length == 1;
  return switch (repair) {
    IntegrityRepair.restorePayload => _folderOrCountMessage(
      targets,
      AppI10n.integrityFixRestoreOne,
      AppI10n.integrityFixRestoreMany,
    ),
    IntegrityRepair.replaceProject => _folderOrCountMessage(
      targets,
      AppI10n.integrityFixReplaceOne,
      AppI10n.integrityFixReplaceMany,
    ),
    IntegrityRepair.rescue when one => tr(
      AppI10n.integrityFixRescueOne,
      namedArgs: <String, String>{'name': targets.single.name},
    ),
    IntegrityRepair.rescue => tr(
      AppI10n.integrityFixRescueMany,
      namedArgs: <String, String>{'count': '${targets.length}'},
    ),
    IntegrityRepair.writeProject when one => tr(
      AppI10n.integrityFixWriteOne,
      namedArgs: <String, String>{'name': targets.single.name},
    ),
    IntegrityRepair.writeProject => tr(
      AppI10n.integrityFixWriteMany,
      namedArgs: <String, String>{'count': '${targets.length}'},
    ),
    IntegrityRepair.resolveMedia
        when mediaChoice == MediaRepairChoice.createProject =>
      _folderOrCountMessage(
        targets,
        AppI10n.integrityFixMediaCreateOne,
        AppI10n.integrityFixMediaCreateMany,
      ),
    IntegrityRepair.resolveMedia => _folderOrCountMessage(
      targets,
      AppI10n.integrityFixMediaRecycleOne,
      AppI10n.integrityFixMediaRecycleMany,
    ),
    IntegrityRepair.recycleShaderCache => _folderOrCountMessage(
      targets,
      AppI10n.integrityFixCacheOne,
      AppI10n.integrityFixCacheMany,
    ),
  };
}

String _folderOrCountMessage(
  List<IntegrityFinding> targets,
  String oneKey,
  String manyKey,
) => targets.length == 1
    ? tr(oneKey)
    : tr(manyKey, namedArgs: <String, String>{'count': '${targets.length}'});

List<ConfirmDetail> _confirmationDetails(
  IntegrityRepair repair,
  List<IntegrityFinding> targets, {
  required String? workshop,
  required String? myProjects,
  required String? backupRoot,
}) {
  if (targets.length != 1) {
    return <ConfirmDetail>[
      if (repair == IntegrityRepair.rescue && myProjects != null)
        (
          label: tr(AppI10n.integrityFixToLabel),
          value: _rootDisplayName(IntegrityRoot.liveMyProjects),
        ),
    ];
  }
  final IntegrityFinding target = targets.single;
  final String? counterpart = integrityCounterpartFolder(
    target,
    workshop: workshop,
    myProjects: myProjects,
    backupRoot: backupRoot,
  );
  final String targetDisplay = _displayFolder(target.root, target.name);
  final String? counterpartDisplay = counterpart == null
      ? null
      : _displayFolder(_pairedRoot(target.root), target.name);
  return switch (repair) {
    IntegrityRepair.restorePayload => <ConfirmDetail>[
      if (target.missing case final String missing) ...<ConfirmDetail>[
        (label: tr(AppI10n.integrityFixMissingFileLabel), value: missing),
        if (counterpart != null && counterpartDisplay != null)
          (
            label: tr(AppI10n.integrityFixFromLabel),
            value: path.join(counterpartDisplay, missing),
          ),
        (
          label: tr(AppI10n.integrityFixToLabel),
          value: path.join(targetDisplay, missing),
        ),
      ],
    ],
    IntegrityRepair.replaceProject => <ConfirmDetail>[
      if (counterpart != null && counterpartDisplay != null)
        (
          label: tr(AppI10n.integrityFixFromLabel),
          value: path.join(counterpartDisplay, WallpaperFiles.project),
        ),
      (
        label: tr(AppI10n.integrityFixToLabel),
        value: path.join(targetDisplay, WallpaperFiles.project),
      ),
    ],
    IntegrityRepair.rescue => <ConfirmDetail>[
      (label: tr(AppI10n.integrityFixFromLabel), value: targetDisplay),
      if (myProjects != null)
        (
          label: tr(AppI10n.integrityFixToLabel),
          value: _rootDisplayName(IntegrityRoot.liveMyProjects),
        ),
    ],
    IntegrityRepair.writeProject ||
    IntegrityRepair.resolveMedia ||
    IntegrityRepair.recycleShaderCache => <ConfirmDetail>[
      (label: tr(AppI10n.integrityFixFolderLabel), value: targetDisplay),
    ],
  };
}

IntegrityRoot _pairedRoot(IntegrityRoot root) => switch (root) {
  IntegrityRoot.liveWorkshop => IntegrityRoot.backupWorkshop,
  IntegrityRoot.liveMyProjects => IntegrityRoot.backupMyProjects,
  IntegrityRoot.backupWorkshop => IntegrityRoot.liveWorkshop,
  IntegrityRoot.backupMyProjects => IntegrityRoot.liveMyProjects,
};

String _displayFolder(IntegrityRoot root, String name) =>
    path.join(_rootDisplayName(root), name);

String _rootDisplayName(IntegrityRoot root) => switch (root) {
  IntegrityRoot.liveWorkshop => tr(AppI10n.homeLibraryWorkshop),
  IntegrityRoot.liveMyProjects => tr(AppI10n.homeLibraryMyProjects),
  IntegrityRoot.backupWorkshop => path.join(
    tr(AppI10n.navBackup),
    tr(AppI10n.homeLibraryWorkshop),
  ),
  IntegrityRoot.backupMyProjects => path.join(
    tr(AppI10n.navBackup),
    tr(AppI10n.homeLibraryMyProjects),
  ),
};

String? integrityCounterpartFolder(
  IntegrityFinding target, {
  required String? workshop,
  required String? myProjects,
  required String? backupRoot,
}) {
  final String? pairedRoot = switch (target.root) {
    IntegrityRoot.liveWorkshop => backupWorkshopPath(backupRoot),
    IntegrityRoot.liveMyProjects => backupMyProjectsPath(backupRoot),
    IntegrityRoot.backupWorkshop => workshop,
    IntegrityRoot.backupMyProjects => myProjects,
  };
  return pairedRoot == null ? null : path.join(pairedRoot, target.name);
}

Future<MediaRepairChoice?> _showMediaRepairChoice(
  List<IntegrityFinding> targets,
) {
  final Completer<MediaRepairChoice?> completer =
      Completer<MediaRepairChoice?>();
  late final CancelFunc close;
  void finish(MediaRepairChoice? choice) {
    if (completer.isCompleted) return;
    completer.complete(choice);
    close();
  }

  close = BotToast.showCustomLoading(
    backgroundColor: Colors.black.withValues(alpha: .6),
    clickClose: true,
    onClose: () => finish(null),
    toastBuilder: (_) =>
        _MediaRepairDialog(count: targets.length, onResult: finish),
  );
  return completer.future;
}

class _MediaRepairDialog extends StatelessWidget {
  const _MediaRepairDialog({required this.count, required this.onResult});

  final int count;
  final void Function(MediaRepairChoice? choice) onResult;

  static const double _width = 600;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ActionButtonTheme actions = theme.actionButtons;
    return AppDialogSurface(
      width: _width,
      padding: const EdgeInsets.all(LayoutNums.edgeInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          AppDialogHeader(
            icon: Icons.auto_fix_high_rounded,
            title: tr(AppI10n.integrityFixMediaChoiceTitle),
            foreground: actions.primaryForeground,
            background: actions.primaryBackground,
          ),
          const SizedBox(height: LayoutNums.largeGap),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(LayoutNums.largeGap),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: .55,
              ),
              border: Border.all(
                color: theme.dividerColor.withValues(alpha: .35),
              ),
              borderRadius: BorderRadius.circular(LayoutNums.surfaceRadius),
            ),
            child: Text(
              tr(
                count == 1
                    ? AppI10n.integrityFixMediaChoiceOne
                    : AppI10n.integrityFixMediaChoiceMany,
                namedArgs: <String, String>{'count': '$count'},
              ),
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
            ),
          ),
          const SizedBox(height: LayoutNums.sectionGap),
          SizedBox(
            width: double.infinity,
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: LayoutNums.smallGap,
              runSpacing: LayoutNums.smallGap,
              children: <Widget>[
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, LayoutNums.controlHeight),
                  ),
                  onPressed: () => onResult(MediaRepairChoice.createProject),
                  icon: const Icon(Icons.add_circle_outline_rounded, size: 18),
                  label: Text(tr(AppI10n.integrityFixMediaCreate)),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, LayoutNums.controlHeight),
                    backgroundColor: actions.destructiveBackground,
                    foregroundColor: actions.destructiveForeground,
                    side: BorderSide(color: actions.destructiveBorder),
                  ),
                  onPressed: () => onResult(MediaRepairChoice.recycle),
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: Text(tr(AppI10n.integrityFixMediaRecycle)),
                ),
              ],
            ),
          ),
          const SizedBox(height: LayoutNums.sectionGap),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: <Widget>[
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(88, LayoutNums.controlHeight),
                ),
                onPressed: () => onResult(null),
                child: Text(tr(AppI10n.cancel)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
