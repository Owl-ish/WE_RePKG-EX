import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:we_repkg/constants/i10n.dart';
import 'package:we_repkg/cores/base.dart';
import 'package:we_repkg/models/enums.dart';
import 'package:we_repkg/provider/setting.dart';
import 'package:we_repkg/provider/system.dart';
import 'package:we_repkg/utils/memory_advice.dart';
import 'package:we_repkg/utils/system_memory.dart';
import 'package:we_repkg/views/setting/setting_path_input.dart';
import 'package:we_repkg/views/setting/setting_slider.dart';
import 'package:we_repkg/widgets/setting_checkbox.dart';
import 'package:we_repkg/widgets/setting_label.dart';

class SettingConfigGroup extends ConsumerStatefulWidget {
  const SettingConfigGroup({super.key});

  @override
  ConsumerState<SettingConfigGroup> createState() => _SettingConfigGroupState();
}

class _SettingConfigGroupState extends ConsumerState<SettingConfigGroup> {
  /// Read when this state is created, so at least once per opening of the
  /// settings card and again if the card crosses the width where its groups
  /// re-lay out. Held rather than read in build, so the figure under the slider
  /// stays put while the slider above it is being dragged.
  final int? _availableBytes = availableMemoryBytes();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingLabel(tr(AppI10n.settingConfigLabel)),
        SettingCheckbox.text(
          label: tr(AppI10n.settingConfigMaximizeOpen),
          value: ref.watch(maximizeOpenProvider),
          onChanged: (value) =>
              ref.read(maximizeOpenProvider.notifier).update(value!),
        ),
        SettingCheckbox.text(
          label: tr(AppI10n.settingConfigOnlySaveImage),
          value: ref.watch(onlySaveImageProvider),
          onChanged: (value) =>
              ref.read(onlySaveImageProvider.notifier).update(value!),
        ),
        SettingCheckbox.text(
          label: tr(AppI10n.settingConfigNoTexture),
          value: ref.watch(excludeTextureProvider),
          onChanged: (value) =>
              ref.read(excludeTextureProvider.notifier).update(value!),
        ),
        SettingCheckbox.text(
          label: tr(AppI10n.settingConfigOriginalProjectName),
          value: ref.watch(useTitleNameProvider),
          onChanged: (value) =>
              ref.read(useTitleNameProvider.notifier).update(value!),
        ),
        SettingCheckbox.twoLine(
          value: ref.watch(deleteTransparencyProvider),
          onChanged: (value) =>
              ref.read(deleteTransparencyProvider.notifier).update(value!),
          label: tr(AppI10n.settingConfigDeleteTransparency),
          subTitle: tr(AppI10n.settingConfigDeleteTransparencyTip),
        ),
        SettingCheckbox.twoLine(
          value: ref.watch(replaceFileProvider),
          onChanged: (value) =>
              ref.read(replaceFileProvider.notifier).update(value!),
          label: tr(AppI10n.settingConfigReplaceExistFile),
          subTitle: tr(AppI10n.settingConfigReplaceExistFileTip),
        ),
        SettingCheckbox.twoLine(
          value: ref.watch(useAcfInfoProvider),
          onChanged: (value) {
            ref.read(useAcfInfoProvider.notifier).update(value!);
            if (!value && ref.read(wallpaperSortTypeProvider).isUpdate) {
              ref
                  .read(wallpaperSortTypeProvider.notifier)
                  .update(SortType.time);
            }
            refreshWallpaperPath(ref);
          },
          label: tr(AppI10n.settingConfigGetAcfInfo),
          subTitle: tr(AppI10n.settingConfigGetAcfInfoTip),
        ),
        SettingCheckbox.twoLine(
          value: ref.watch(useProjectPathProvider),
          onChanged: (value) =>
              ref.read(useProjectPathProvider.notifier).update(value!),
          label: tr(AppI10n.settingConfigUseProjectFolder),
          subTitle: tr(AppI10n.settingConfigUseProjectFolderTip),
        ),
        SettingCheckbox.twoLine(
          value: ref.watch(updateProjectPathProvider),
          onChanged: (value) =>
              ref.read(updateProjectPathProvider.notifier).update(value!),
          label: tr(AppI10n.settingConfigAutoUpdateProjectPath),
          subTitle: tr(AppI10n.settingConfigAutoUpdateProjectPathTip),
        ),
        SettingCheckbox.twoLine(
          value: ref.watch(updateAcfPathProvider),
          onChanged: (value) =>
              ref.read(updateAcfPathProvider.notifier).update(value!),
          label: tr(AppI10n.settingConfigAutoUpdateAcfPath),
          subTitle: tr(AppI10n.settingConfigAutoUpdateAcfPathTip),
        ),
        // RePKG is partly disk-bound, so on a spinning disk a high value makes
        // a batch slower, while fast NVMe benefits from more.
        SettingSlider(
          label: tr(AppI10n.settingConfigConcurrency),
          tip: tr(AppI10n.settingConfigConcurrencyTip),
          value: ref.watch(extractConcurrencyProvider),
          min: ExtractConcurrency.min,
          max: ExtractConcurrency.max,
          onChanged: (v) =>
              ref.read(extractConcurrencyProvider.notifier).update(v),
        ),
        // A ceiling rather than a prediction: nothing can say in advance what a
        // wallpaper costs, since that follows the size of its largest texture.
        // Setting this low only makes extraction slower.
        _memorySlider(),
        SizedBox(height: 8),
        SettingPathInput(
          label: tr(AppI10n.settingConfigWallpapersPath),
          path: ref.watch(wallpaperPathProvider),
          hintText: tr(AppI10n.settingConfigWallpapersPathTip),
          onPick: () => setWallpaperPath(ref),
          onRefresh: () => refreshWallpaperPath(ref),
        ),
        SizedBox(height: 4),
        SettingPathInput(
          label: tr(AppI10n.settingConfigProjectPath),
          path: ref.watch(projectPathProvider),
          hintText: tr(AppI10n.settingConfigProjectPathTip),
          onPick: () => setProjectPath(ref),
          onRefresh: () => refreshProjectPath(ref),
        ),
      ],
    );
  }

  Widget _memorySlider() {
    final int setting = ref.watch(extractMemoryLimitProvider);
    final advice = memoryAdvice(
      settingMb: setting,
      availableBytes: _availableBytes,
    );
    final String? free = advice.freeMb == null
        ? null
        : formatGb(advice.freeMb!);

    return SettingSlider(
      label: tr(AppI10n.settingConfigMemoryLimit),
      tip: tr(AppI10n.settingConfigMemoryLimitTip),
      value: setting,
      min: ExtractMemoryLimit.min,
      max: ExtractMemoryLimit.max,
      step: ExtractMemoryLimit.step,
      unit: ' MB',
      notice: free == null
          ? null
          : tr(
              advice.exceedsFree
                  ? AppI10n.settingConfigMemoryOverFree
                  : AppI10n.settingConfigMemoryFree,
              namedArgs: {'free': free},
            ),
      noticeIsWarning: advice.exceedsFree,
      onChanged: (v) => ref.read(extractMemoryLimitProvider.notifier).update(v),
    );
  }
}
