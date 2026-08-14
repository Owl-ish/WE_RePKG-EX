import 'package:flutter/material.dart';
import 'package:we_repkg/constants/nums.dart';

/// The bar across the top of a tab: controls either side of a centred search
/// box.
///
/// Both grids have one and they have to line up, so the height, the inset and
/// the cap on the middle live here. The gaps between a tab's own controls go in
/// [leading] and [trailing].
class TopBar extends StatelessWidget {
  const TopBar({
    super.key,
    this.leading = const <Widget>[],
    this.centre = const SizedBox.shrink(),
    this.trailing = const <Widget>[],
  });

  final List<Widget> leading;
  final Widget centre;
  final List<Widget> trailing;

  static const double height = 48;

  /// Wider than this and the search field reads as a text editor.
  static const double _centreMaxWidth = 640;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: LayoutNums.edgeInset),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          ...leading,
          // Expanded absorbs the slack so the row cannot overflow.
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _centreMaxWidth),
                child: centre,
              ),
            ),
          ),
          ...trailing,
        ],
      ),
    );
  }
}
