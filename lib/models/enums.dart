import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:we_repkg/constants/i10n.dart';

enum RunState { initial, empty, complete }

extension RunStateExtension on RunState {
  bool get isInitial => this == RunState.initial;
  bool get isComplete => this == RunState.complete;
}

enum SortType { time, size, update }

extension SortTypeExtension on SortType {
  String get label {
    switch (this) {
      case SortType.time:
        return tr(AppI10n.homeSortDate);
      case SortType.size:
        return tr(AppI10n.homeSortSize);
      case SortType.update:
        return tr(AppI10n.homeSortUpdate);
    }
  }

  bool get isUpdate => this == SortType.update;
}

enum LanguageType { en, zh }

extension LanguageTypeExtension on LanguageType {
  String get label {
    switch (this) {
      case LanguageType.en:
        return 'English';
      case LanguageType.zh:
        return '中文';
    }
  }

  Locale get locale {
    switch (this) {
      case LanguageType.en:
        return const Locale('en', 'US');
      case LanguageType.zh:
        return const Locale('zh', 'CN');
    }
  }

}

enum ThemeType { light, dark, system }

extension ThemeTypeExtension on ThemeType {
  String get label {
    switch (this) {
      case ThemeType.light:
        return tr(AppI10n.settingSystemLight);
      case ThemeType.dark:
        return tr(AppI10n.settingSystemDark);
      case ThemeType.system:
        return tr(AppI10n.settingSystemSystem);
    }
  }

  ThemeMode get mode {
    switch (this) {
      case ThemeType.light:
        return ThemeMode.light;
      case ThemeType.dark:
        return ThemeMode.dark;
      case ThemeType.system:
        return ThemeMode.system;
    }
  }
}

/// The areas you can switch between, in the order they are listed.
///
/// Settings is not one: it opens as a card over whichever area you are in, so
/// it has nothing to be selected.
enum NavSection { extract, backup }

extension NavSectionExtension on NavSection {
  String get label {
    switch (this) {
      case NavSection.extract:
        return tr(AppI10n.navExtract);
      case NavSection.backup:
        return tr(AppI10n.navBackup);
    }
  }

  IconData get icon {
    switch (this) {
      case NavSection.extract:
        return Icons.grid_view_rounded;
      case NavSection.backup:
        return Icons.backup_outlined;
    }
  }
}

enum NotificationType { system, app }

extension NotificationTypeExtension on NotificationType {
  String get label {
    switch (this) {
      case NotificationType.system:
        return tr(AppI10n.settingSystemInSystem);
      case NotificationType.app:
        return tr(AppI10n.settingSystemInApp);
    }
  }

}

enum ExtractType { wallpaper, project }

extension ExtractTypeExtension on ExtractType {
  String get label {
    switch (this) {
      case ExtractType.wallpaper:
        return tr(AppI10n.homeWallpaper);
      case ExtractType.project:
        return tr(AppI10n.homeProject);
    }
  }

  bool get isWallpaper => this == ExtractType.wallpaper;
  bool get isProject => this == ExtractType.project;
}
