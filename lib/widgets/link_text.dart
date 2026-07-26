import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class LinkText extends StatefulWidget {
  const LinkText({super.key, required this.label, required this.uri});

  final String label;
  final String uri;

  @override
  State<LinkText> createState() => _LinkTextState();
}

class _LinkTextState extends State<LinkText> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color linkColor = theme.colorScheme.primary;
    final Color hoverTarget = theme.brightness == Brightness.dark
        ? Colors.white
        : Colors.black;
    final Color currentColor = _hover
        ? Color.lerp(linkColor, hoverTarget, .18)!
        : linkColor;

    return Tooltip(
      message: widget.uri,
      waitDuration: const Duration(milliseconds: 350),
      child: Semantics(
        link: true,
        label: widget.label,
        child: MouseRegion(
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: InkWell(
            onTap: () async => await launchUrl(Uri.parse(widget.uri)),
            hoverColor: linkColor.withValues(alpha: .08),
            borderRadius: BorderRadius.circular(3),
            mouseCursor: SystemMouseCursors.click,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 5,
                children: [
                  GitHubMark(size: 14, color: currentColor),
                  Text(
                    widget.label,
                    style: TextStyle(
                      fontSize: 14,
                      color: currentColor,
                      fontWeight: FontWeight.w600,
                      decoration: _hover
                          ? TextDecoration.underline
                          : TextDecoration.none,
                      decorationColor: currentColor,
                      decorationThickness: 1.2,
                      fontFamily: 'Microsoft YaHei',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class GitHubMark extends StatelessWidget {
  const GitHubMark({super.key, this.size = 14, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _GitHubMarkPainter(color),
    );
  }
}

class _GitHubMarkPainter extends CustomPainter {
  const _GitHubMarkPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);

    final Path path = Path()
      ..moveTo(12, .297)
      ..cubicTo(5.37, .297, 0, 5.67, 0, 12.297)
      ..cubicTo(0, 17.6, 3.438, 22.097, 8.205, 23.682)
      ..cubicTo(8.805, 23.795, 9.025, 23.424, 9.025, 23.105)
      ..cubicTo(9.025, 22.82, 9.015, 22.065, 9.01, 21.065)
      ..cubicTo(5.672, 21.789, 4.968, 19.455, 4.968, 19.455)
      ..cubicTo(4.422, 18.068, 3.633, 17.699, 3.633, 17.699)
      ..cubicTo(2.546, 16.955, 3.717, 16.97, 3.717, 16.97)
      ..cubicTo(4.922, 17.054, 5.555, 18.207, 5.555, 18.207)
      ..cubicTo(6.625, 20.042, 8.364, 19.512, 9.05, 19.205)
      ..cubicTo(9.158, 18.429, 9.468, 17.9, 9.812, 17.6)
      ..cubicTo(7.147, 17.3, 4.346, 16.268, 4.346, 11.67)
      ..cubicTo(4.346, 10.36, 4.811, 9.29, 5.581, 8.45)
      ..cubicTo(5.446, 8.147, 5.041, 6.927, 5.686, 5.274)
      ..cubicTo(5.686, 5.274, 6.691, 4.952, 8.986, 6.504)
      ..cubicTo(9.946, 6.237, 10.966, 6.105, 11.986, 6.099)
      ..cubicTo(13.006, 6.105, 14.026, 6.237, 14.986, 6.504)
      ..cubicTo(17.266, 4.952, 18.271, 5.274, 18.271, 5.274)
      ..cubicTo(18.916, 6.927, 18.511, 8.147, 18.391, 8.45)
      ..cubicTo(19.156, 9.29, 19.621, 10.36, 19.621, 11.67)
      ..cubicTo(19.621, 16.28, 16.816, 17.295, 14.146, 17.59)
      ..cubicTo(14.566, 17.95, 14.956, 18.686, 14.956, 19.81)
      ..cubicTo(14.956, 21.416, 14.941, 22.706, 14.941, 23.096)
      ..cubicTo(14.941, 23.411, 15.151, 23.786, 15.766, 23.666)
      ..cubicTo(20.565, 22.092, 24, 17.592, 24, 12.297)
      ..cubicTo(24, 5.67, 18.627, .297, 12, .297)
      ..close();

    canvas.drawPath(path, Paint()..color = color);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GitHubMarkPainter oldDelegate) =>
      oldDelegate.color != color;
}
