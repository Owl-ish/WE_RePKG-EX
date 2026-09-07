import 'dart:math';

import 'package:flutter/material.dart';
import 'package:we_repkg/config/theme_extensions.dart';
import 'package:we_repkg/constants/nums.dart';
import 'package:we_repkg/utils/backup_diff.dart';

/// Shared attention halo for backup actions. The control inside keeps its own
/// shape and fill; this only supplies the outward pulse.
class BackupActionGlow extends StatefulWidget {
  const BackupActionGlow({
    super.key,
    required this.colour,
    required this.enabled,
    required this.borderRadius,
    required this.child,
    this.glowKey,
    this.scale = 1,
  });

  final Color colour;
  final bool enabled;
  final BorderRadiusGeometry borderRadius;
  final Widget child;
  final Key? glowKey;
  final double scale;

  @override
  State<BackupActionGlow> createState() => _BackupActionGlowState();
}

class _BackupActionGlowState extends State<BackupActionGlow>
    with SingleTickerProviderStateMixin {
  static const Duration _period = Duration(milliseconds: 2200);
  late final AnimationController _glow = AnimationController(
    vsync: this,
    duration: _period,
  );

  @override
  void initState() {
    super.initState();
    if (widget.enabled) _glow.repeat();
  }

  @override
  void didUpdateWidget(BackupActionGlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled && !_glow.isAnimating) {
      _glow.repeat();
    } else if (!widget.enabled && _glow.isAnimating) {
      _glow.stop();
      _glow.value = 0;
    }
  }

  @override
  void dispose() {
    _glow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _glow,
    builder: (BuildContext context, Widget? child) {
      // Same slow swell as the status pills. At rest there is no halo; the
      // action keeps its normal pill surface and the emphasis grows outward.
      final double pulse = (1 - cos(_glow.value * 2 * pi)) / 2;
      final double scale = widget.scale;
      return DecoratedBox(
        key: widget.glowKey,
        decoration: BoxDecoration(
          borderRadius: widget.borderRadius,
          boxShadow: widget.enabled
              ? <BoxShadow>[
                  BoxShadow(
                    color: widget.colour.withValues(alpha: .14 * pulse),
                    blurRadius: 8 * pulse * scale,
                    spreadRadius: .4 * pulse * scale,
                  ),
                  BoxShadow(
                    color: widget.colour.withValues(alpha: .22 * pulse),
                    blurRadius: 20 * pulse * scale,
                    spreadRadius: 2 * pulse * scale,
                  ),
                ]
              : const <BoxShadow>[],
        ),
        child: child,
      );
    },
    child: widget.child,
  );
}

/// Bulk-action styling for the Backup summary and grouped cleanup controls.
class BackupBulkActionButton extends StatefulWidget {
  const BackupBulkActionButton({
    super.key,
    required this.label,
    required this.icon,
    required this.colour,
    required this.onPressed,
    this.destructive = false,
  });

  final String label;
  final IconData icon;
  final Color colour;
  final VoidCallback? onPressed;
  final bool destructive;

  @override
  State<BackupBulkActionButton> createState() => _BackupBulkActionButtonState();
}

class _BackupBulkActionButtonState extends State<BackupBulkActionButton> {
  bool _hovered = false;

  void _setHovered(bool hovered) {
    if (_hovered == hovered) return;
    setState(() => _hovered = hovered);
  }

  @override
  Widget build(BuildContext context) {
    final bool enabled = widget.onPressed != null;
    final ThemeData theme = Theme.of(context);
    final ActionButtonTheme actionColors = theme.actionButtons;
    final Color resolvedColour = enabled
        ? (widget.destructive
              ? actionColors.destructiveForeground
              : widget.colour)
        : theme.disabledColor;
    // Non-destructive state actions rest like their status pills. Destructive
    // actions use the app-wide danger surface, then the same outward pulse.
    final Color fill = widget.destructive
        ? (enabled
              ? actionColors.destructiveBackground
              : actionColors.destructiveBackground.withValues(alpha: .5))
        : Color.alphaBlend(
            resolvedColour.withValues(alpha: enabled ? .07 : .05),
            theme.scaffoldBackgroundColor,
          );
    final Color border = widget.destructive
        ? (enabled
              ? actionColors.destructiveBorder
              : actionColors.destructiveBorder.withValues(alpha: .5))
        : resolvedColour.withValues(alpha: enabled ? .2 : .15);
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: enabled ? (_) => _setHovered(true) : null,
      onExit: enabled ? (_) => _setHovered(false) : null,
      child: AnimatedScale(
        key: const ValueKey<String>('backup-all-action-scale'),
        scale: enabled && _hovered ? 1.06 : 1,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOutCubic,
        child: BackupActionGlow(
          colour: resolvedColour,
          enabled: enabled,
          borderRadius: LayoutNums.pill,
          glowKey: const ValueKey<String>('backup-all-action-glow'),
          child: Material(
            color: fill,
            shape: RoundedRectangleBorder(
              borderRadius: LayoutNums.pill,
              side: BorderSide(color: border),
            ),
            child: InkWell(
              borderRadius: LayoutNums.pill,
              onTap: widget.onPressed,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: LayoutNums.compactGap,
                  children: <Widget>[
                    Icon(widget.icon, size: 16, color: resolvedColour),
                    Text(widget.label, style: TextStyle(color: resolvedColour)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

IconData backupActionIcon(BackupAction action) => switch (action) {
  BackupAction.backUp => Icons.backup_outlined,
  BackupAction.update => Icons.sync_rounded,
  BackupAction.restore => Icons.restore_rounded,
  BackupAction.recycleJunk => Icons.delete_outline_rounded,
  BackupAction.ignoreUpdate => Icons.visibility_off_outlined,
  BackupAction.showUpdateAgain => Icons.visibility_outlined,
};
