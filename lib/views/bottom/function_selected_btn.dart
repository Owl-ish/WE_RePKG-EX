import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:we_repkg/constants/i10n.dart';
import 'package:we_repkg/models/enums.dart';
import 'package:we_repkg/provider/system.dart';

class FunctionSelectedBtn extends ConsumerWidget {
  const FunctionSelectedBtn({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ExtractType type = ref.watch(currentExtractTypeProvider);
    ThemeData theme = Theme.of(context);
    return Row(
      spacing: 8,
      children: [
        PopupMenuButton<ExtractType>(
          icon: const Icon(Icons.arrow_drop_down),
          iconSize: 22,
          tooltip: type.label,
          // Circular and filled, like the scroll edge buttons. A bare arrow on
          // the bar was easy to miss for something that changes what extracting
          // does.
          style: IconButton.styleFrom(
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            foregroundColor: theme.colorScheme.onSurface,
            shape: const CircleBorder(),
            side: BorderSide(
              color: theme.colorScheme.onSurface.withValues(alpha: .12),
            ),
            padding: EdgeInsets.zero,
            minimumSize: const Size(34, 34),
            maximumSize: const Size(34, 34),
            hoverColor: theme.colorScheme.primary.withValues(alpha: .10),
          ),
          color: theme.dialogTheme.backgroundColor,
          itemBuilder: (context) => ExtractType.values
              .map(
                (e) => PopupMenuItem(
                  value: e,
                  height: 40,
                  mouseCursor: SystemMouseCursors.click,
                  child: Builder(
                    builder: (context) {
                      bool selected =
                          ref.watch(currentExtractTypeProvider) == e;
                      if (!selected) {
                        return Text(e.label, style: theme.textTheme.bodyMedium);
                      }
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            e.label,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: Colors.blue,
                            ),
                          ),
                          Icon(Icons.check, color: Colors.blue),
                        ],
                      );
                    },
                  ),
                ),
              )
              .toList(),
          onSelected: (value) =>
              ref.read(currentExtractTypeProvider.notifier).update(value),
        ),
        Text(
          '${type.label}${tr(AppI10n.homeExtractTo)}:',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }
}
