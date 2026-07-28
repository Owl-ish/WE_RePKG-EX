import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:we_repkg/constants/i10n.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:we_repkg/models/enums.dart';
import 'package:we_repkg/provider/navigation.dart';
import 'package:we_repkg/views/setting/setting_card.dart';

/// The app's top level navigation, down the left edge.
class NavRail extends ConsumerWidget {
  const NavRail({super.key});

  /// Fixed icons-only width: the rail never relayouts the wallpaper grid.
  static const double width = 60;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final NavSection current = ref.watch(currentSectionProvider);

    return Container(
      width: width,
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: theme.dividerColor.withValues(alpha: .45)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          for (final NavSection section in NavSection.values)
            _RailButton(
              icon: section.icon,
              label: section.label,
              selected: section == current,
              onTap: () =>
                  ref.read(currentSectionProvider.notifier).update(section),
            ),
          const Spacer(),
          // Not a destination: it opens a card over whatever is showing, so it
          // never takes the selected state the buttons above share. No tooltip
          // either, since Windows' accessibility bridge trips over them
          // appearing and disappearing.
          _RailButton(
            icon: Icons.settings_outlined,
            label: tr(AppI10n.settingTitle),
            showTooltip: false,
            onTap: () => showSettingCard(context),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.showTooltip = true,
    this.selected,
  });

  final IconData icon;

  /// Always announced. [showTooltip] only decides whether it is also drawn on
  /// hover.
  final String label;
  final bool showTooltip;
  final VoidCallback onTap;

  /// Null for buttons that open something rather than navigate, so they are not
  /// announced as unselected when there is nothing to select.
  final bool? selected;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color active = theme.primaryColor;
    final Color idle = theme.iconTheme.color ?? Colors.grey;

    final bool on = selected ?? false;
    Widget button = Semantics(
      label: label,
      button: true,
      selected: selected,
      child: Material(
        color: on ? active.withValues(alpha: .12) : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          mouseCursor: SystemMouseCursors.click,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(icon, size: 20, color: on ? active : idle),
          ),
        ),
      ),
    );

    if (showTooltip) {
      button = Tooltip(
        message: label,
        waitDuration: const Duration(milliseconds: 400),
        excludeFromSemantics: true,
        child: button,
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: button,
    );
  }
}
