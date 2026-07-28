import 'dart:math';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:we_repkg/constants/i10n.dart';
import 'package:we_repkg/views/setting/setting.dart';
import 'package:we_repkg/widgets/app_dialog_surface.dart';

/// Settings as a card over the workspace, sized off the window rather than
/// filling it, so the grid stays visible around the edges.
class SettingCard extends StatelessWidget {
  const SettingCard({super.key});

  /// Wide enough for two columns on a big monitor and no wider. Past this the
  /// card stops reading as a card.
  static const double maxWidth = 1240;
  static const double maxHeight = 880;

  static double widthFor(double window) => min(window * .82, maxWidth);

  static double heightFor(double window) => min(window * .86, maxHeight);

  @override
  Widget build(BuildContext context) {
    final Size window = MediaQuery.sizeOf(context);
    return AppDialogSurface(
      width: widthFor(window.width),
      maxHeight: heightFor(window.height),
      child: const SettingView(),
    );
  }
}

/// Unrolls settings open, the same way the filter panel does.
///
/// A route, so Navigator owns the barrier, the Escape key and focus. Doing that
/// by hand is how the accessibility tree got upset last time.
Future<void> showSettingCard(BuildContext context) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: tr(AppI10n.settingTitle),
    barrierColor: Colors.black.withValues(alpha: .45),
    transitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (_, _, _) => const SettingCard(),
    transitionBuilder: (context, animation, _, child) {
      final double t = Curves.easeInOutCubic.transform(animation.value);
      return Opacity(
        opacity: t,
        // At zero opacity Flutter drops the whole subtree out of the
        // accessibility tree, and the settings form is a few hundred nodes
        // going at once. Windows' bridge then reports orphaned nodes and stays
        // confused long after the card has closed.
        alwaysIncludeSemantics: true,
        // Scaled, not clipped or height-factored. Both of those drop whatever
        // falls outside them from the accessibility tree, so animating one over
        // a few hundred settings nodes adds and removes them every frame and
        // Windows' AXTree bridge gives up. A transform moves nodes instead of
        // removing them, so the tree stays put for the whole 260ms.
        child: Center(
          child: Transform.scale(
            scaleY: t,
            alignment: Alignment.topCenter,
            filterQuality: FilterQuality.medium,
            child: child,
          ),
        ),
      );
    },
  );
}
