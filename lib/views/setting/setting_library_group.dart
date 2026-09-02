import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:we_repkg/constants/i10n.dart';
import 'package:we_repkg/actions/path_actions.dart';
import 'package:we_repkg/provider/system.dart';
import 'package:we_repkg/views/setting/setting_path_input.dart';
import 'package:we_repkg/widgets/setting_label.dart';

/// The two live libraries. A pair, and apart from the extraction settings,
/// because they say where the wallpapers are rather than what a run does with
/// them.
class SettingLibraryGroup extends ConsumerWidget {
  const SettingLibraryGroup({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingLabel(tr(AppI10n.settingLibraryLabel)),
        SettingPathInput(
          label: tr(AppI10n.settingLibraryWorkshop),
          path: ref.watch(wallpaperPathProvider),
          hintText: tr(AppI10n.settingLibraryWorkshopTip),
          onPick: () => setWallpaperPath(ref),
          onRefresh: () => refreshWallpaperPath(ref),
        ),
        const SizedBox(height: 4),
        SettingPathInput(
          label: tr(AppI10n.settingLibraryMyProjects),
          path: ref.watch(myProjectsLibraryProvider),
          hintText: tr(AppI10n.settingLibraryMyProjectsTip),
          onPick: () => setMyProjectsLibrary(ref),
          onRefresh: () => refreshMyProjectsLibrary(ref),
        ),
      ],
    );
  }
}
