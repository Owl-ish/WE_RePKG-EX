import 'package:flutter/material.dart';
import 'package:we_repkg/widgets/folder_input.dart';

/// A labelled path box with browse beside it, and refresh where there is a
/// default worth going back to. The backup root has none, so it omits it.
class SettingPathInput extends StatelessWidget {
  const SettingPathInput({
    super.key,
    required this.label,
    required this.path,
    required this.hintText,
    required this.onPick,
    this.onRefresh,
  });

  final String label;
  final String? path;
  final String hintText;
  final VoidCallback onPick;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    return Row(
      spacing: 8,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text('$label:', style: Theme.of(context).textTheme.bodyMedium),
        Expanded(
          child: FolderInput(
            height: 32,
            fontSize: 13,
            text: path,
            hintText: hintText,
            onPressed: onPick,
          ),
        ),
        if (onRefresh != null)
          IconButton(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
      ],
    );
  }
}
