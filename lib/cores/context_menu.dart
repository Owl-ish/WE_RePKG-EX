import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_context_menu/flutter_context_menu.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:we_repkg/constants/i10n.dart';
import 'package:we_repkg/constants/nums.dart';
import 'package:we_repkg/constants/wallpaper_type.dart';
import 'package:we_repkg/models/wallpaper.dart';
import 'package:we_repkg/provider/wallpaper.dart';
import 'package:we_repkg/views/content/detail_dialog.dart';
import 'package:we_repkg/widgets/right_menu_item.dart';

import 'base.dart';
import 'extract.dart';

List<WallpaperInfo> menuTargets(
  List<WallpaperInfo> checked,
  WallpaperInfo wallpaper,
) {
  return checked.contains(wallpaper) ? checked : <WallpaperInfo>[wallpaper];
}

Future<void> showRightMenu(
  BuildContext context,
  TapDownDetails details,
  WidgetRef ref,
  WallpaperInfo wallpaper,
) async {
  List<WallpaperInfo> checkedList = ref.read(checkedWallpaperListProvider);
  final List<WallpaperInfo> targets = menuTargets(checkedList, wallpaper);
  final entries = <ContextMenuEntry>[
    // Double click opens the same dialog, but nothing on a tile advertises
    // that. This is the discoverable way in.
    RightMenuItem(
      label: tr(AppI10n.homeDetails),
      onSelected: (_) => showWallpaperDetail(context, wallpaper),
    ),
    // Neither is gated on type: project mode handles them all.
    RightMenuItem(
      label: tr(AppI10n.homeExtractSelectedAsWallpaper),
      onSelected: (_) => extractWallpapers(ref, targets),
    ),
    RightMenuItem(
      label: tr(AppI10n.homeExtractSelectedAsProject),
      onSelected: (_) => extractProject(ref, targets),
    ),
    if (wallpaper.type == WallpaperType.video)
      RightMenuItem(
        label: tr(AppI10n.homePlayVideo),
        onSelected: (_) => playVideo(wallpaper),
      ),
    RightMenuItem(
      label: tr(AppI10n.homeOpenFileLocation),
      onSelected: (_) => browserCurrent(wallpaper),
    ),
    // Right-clicking inside a multi-wallpaper selection acts on the whole
    // selection. Right-clicking outside one acts on that wallpaper alone.
    if (checkedList.length > 1 && checkedList.contains(wallpaper))
      RightMenuItem(
        label: tr(AppI10n.homeDeleteChecked),
        color: Colors.red,
        onSelected: (_) async => await deleteChecked(ref),
      )
    else
      RightMenuItem(
        label: tr(AppI10n.homeDeleteCurrent),
        color: Colors.red,
        onSelected: (_) async => await deleteCurrent(ref, wallpaper),
      ),
  ];

  await showMenuAt(context, details, entries);
}

typedef BackupFolderMenuTarget = ({String label, String path});

/// What a backup tile offers on a right click.
///
/// [folders] is resolved by the tile because ordinary cards represent one
/// live/backup pair while Reconcile can represent up to four concrete copies.
/// Keeping the menu generic preserves those distinct locations.
Future<void> showBackupMenu(
  BuildContext context,
  TapDownDetails details, {
  required VoidCallback onDetails,
  required List<BackupFolderMenuTarget> folders,
  String? actionLabel,
  VoidCallback? onAction,
}) async {
  await showMenuAt(context, details, <ContextMenuEntry>[
    // Double click opens the same dialog, but nothing on a tile advertises
    // that. This is the discoverable way in.
    RightMenuItem(
      label: tr(AppI10n.homeDetails),
      onSelected: (_) => onDetails(),
    ),
    for (final BackupFolderMenuTarget folder in folders)
      RightMenuItem(
        label: folder.label,
        onSelected: (_) => browserFolder(folder.path),
      ),
    if (actionLabel != null && onAction != null)
      RightMenuItem(label: actionLabel, onSelected: (_) => onAction()),
  ]);
}

/// The app's context menu: the caller's rows on the app's surface, at the
/// pointer.
Future<void> showMenuAt(
  BuildContext context,
  TapDownDetails details,
  List<ContextMenuEntry> entries,
) async {
  final ContextMenu<dynamic> menu = ContextMenu(
    entries: entries,
    boxDecoration: BoxDecoration(
      color: Theme.of(context).dialogTheme.backgroundColor,
      borderRadius: BorderRadius.circular(LayoutNums.controlRadius),
      boxShadow: [
        BoxShadow(blurRadius: 4, color: Colors.black.withValues(alpha: .2)),
      ],
    ),
    padding: EdgeInsets.zero,
    position: details.globalPosition,
  );

  await showContextMenu(context, contextMenu: menu);
}
