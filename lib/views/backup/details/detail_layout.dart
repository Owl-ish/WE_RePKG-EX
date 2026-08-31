import 'package:flutter/material.dart';

/// Compact title-and-items block shared by Backup detail states.
class BackupDetailGroup extends StatelessWidget {
  const BackupDetailGroup({
    super.key,
    required this.title,
    required this.items,
    required this.foreground,
  });

  final String title;
  final List<String> items;
  final Color foreground;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Text(
        title,
        style: TextStyle(color: foreground, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 5),
      for (final String item in items)
        Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: Text(item, style: TextStyle(color: foreground, height: 1.3)),
        ),
    ],
  );
}

/// Explicit action prompt used to reveal or start denser detail work.
class BackupDetailExpandPrompt extends StatelessWidget {
  const BackupDetailExpandPrompt({
    super.key,
    required this.title,
    required this.subtitle,
    required this.foreground,
    required this.onPressed,
  });

  final String title;
  final String subtitle;
  final Color foreground;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '$title. $subtitle',
    onTap: onPressed,
    child: MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTap: onPressed,
        child: Container(
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            border: Border.all(color: foreground.withValues(alpha: .2)),
            borderRadius: BorderRadius.circular(8),
            color: foreground.withValues(alpha: .045),
          ),
          child: Row(
            children: <Widget>[
              Icon(
                Icons.open_in_full_rounded,
                size: 17,
                color: foreground.withValues(alpha: .76),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: TextStyle(
                        color: foreground,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: foreground.withValues(alpha: .68),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Backup-detail scroll view whose thumb stays visible whenever there is actual
/// overflow. The explicit controller keeps the thumb attached to the intended
/// viewport instead of relying on an ambient primary scroll controller.
class BackupDetailScrollView extends StatefulWidget {
  const BackupDetailScrollView({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  State<BackupDetailScrollView> createState() => _BackupDetailScrollViewState();
}

class _BackupDetailScrollViewState extends State<BackupDetailScrollView> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scrollbar(
    controller: _controller,
    thumbVisibility: true,
    child: SingleChildScrollView(
      controller: _controller,
      padding: widget.padding,
      child: widget.child,
    ),
  );
}
