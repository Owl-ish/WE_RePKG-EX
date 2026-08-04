import 'package:flutter/material.dart';

/// 省略号动画文本组件
class EllipsisAnimationText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final Duration animationDuration;

  const EllipsisAnimationText({
    super.key,
    required this.text,
    this.style,
    this.animationDuration = const Duration(milliseconds: 1200),
  });

  @override
  State<EllipsisAnimationText> createState() => _EllipsisAnimationTextState();
}

class _EllipsisAnimationTextState extends State<EllipsisAnimationText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ellipsisController;
  late final Animation<int> _ellipsisAnimation;
  int _dots = 0;

  @override
  void initState() {
    super.initState();
    // 省略号动画控制器
    _ellipsisController = AnimationController(
      duration: widget.animationDuration,
      vsync: this,
    );

    // 整数动画，范围从0到6，表示省略号的数量
    _ellipsisAnimation = IntTween(
      begin: 0,
      end: 6,
    ).animate(_ellipsisController);
    // Rebuilt on the seven values it actually shows, not on all ~72 ticks of
    // the cycle. This runs throughout a scan and an extraction, when the CPU
    // has better things to do.
    _ellipsisAnimation.addListener(() {
      if (_ellipsisAnimation.value != _dots) {
        setState(() => _dots = _ellipsisAnimation.value);
      }
    });
    _ellipsisController.repeat();
  }

  @override
  void dispose() {
    _ellipsisController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      '${widget.text}${'.' * _dots}',
      style: widget.style ?? Theme.of(context).textTheme.bodyMedium,
    );
  }
}
