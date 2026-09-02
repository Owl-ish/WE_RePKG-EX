import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:we_repkg/actions/wallpaper_actions.dart';
import 'package:we_repkg/models/enums.dart';
import 'package:we_repkg/provider/system.dart';
import 'package:we_repkg/utils/backup_diff.dart';
import 'package:we_repkg/widgets/pill_dropdown.dart';

/// Which library the grid shows. Switching rescans, which is also what clears
/// a selection made against the library being left behind.
class LibraryDropdown extends ConsumerWidget {
  const LibraryDropdown({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PillDropdown<WallpaperLibrary>(
      value: ref.watch(currentLibraryProvider),
      items: WallpaperLibrary.values,
      labelOf: (WallpaperLibrary library) => library.label,
      onChanged: (WallpaperLibrary library) {
        ref.read(currentLibraryProvider.notifier).update(library);
        refreshWallpaper(ref);
      },
    );
  }
}
