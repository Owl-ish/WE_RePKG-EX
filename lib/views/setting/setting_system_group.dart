import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:we_repkg/constants/i10n.dart';
import 'package:we_repkg/models/enums.dart';
import 'package:we_repkg/provider/setting.dart';
import 'package:we_repkg/provider/system.dart';
import 'package:we_repkg/widgets/setting_label.dart';

import 'setting_segmented.dart';

class SettingSystemGroup extends ConsumerWidget {
  const SettingSystemGroup({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingLabel(tr(AppI10n.settingSystemLabel)),
        SettingSegmented<NotificationType>(
          label: tr(AppI10n.settingSystemNotification),
          values: NotificationType.values,
          current: ref.watch(localNotificationTypeProvider),
          labelOf: (type) => type.label,
          onChanged: (type) =>
              ref.read(localNotificationTypeProvider.notifier).update(type),
        ),
        SizedBox(height: 8),
        SettingSegmented<LanguageType>(
          label: tr(AppI10n.settingSystemLanguage),
          values: LanguageType.values,
          current: context.locale == LanguageType.zh.locale
              ? LanguageType.zh
              : LanguageType.en,
          labelOf: (type) => type.label,
          onChanged: (type) => context.setLocale(type.locale),
        ),
        SizedBox(height: 8),
        SettingSegmented<ThemeType>(
          label: tr(AppI10n.settingSystemTheme),
          values: ThemeType.values,
          current: ref.watch(currentThemeProvider),
          labelOf: (type) => type.label,
          onChanged: (type) =>
              ref.read(currentThemeProvider.notifier).update(type),
        ),
      ],
    );
  }
}
