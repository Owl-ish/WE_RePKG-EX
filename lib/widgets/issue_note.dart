import 'package:flutter/material.dart';
import 'package:we_repkg/constants/nums.dart';

/// A low, tinted explanation shown beneath the issue it describes.
class IssueNote extends StatelessWidget {
  const IssueNote({
    super.key,
    required this.colour,
    required this.child,
    this.icon = Icons.info_outline_rounded,
    this.compact = false,
  });

  final Color colour;
  final IconData icon;
  final Widget child;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: LayoutNums.mediumGap,
        vertical: compact ? LayoutNums.tinyGap / 2 : LayoutNums.smallGap,
      ),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(LayoutNums.surfaceRadius),
        border: Border.all(color: colour.withValues(alpha: .3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: LayoutNums.smallGap,
        children: <Widget>[
          Icon(icon, size: 18, color: colour),
          Expanded(child: child),
        ],
      ),
    );
  }
}
