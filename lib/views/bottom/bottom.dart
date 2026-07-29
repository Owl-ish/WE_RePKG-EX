import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:we_repkg/constants/i10n.dart';
import 'package:we_repkg/constants/nums.dart';
import 'package:we_repkg/cores/base.dart';
import 'package:we_repkg/cores/extract.dart';
import 'package:we_repkg/models/wallpaper.dart';
import 'package:we_repkg/provider/wallpaper.dart';
import 'package:we_repkg/views/bottom/selected_count.dart';
import 'package:we_repkg/views/bottom/toggle_input.dart';
import 'package:we_repkg/widgets/custom_btn.dart';

import 'function_selected_btn.dart';

class BottomView extends ConsumerWidget {
  const BottomView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    List<WallpaperInfo> checkedList = ref.watch(checkedWallpaperListProvider);
    return Container(
      // Taller than the 48 it was, with the extra going below the controls so
      // they stop sitting on the window's bottom edge.
      height: 48 + LayoutNums.contentGap,
      padding: EdgeInsets.fromLTRB(
        LayoutNums.edgeInset,
        0,
        LayoutNums.edgeInset,
        LayoutNums.contentGap,
      ),
      child: Row(
        spacing: 8,
        children: [
          FunctionSelectedBtn(),
          ToggleInput(),
          if (checkedList.isEmpty)
            CustomBtn(
              onPressed: () => extractAll(ref),
              label: tr(AppI10n.homeExtractAll),
            ),
          if (checkedList.isNotEmpty) ...[
            CustomBtn(
              onPressed: () => extractChecked(ref),
              label: tr(AppI10n.homeExtractChecked),
            ),
            CustomBtn.destructive(
              onPressed: () => deleteChecked(ref),
              label: tr(AppI10n.homeDeleteChecked),
            ),
          ],
          const SelectedCount(),
        ],
      ),
    );
  }
}
