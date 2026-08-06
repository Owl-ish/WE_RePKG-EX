import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:we_repkg/constants/i10n.dart';
import 'package:we_repkg/constants/nums.dart';
import 'package:we_repkg/cores/backup.dart';
import 'package:we_repkg/cores/base.dart';
import 'package:we_repkg/models/enums.dart';
import 'package:we_repkg/provider/backup.dart';
import 'package:we_repkg/provider/navigation.dart';
import 'package:we_repkg/provider/system.dart';
import 'package:we_repkg/utils/backup_diff.dart';
import 'package:we_repkg/views/backup/integrity.dart';
import 'package:we_repkg/widgets/folder_input.dart';
import 'package:we_repkg/widgets/sliding_switch.dart';

/// The backup area: the backup itself, and the integrity check beside it.
class BackupView extends ConsumerWidget {
  const BackupView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final BackupTab tab = ref.watch(currentBackupTabProvider);
    // The section is handed straight into an Expanded, so the inset the top bar
    // and the grid apply for themselves has to be applied here too.
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        LayoutNums.edgeInset,
        LayoutNums.contentGap,
        LayoutNums.edgeInset,
        LayoutNums.contentGap,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(bottom: LayoutNums.contentGap),
            child: SlidingSwitch(
              initialValue: tab.index,
              children: <int, Widget>{
                for (int i = 0; i < BackupTab.values.length; i++)
                  i + 1: Text(BackupTab.values[i].label),
              },
              onValueChanged: (int v) => ref
                  .read(currentBackupTabProvider.notifier)
                  .update(BackupTab.values[v - 1]),
            ),
          ),
          Expanded(
            child: switch (tab) {
              // The integrity check reads the live libraries too, so it is
              // worth opening before a backup root has been chosen.
              BackupTab.integrity => const IntegrityView(),
              BackupTab.backup => const _Backup(),
            },
          ),
        ],
      ),
    );
  }
}

/// Until the grid lands this is a count per state, which is enough to check the
/// comparison against a real library.
class _Backup extends ConsumerWidget {
  const _Backup();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(backupRootProvider) == null) return const _PickRoot();
    return switch (ref.watch(backupScanProvider)) {
      AsyncData<BackupScan>(value: final BackupScan scan)
          when scan.missing.isNotEmpty =>
        _MissingFolders(missing: scan.missing),
      AsyncData<BackupScan>(:final BackupScan value) => _Counts(scan: value),
      AsyncError<BackupScan>(:final Object error) => Center(
        child: Text('${tr(AppI10n.backupScanFailed)} $error'),
      ),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }
}

/// Names the folders the scan could not read, and what each is set to.
///
/// Counts are withheld rather than shown alongside: a missing live library
/// turns every backup folder into a vanished card and a missing backup root
/// empties the vanished list, and either reads as a confident number.
class _MissingFolders extends ConsumerWidget {
  const _MissingFolders({required this.missing});

  final Set<BackupFolder> missing;

  static const Map<BackupFolder, String> _labels = <BackupFolder, String>{
    BackupFolder.liveWorkshop: AppI10n.backupFolderLiveWorkshop,
    BackupFolder.liveMyProjects: AppI10n.backupFolderLiveMyProjects,
    BackupFolder.backupRoot: AppI10n.backupFolderBackupRoot,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Map<BackupFolder, String?> paths = <BackupFolder, String?>{
      BackupFolder.liveWorkshop: ref.watch(wallpaperPathProvider),
      BackupFolder.liveMyProjects: ref.watch(myProjectsLibraryProvider),
      BackupFolder.backupRoot: ref.watch(backupRootProvider),
    };
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        spacing: 12,
        children: [
          const Icon(Icons.folder_off_outlined, size: 48, color: Colors.grey),
          Text(tr(AppI10n.backupMissingFolders)),
          for (final BackupFolder folder in BackupFolder.values)
            if (missing.contains(folder))
              Text(
                '${tr(_labels[folder]!)}  '
                '${paths[folder] ?? tr(AppI10n.backupPathNotSet)}',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
        ],
      ),
    );
  }
}

/// Repeats the settings card's picker, so the feature is reachable without
/// knowing to look there.
class _PickRoot extends ConsumerWidget {
  const _PickRoot();

  static const double _pickerWidth = 460;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        spacing: 16,
        children: [
          Icon(Icons.backup_outlined, size: 48, color: Colors.grey),
          Text(
            tr(AppI10n.backupNoRoot),
            style: const TextStyle(
              fontSize: 16,
              color: Colors.grey,
              fontFamily: 'Microsoft YaHei',
            ),
          ),
          SizedBox(
            width: _pickerWidth,
            child: FolderInput(
              height: 36,
              text: null,
              hintText: tr(AppI10n.settingBackupRootTip),
              onPressed: () => setBackupRoot(ref),
            ),
          ),
        ],
      ),
    );
  }
}

class _Counts extends ConsumerWidget {
  const _Counts({required this.scan});

  final BackupScan scan;

  /// Also the display order, worst first. Vanished is the case the tab exists
  /// for, so it goes at the top.
  static const Map<BackupState, String> _labels = <BackupState, String>{
    BackupState.vanished: AppI10n.backupStateVanished,
    BackupState.updateAvailable: AppI10n.backupStateUpdateAvailable,
    BackupState.notBackedUp: AppI10n.backupStateNotBackedUp,
    BackupState.synced: AppI10n.backupStateSynced,
    BackupState.updateDismissed: AppI10n.backupStateUpdateDismissed,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Map<BackupState, int> counts = countByState(scan.cards.values);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        spacing: 8,
        children: [
          // Without the ACF every backed-up Workshop wallpaper compares as
          // current, so the update count reads zero rather than unknown.
          if (!scan.acfRead)
            SizedBox(
              width: _CountRow._width,
              child: Text(
                tr(AppI10n.backupAcfUnreadable),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          for (final MapEntry<BackupState, String> entry in _labels.entries)
            _CountRow(labelKey: entry.value, count: counts[entry.key]!),
          _CountRow(
            labelKey: AppI10n.backupReconcile,
            count: scan.reconcile.length,
          ),
          TextButton.icon(
            onPressed: () => ref.invalidate(backupScanProvider),
            icon: const Icon(Icons.refresh_rounded),
            label: Text(tr(AppI10n.backupRefresh)),
          ),
        ],
      ),
    );
  }
}

class _CountRow extends StatelessWidget {
  const _CountRow({required this.labelKey, required this.count});

  final String labelKey;
  final int count;

  static const double _width = 280;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _width,
      child: Row(
        children: [
          Expanded(child: Text(tr(labelKey))),
          Text('$count'),
        ],
      ),
    );
  }
}
