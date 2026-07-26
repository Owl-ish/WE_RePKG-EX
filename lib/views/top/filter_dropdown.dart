import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:we_repkg/constants/i10n.dart';
import 'package:we_repkg/constants/nums.dart';
import 'package:we_repkg/models/filter.dart';
import 'package:we_repkg/provider/filter.dart';
import 'package:we_repkg/widgets/app_icon_button.dart';

/// One checkbox row: its label, whether the wallpapers are showing, and the
/// setter that flips it.
typedef _FilterBox = (String, bool, void Function(bool));

/// Type and age-rating filters, in the top bar rather than the settings window.
///
/// The trigger stays icon-sized on purpose. TopView is a fixed-width Row, and at
/// the 1060px minimum window width (config/app.dart) the side panel leaves it
/// roughly 200px of slack, so a labelled dropdown the width of SortDropdown
/// would overflow the row.
class FilterDropdown extends ConsumerWidget {
  const FilterDropdown({super.key});

  static const double _menuWidth = 240;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final WallpaperFilter filter = ref.watch(filterStateProvider);
    final filterRead = ref.read(filterStateProvider.notifier);
    final TextStyle? itemStyle = theme.textTheme.bodySmall?.copyWith(
      fontSize: 13,
    );

    // A ticked box means "show these", so every value is the negation of the
    // stored hideX flag. The storage keys keep their original names; renaming
    // them would silently reset every existing user's saved filters.
    final List<_FilterBox> types = [
      (
        tr(AppI10n.homeScene),
        !filter.hideScene,
        (bool v) => filterRead.updateHideScene(!v),
      ),
      (
        tr(AppI10n.homeVideo),
        !filter.hideVideo,
        (bool v) => filterRead.updateHideVideo(!v),
      ),
      (
        tr(AppI10n.homeWeb),
        !filter.hideWeb,
        (bool v) => filterRead.updateHideWeb(!v),
      ),
      (
        tr(AppI10n.homeApplication),
        !filter.hideApp,
        (bool v) => filterRead.updateHideApp(!v),
      ),
      (
        tr(AppI10n.homeUnknown),
        !filter.hideUnknown,
        (bool v) => filterRead.updateHideUnknown(!v),
      ),
    ];

    // Wallpaper Engine's three age levels, from project.json's `contentrating`.
    final List<_FilterBox> ratings = [
      (
        tr(AppI10n.homeFilterRatingEveryone),
        !filter.hideEveryone,
        (bool v) => filterRead.updateHideEveryone(!v),
      ),
      (
        tr(AppI10n.homeFilterRatingQuestionable),
        !filter.hideQuestionable,
        (bool v) => filterRead.updateHideQuestionable(!v),
      ),
      (
        tr(AppI10n.homeFilterRatingMature),
        !filter.hideMature,
        (bool v) => filterRead.updateHideMature(!v),
      ),
    ];

    // Tint the icon while anything is hidden, so a filtered library never looks
    // like an empty one. Doubles as whether reset has anything to do.
    final bool active = !filter.nothingHidden;

    return CheckboxTheme(
      data: CheckboxThemeData(
        side: const BorderSide(width: 2, color: Colors.grey),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? theme.primaryColor
              : Colors.transparent,
        ),
      ),
      child: MenuAnchor(
        // Right-align the panel with the trigger. Left to itself the menu hangs
        // off the trigger's left edge, runs past the window, and Flutter shunts
        // it back so it sits flush against the window edge.
        alignmentOffset: const Offset(TopBarNums.buttonSize - _menuWidth, 4),
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(
            theme.dropdownMenuTheme.inputDecorationTheme?.fillColor,
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          ),
          minimumSize: const WidgetStatePropertyAll(Size(_menuWidth, 0)),
          maximumSize: const WidgetStatePropertyAll(
            Size(_menuWidth, double.infinity),
          ),
        ),
        builder: (context, controller, child) => AppIconButton(
          tooltip: tr(AppI10n.homeFilterTip),
          onPressed: () =>
              controller.isOpen ? controller.close() : controller.open(),
          icon: Icons.filter_alt_rounded,
          width: TopBarNums.buttonSize,
          height: TopBarNums.buttonSize,
          iconSize: TopBarNums.iconSize,
          color: active ? theme.primaryColor : null,
        ),
        // closeOnActivate stays false throughout: ticking three boxes should
        // take one trip to the menu, not three.
        menuChildren: [
          _label(tr(AppI10n.homeFilterType)),
          ..._boxes(types, itemStyle),
          const _MenuDivider(),
          _label(tr(AppI10n.homeFilterRating)),
          ..._boxes(ratings, itemStyle),
          const _MenuDivider(),
          MenuItemButton(
            closeOnActivate: false,
            // Disabled rather than hidden, so the menu doesn't reflow under the
            // pointer the moment the last box goes back on.
            onPressed: active ? filterRead.reset : null,
            leadingIcon: Icon(
              Icons.restart_alt_rounded,
              size: 18,
              color: active ? null : theme.disabledColor,
            ),
            child: Text(tr(AppI10n.homeFilterReset), style: itemStyle),
          ),
        ],
      ),
    );
  }

  Iterable<Widget> _boxes(List<_FilterBox> boxes, TextStyle? style) =>
      boxes.map(
        (box) => CheckboxMenuButton(
          value: box.$2,
          closeOnActivate: false,
          onChanged: (checked) => box.$3(checked ?? false),
          child: Text(box.$1, style: style),
        ),
      );

  Widget _label(String label) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
    child: Text(
      label,
      style: const TextStyle(
        fontSize: 12,
        color: Colors.grey,
        fontFamily: 'Microsoft YaHei',
      ),
    ),
  );
}

/// A Divider needs a bounded width, which the menu panel only has because
/// [FilterDropdown] pins the panel to a fixed size.
class _MenuDivider extends StatelessWidget {
  const _MenuDivider();

  @override
  Widget build(BuildContext context) => const SizedBox(
    width: FilterDropdown._menuWidth,
    child: Divider(height: 9, thickness: 1),
  );
}
