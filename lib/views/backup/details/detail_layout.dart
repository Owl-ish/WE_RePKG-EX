import 'package:flutter/material.dart';

/// Compact title-and-items block shared by Backup detail states.
class BackupDetailGroup extends StatelessWidget {
  const BackupDetailGroup({
    super.key,
    required this.title,
    required this.items,
    required this.foreground,
  });

  final String title;
  final List<String> items;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: TextStyle(color: foreground, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          for (final String item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                '• $item',
                style: TextStyle(color: foreground, height: 1.3),
              ),
            ),
        ],
      ),
    );
  }
}
