import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:we_repkg/constants/i10n.dart';
import 'package:we_repkg/constants/nums.dart';
import 'package:we_repkg/views/setting/setting_about_group.dart';
import 'package:we_repkg/views/setting/setting_config_group.dart';
import 'package:we_repkg/views/setting/setting_system_group.dart';

/// The contents of the settings card. [SettingCard] owns how wide it gets.
class SettingView extends StatelessWidget {
  const SettingView({super.key});

  /// Below this the groups stack; above it they sit side by side.
  ///
  /// Measured against the card's width less its insets, not the window. Too low
  /// and the smallest window gets two columns of about 400px, which the longer
  /// subtitles do not fit; too high and the second column is unreachable at any
  /// size. At the 1060px minimum window the card leaves 821px, and two columns
  /// start at roughly 1327px of window.
  static const double twoColumnWidth = 1040;
  static const double columnGap = 40;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
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
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              LayoutNums.edgeInset,
              0,
              LayoutNums.edgeInset,
              LayoutNums.contentGap,
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < twoColumnWidth) {
                  return const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SettingConfigGroup(),
                      SettingSystemGroup(),
                      SettingAboutGroup(),
                    ],
                  );
                }
                // Split by group, not by height. The extraction settings are
                // one subject and stay together even though it leaves the
                // right column shorter.
                return const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: SettingConfigGroup()),
                    SizedBox(width: columnGap),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [SettingSystemGroup(), SettingAboutGroup()],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
