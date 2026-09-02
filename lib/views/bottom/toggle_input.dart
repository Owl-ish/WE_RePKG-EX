import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:we_repkg/constants/i10n.dart';
import 'package:we_repkg/actions/path_actions.dart';
import 'package:we_repkg/models/enums.dart';
import 'package:we_repkg/provider/system.dart';
import 'package:we_repkg/widgets/folder_input.dart';

/// Where the current extraction writes, and the only place to set it.
///
/// Reset means two different things because the two folders do: the project
/// folder goes back to the one derived from the wallpaper library, while the
/// export folder has nothing to derive from and clears instead.
class ToggleInput extends ConsumerWidget {
  const ToggleInput({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ExtractType extractType = ref.watch(currentExtractTypeProvider);
    final bool wallpaper = extractType.isWallpaper;
    final String? text = wallpaper
        ? ref.watch(exportPathProvider)
        : ref.watch(projectPathProvider);
    return Expanded(
      child: Row(
        spacing: 4,
        children: [
          Expanded(
            child: FolderInput(
              text: text,
              hintText: tr(
                wallpaper
                    ? AppI10n.homeExtractFolderTip
                    : AppI10n.homeProjectFolderTip,
              ),
              onPressed: () async => wallpaper
                  ? await setExportPath(ref)
                  : await setProjectPath(ref),
            ),
          ),
          IconButton(
            tooltip: tr(
              wallpaper ? AppI10n.homeClearFolder : AppI10n.homeResetFolder,
            ),
            onPressed: () =>
                wallpaper ? refreshExportPath(ref) : refreshProjectPath(ref),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
    );
  }
}
