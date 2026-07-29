import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:we_repkg/constants/i10n.dart';
import 'package:we_repkg/provider/wallpaper.dart';

class SelectedCount extends ConsumerWidget {
  const SelectedCount({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final int count = ref.watch(checkedWallpaperListProvider).length;
    if (count == 0) return const SizedBox.shrink();

    final ThemeData theme = Theme.of(context);
    return Text(
      tr(AppI10n.homeSelectedCount, namedArgs: {'count': '$count'}),
      style: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurface.withValues(alpha: .68),
      ),
    );
  }
}
