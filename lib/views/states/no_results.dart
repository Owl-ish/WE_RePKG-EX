import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:we_repkg/constants/i10n.dart';

class NoResultsView extends StatelessWidget {
  const NoResultsView({super.key});

  static const Key viewKey = ValueKey<String>('no-results');

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color muted = theme.colorScheme.onSurface.withValues(alpha: .55);
    return Center(
      child: Column(
        spacing: 12,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off_rounded, size: 44, color: muted),
          Text(
            tr(AppI10n.homeNoResults),
            style: theme.textTheme.bodyMedium?.copyWith(color: muted),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
