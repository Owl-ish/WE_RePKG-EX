import 'package:flutter/material.dart';
import 'package:we_repkg/widgets/folder_input.dart';

/// A labelled path box with browse and refresh beside it.
class SettingPathInput extends StatelessWidget {
  const SettingPathInput({
    super.key,
    required this.label,
    required this.path,
    required this.hintText,
    required this.onPick,
    required this.onRefresh,
  });

  final String label;
  final String? path;
  final String hintText;
  final VoidCallback onPick;
  final VoidCallback onRefresh;

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
        IconButton(
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    );
  }
}
