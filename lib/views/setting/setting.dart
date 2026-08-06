import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:we_repkg/constants/i10n.dart';
import 'package:we_repkg/constants/nums.dart';
import 'package:we_repkg/views/setting/setting_about_group.dart';
import 'package:we_repkg/views/setting/setting_backup_group.dart';
import 'package:we_repkg/views/setting/setting_config_group.dart';
import 'package:we_repkg/views/setting/setting_library_group.dart';
import 'package:we_repkg/views/setting/setting_system_group.dart';

/// The contents of the settings card. [SettingCard] owns how wide it gets.
class SettingView extends StatelessWidget {
  const SettingView({super.key});

  /// Below this the groups stack; above it they sit side by side.
  ///
  /// Measured against the card's width less its insets, not the window. Too low
  /// and the smallest window gets two columns of about 400px, which the longer
  /// subtitles do not fit; too high and the second column is unreachable at any
  /// size. At the 1060px minimum window the card leaves 813px, and two columns
  /// start at roughly 1337px of window.
  static const double twoColumnWidth = 1040;
  static const double columnGap = 40;

  /// Wider than the grid's [LayoutNums.edgeInset], because a path row runs to
  /// the card's edge on both sides where the grid scrolls past a bar instead.
  /// The bottom is the largest: the last row is a control, and a control sitting
  /// on the edge reads as cut off whether it is or not.
  static const double _inset = 28;
  static const double _topInset = 16;
  static const double _bottomInset = 24;

  /// Named once each, so a new group cannot reach one layout and miss the
  /// other. Split by group, not by height: the extraction settings are one
  /// subject and stay together even though it leaves the right column shorter.
  ///
  /// Every folder setting is in the right column, below the tool and ACF paths,
  /// so the left column is only what a run does and the right is only where
  /// things live.
  static const List<Widget> _leftGroups = <Widget>[SettingConfigGroup()];
  static const List<Widget> _rightGroups = <Widget>[
    SettingSystemGroup(),
    SettingAboutGroup(),
    SettingBackupGroup(),
    SettingLibraryGroup(),
  ];

  static Widget _column(List<Widget> groups) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: groups,
  );

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(_inset, _topInset, _inset, 8),
          child: Text(
            tr(AppI10n.settingTitle),
            style: theme.textTheme.titleLarge?.copyWith(fontSize: 20),
          ),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(_inset, 0, _inset, _bottomInset),
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < twoColumnWidth) {
                  return _column(<Widget>[..._leftGroups, ..._rightGroups]);
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(child: _column(_leftGroups)),
                    const SizedBox(width: columnGap),
                    Expanded(child: _column(_rightGroups)),
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
