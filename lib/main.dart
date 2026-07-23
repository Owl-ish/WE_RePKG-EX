import 'package:bot_toast/bot_toast.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import 'package:we_repkg/config/language.dart';
import 'package:we_repkg/config/theme.dart';
import 'package:we_repkg/constants/keys.dart';
import 'package:we_repkg/constants/strings.dart';
import 'package:we_repkg/models/enums.dart';
import 'package:we_repkg/provider/system.dart';
import 'package:we_repkg/utils/storage.dart';
import 'package:we_repkg/views/home.dart';

import 'config/app.dart';

Future<void> main() async {
  await AppConfig.init([]);
  runApp(
    ProviderScope(
      child: EasyLocalization(
        path: LanguageConfig.path,
        supportedLocales: LanguageConfig.supportedLocales,
        fallbackLocale: LanguageConfig.fallbackLocale,
        child: MyApp(),
      ),
    ),
  );
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> with WindowListener {
  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowResized() async {
    // Persist the window size so it's restored next launch. Skip while maximized
    // so we store the real restored size, not the maximized bounds.
    if (await windowManager.isMaximized()) return;
    final Size size = await windowManager.getSize();
    await StorageUtil.setInt(AppKeys.windowWidth, size.width.round());
    await StorageUtil.setInt(AppKeys.windowHeight, size.height.round());
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppStrings.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ref.watch(currentThemeProvider).mode,
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      builder: BotToastInit(),
      navigatorObservers: [BotToastNavigatorObserver()],
      home: HomeView(),
    );
  }
}
