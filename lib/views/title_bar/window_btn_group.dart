import 'package:flutter/material.dart';
import 'package:we_repkg/widgets/app_icon_button.dart';
import 'package:window_manager/window_manager.dart';

class WindowBtnGroup extends StatefulWidget {
  const WindowBtnGroup({super.key});

  @override
  State<WindowBtnGroup> createState() => _WindowBtnGroupState();
}

class _WindowBtnGroupState extends State<WindowBtnGroup> with WindowListener {
  @override
  void initState() {
    windowManager.addListener(this);
    super.initState();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() {
    setState(() {});
  }

  @override
  void onWindowUnmaximize() {
    setState(() {});
  }

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
              windowManager.restore();
            } else {
              windowManager.minimize();
            }
          },
        ),
        FutureBuilder<bool>(
          future: windowManager.isMaximized(),
          builder: (BuildContext context, AsyncSnapshot<bool> snapshot) {
            IconData icon = snapshot.data == true
                ? Icons.filter_none
                : Icons.crop_square;
            double size = snapshot.data == true ? 14 : 16;
            void Function() onTap = snapshot.data == true
                ? () {
                    windowManager.unmaximize();
                  }
                : () {
                    windowManager.maximize();
                  };
            return AppIconButton(
              width: 40,
              height: 32,
              iconSize: size,
              icon: icon,
              onPressed: onTap,
            );
          },
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
