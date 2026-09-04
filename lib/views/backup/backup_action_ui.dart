import 'dart:math';

import 'package:flutter/material.dart';
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

IconData backupActionIcon(BackupAction action) => switch (action) {
  BackupAction.backUp => Icons.backup_outlined,
  BackupAction.update => Icons.sync_rounded,
  BackupAction.restore => Icons.restore_rounded,
  BackupAction.recycleJunk => Icons.delete_outline_rounded,
  BackupAction.ignoreUpdate => Icons.visibility_off_outlined,
  BackupAction.showUpdateAgain => Icons.visibility_outlined,
};
