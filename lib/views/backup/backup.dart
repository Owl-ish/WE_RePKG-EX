import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:we_repkg/constants/i10n.dart';
import 'package:we_repkg/cores/base.dart';
import 'package:we_repkg/provider/system.dart';
import 'package:we_repkg/widgets/folder_input.dart';

/// The backup area. Until the grid lands this is the empty state, which repeats
/// the settings card's picker so the feature is reachable without knowing to
/// look there.
class BackupView extends ConsumerWidget {
  const BackupView({super.key});

  static const double _pickerWidth = 460;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String? root = ref.watch(backupRootProvider);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        spacing: 16,
        children: [
          Icon(Icons.backup_outlined, size: 48, color: Colors.grey),
          Text(
            tr(root == null ? AppI10n.backupNoRoot : AppI10n.backupComingSoon),
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
              text: root,
              hintText: tr(AppI10n.settingBackupRootTip),
              onPressed: () => setBackupRoot(ref),
            ),
          ),
        ],
      ),
    );
  }
}
