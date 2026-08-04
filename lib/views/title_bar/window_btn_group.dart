import 'package:flutter/material.dart';
import 'package:we_repkg/widgets/app_icon_button.dart';
import 'package:window_manager/window_manager.dart';

class WindowBtnGroup extends StatefulWidget {
  const WindowBtnGroup({super.key});

  @override
  State<WindowBtnGroup> createState() => _WindowBtnGroupState();
}

class _WindowBtnGroupState extends State<WindowBtnGroup> with WindowListener {
  // Kept here rather than asked for in build. A FutureBuilder over
  // isMaximized() fired a method channel call on every rebuild and had no
  // answer for the first frame of each one, so the restore button flashed
  // back to the maximize icon whenever anything above it rebuilt.
  bool _maximized = false;

  @override
  void initState() {
    windowManager.addListener(this);
    super.initState();
    windowManager.isMaximized().then((value) {
      if (mounted) setState(() => _maximized = value);
    });
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() => setState(() => _maximized = true);

  @override
  void onWindowUnmaximize() => setState(() => _maximized = false);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        AppIconButton(
          width: 40,
          height: 32,
          icon: Icons.horizontal_rule_rounded,
          onPressed: () async {
            bool isMinimized = await windowManager.isMinimized();
            if (isMinimized) {
              await windowManager.restore();
            } else {
              await windowManager.minimize();
            }
          },
        ),
        AppIconButton(
          width: 40,
          height: 32,
          iconSize: _maximized ? 14 : 16,
          icon: _maximized ? Icons.filter_none : Icons.crop_square,
          onPressed: _maximized
              ? windowManager.unmaximize
              : windowManager.maximize,
        ),
        AppIconButton(
          width: 40,
          height: 32,
          icon: Icons.close_rounded,
          onPressed: () {
            windowManager.close();
          },
        ),
      ],
    );
  }
}
