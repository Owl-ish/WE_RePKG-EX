import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:we_repkg/config/theme.dart';
import 'package:we_repkg/constants/keys.dart';
import 'package:we_repkg/constants/strings.dart';
import 'package:we_repkg/models/enums.dart';
import 'package:we_repkg/src/rust/frb_generated.dart';
import 'package:we_repkg/utils/pack.dart';
import 'package:we_repkg/utils/storage.dart';
import 'package:window_manager/window_manager.dart';

class AppConfig {
  static Future<void> init(List<String> args) async {
    WidgetsFlutterBinding.ensureInitialized();
    await windowManager.ensureInitialized();
    // A hot restart creates a new Dart isolate inside the existing visible
    // native window. Do not hide or reconfigure that window as if it were a
    // fresh process; that can leave only its border visible while Flutter
    // submits the replacement surface.
    final bool windowAlreadyVisible = await windowManager.isVisible();

    await RustLib.init();
    await PackInfo.init();
    await StorageUtil.init();
    await EasyLocalization.ensureInitialized();

    await localNotifier.setup(
      appName: AppStrings.appName,
      shortcutPolicy: ShortcutPolicy.requireCreate,
    );

    if (!windowAlreadyVisible) {
      // Restore the saved size, or use a 16:9 default on first launch.
      final int? savedWidth = StorageUtil.getInt(AppKeys.windowWidth);
      final int? savedHeight = StorageUtil.getInt(AppKeys.windowHeight);
      final Size windowSize = (savedWidth != null && savedHeight != null)
          ? Size(savedWidth.toDouble(), savedHeight.toDouble())
          : const Size(1380, 800);

      final ThemeType savedTheme =
          ThemeType.values[StorageUtil.getInt(AppKeys.theme) ?? 0];
      final bool darkWindow =
          savedTheme == ThemeType.dark ||
          (savedTheme == ThemeType.system &&
              WidgetsBinding.instance.platformDispatcher.platformBrightness ==
                  Brightness.dark);
      final Color windowBackground = darkWindow
          ? AppTheme.darkTheme.scaffoldBackgroundColor
          : AppTheme.lightTheme.scaffoldBackgroundColor;

      final WindowOptions windowOptions = WindowOptions(
        size: windowSize,
        minimumSize: const Size(1060, 720),
        center: true,
        title: AppStrings.appName,
        // The app is opaque. An opaque native fallback prevents the desktop
        // showing through while Flutter swaps frames during a restart.
        backgroundColor: windowBackground,
        titleBarStyle: TitleBarStyle.hidden,
      );

      await windowManager.waitUntilReadyToShow(windowOptions);
      if (StorageUtil.getBool(AppKeys.maximizeOpen)) {
        await windowManager.maximize();
      }
      await windowManager.setAsFrameless();
      await windowManager.setHasShadow(true);

      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await windowManager.show();
        await windowManager.focus();
      });
    }
  }
}
