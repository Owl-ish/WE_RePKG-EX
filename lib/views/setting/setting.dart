import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:we_repkg/constants/i10n.dart';
import 'package:we_repkg/constants/nums.dart';
import 'package:we_repkg/views/setting/setting_about_group.dart';
import 'package:we_repkg/views/setting/setting_config_group.dart';
import 'package:we_repkg/views/setting/setting_system_group.dart';

/// Settings as one of the nav rail's areas.
///
/// Used to be a dialog opened from a gear in the title bar. The groups
/// themselves didn't change; only the frame around them did.
class SettingView extends StatelessWidget {
  const SettingView({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            LayoutNums.edgeInset,
            12,
            LayoutNums.edgeInset,
            4,
          ),
          child: Text(
            tr(AppI10n.settingTitle),
            style: theme.textTheme.titleLarge?.copyWith(fontSize: 20),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              LayoutNums.edgeInset,
              0,
              LayoutNums.edgeInset,
              LayoutNums.contentGap,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SettingConfigGroup(),
                SettingSystemGroup(),
                SettingAboutGroup(),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
