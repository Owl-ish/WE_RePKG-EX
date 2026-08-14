import 'package:flutter/material.dart';
import 'package:we_repkg/constants/nums.dart';
import 'package:we_repkg/widgets/app_icon_button.dart';

/// Runs the grid's order the other way. Which order that is belongs to the tab.
class SortToggle extends StatelessWidget {
  const SortToggle({
    super.key,
    required this.ascending,
    required this.onPressed,
  });

  final bool ascending;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return AppIconButton(
      onPressed: onPressed,
      icon: ascending
          ? Icons.arrow_upward_rounded
          : Icons.arrow_downward_rounded,
      width: TopBarNums.buttonSize,
      height: TopBarNums.buttonSize,
      iconSize: TopBarNums.iconSize,
    );
  }
}
