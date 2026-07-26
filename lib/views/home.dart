import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:we_repkg/models/enums.dart';
import 'package:we_repkg/provider/navigation.dart';
import 'package:we_repkg/views/backup/backup.dart';
import 'package:we_repkg/views/nav/nav_rail.dart';
import 'package:we_repkg/views/setting/setting.dart';
import 'package:we_repkg/views/title_bar/window_title_bar.dart';
import 'package:window_manager/window_manager.dart';

import 'bottom/bottom.dart';
import 'content/content.dart';
import 'top/top.dart';

class HomeView extends ConsumerWidget {
  const HomeView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final NavSection section = ref.watch(currentSectionProvider);
    final Widget page = switch (section) {
      NavSection.extract => const _ExtractView(),
      NavSection.backup => const BackupView(),
      NavSection.settings => const SettingView(),
    };

    return DragToResizeArea(
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Column(
          children: [
            WindowTitleBar(),
            Expanded(
              child: Row(
                children: [
                  const NavRail(),
                  Expanded(child: page),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The wallpaper grid and its two toolbars: what the app opened straight into
/// before the rail existed.
class _ExtractView extends StatelessWidget {
  const _ExtractView();

  @override
  Widget build(BuildContext context) {
    return Column(children: [TopView(), ContentView(), BottomView()]);
  }
}
