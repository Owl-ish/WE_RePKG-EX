import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:we_repkg/constants/i10n.dart';
import 'package:we_repkg/cores/base.dart';
import 'package:we_repkg/provider/system.dart';
import 'package:we_repkg/views/setting/setting_path_input.dart';
import 'package:we_repkg/widgets/setting_label.dart';

class SettingBackupGroup extends ConsumerWidget {
  const SettingBackupGroup({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingLabel(tr(AppI10n.settingBackupLabel)),
        SettingPathInput(
          label: tr(AppI10n.settingBackupRoot),
          path: ref.watch(backupRootProvider),
          hintText: tr(AppI10n.settingBackupRootTip),
          onPick: () => setBackupRoot(ref),
        ),
      ],
    );
  }
}
