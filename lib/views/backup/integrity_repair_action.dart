import 'package:bot_toast/bot_toast.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:we_repkg/constants/i10n.dart';
import 'package:we_repkg/cores/integrity_repair.dart';
import 'package:we_repkg/cores/integrity_scan.dart';
import 'package:we_repkg/cores/toast.dart';
import 'package:we_repkg/models/enums.dart';
import 'package:we_repkg/provider/backup.dart';
import 'package:we_repkg/provider/integrity.dart';
import 'package:we_repkg/provider/system.dart';
import 'package:we_repkg/provider/wallpaper.dart';
import 'package:we_repkg/utils/backup_diff.dart';
import 'package:we_repkg/widgets/confirm_dialog.dart';

enum IntegrityRepair { none, rescue, writeProject }

Future<void> applyIntegrityRepair(
  BuildContext context,
  IntegrityRepair repair,
  List<IntegrityFinding> targets,
) async {
  if (repair == IntegrityRepair.none || targets.isEmpty) return;
  final ProviderContainer container = ProviderScope.containerOf(
    context,
    listen: false,
  );
  final String? library = container.read(myProjectsLibraryProvider);
  final String? tool = container.read(toolPathProvider);
  if (repair == IntegrityRepair.rescue) {
    if (library == null || library.isEmpty) {
      return showErrorToast(tr(AppI10n.integrityFixNoLibrary));
    }
    if (tool == null || tool.isEmpty) {
      return showErrorToast(tr(AppI10n.integrityFixNoTool));
    }
  }
  if (!await showConfirmDialog(
    title: targets.length == 1
        ? tr(AppI10n.integrityFixTitle)
        : tr(
            AppI10n.integrityFixTitleMany,
            args: <String>['${targets.length}'],
          ),
    message: _confirmationMessage(repair, targets, library),
  )) {
    return;
  }

  final CancelFunc close = BotToast.showLoading();
  final List<String> failed = <String>[];
  final List<IntegrityFinding> changed = <IntegrityFinding>[];
  try {
    for (final IntegrityFinding target in targets) {
      final IntegrityRepairResult result = repair == IntegrityRepair.rescue
          ? await rescuePackedScene(
              folder: target.folder,
              intoLibrary: library!,
              rePKGPath: tool!,
            )
          : await _writeProject(target.folder);
      if (result.changed) changed.add(target);
      if (result.error case final String error) {
        failed.add(
          tr(
            AppI10n.integrityFixFailed,
            namedArgs: <String, String>{'name': target.name, 'error': error},
          ),
        );
      }
    }
  } finally {
    close();
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

Future<IntegrityRepairResult> _writeProject(String folder) async {
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
  IntegrityRepair.none => false,
  IntegrityRepair.rescue =>
    library == WallpaperLibrary.myProjects ||
        (library == WallpaperLibrary.workshop &&
            root == IntegrityRoot.liveWorkshop),
  IntegrityRepair.writeProject => switch (root) {
    IntegrityRoot.liveWorkshop => library == WallpaperLibrary.workshop,
    IntegrityRoot.liveMyProjects => library == WallpaperLibrary.myProjects,
    IntegrityRoot.backupWorkshop || IntegrityRoot.backupMyProjects => false,
  },
};

String _confirmationMessage(
  IntegrityRepair repair,
  List<IntegrityFinding> targets,
  String? library,
) {
  final bool one = targets.length == 1;
  return switch (repair) {
    IntegrityRepair.rescue when one => tr(
      AppI10n.integrityFixRescueOne,
      namedArgs: <String, String>{
        'name': targets.single.name,
        'into': library ?? '',
        'from': targets.single.folder,
      },
    ),
    IntegrityRepair.rescue => tr(
      AppI10n.integrityFixRescueMany,
      namedArgs: <String, String>{
        'count': '${targets.length}',
        'into': library ?? '',
      },
    ),
    IntegrityRepair.writeProject when one => tr(
      AppI10n.integrityFixWriteOne,
      namedArgs: <String, String>{
        'name': targets.single.name,
        'from': targets.single.folder,
      },
    ),
    _ => tr(
      AppI10n.integrityFixWriteMany,
      namedArgs: <String, String>{'count': '${targets.length}'},
    ),
  };
}
