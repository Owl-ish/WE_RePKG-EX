import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:we_repkg/models/enums.dart';
import 'package:we_repkg/provider/navigation.dart';

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
              tooltip: section.label,
              selected: section == current,
              onTap: () =>
                  ref.read(currentSectionProvider.notifier).update(section),
            ),
        ],
      ),
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.selected = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color active = theme.primaryColor;
    final Color idle = theme.iconTheme.color ?? Colors.grey;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: Tooltip(
        message: tooltip,
        waitDuration: const Duration(milliseconds: 400),
        excludeFromSemantics: true,
        child: Semantics(
          label: tooltip,
          button: true,
          selected: selected,
          child: Material(
            color: selected
                ? active.withValues(alpha: .12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(6),
              mouseCursor: SystemMouseCursors.click,
              child: SizedBox(
                width: 40,
                height: 40,
                child: Icon(
                  icon,
                  size: 20,
                  color: selected ? active : idle,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
