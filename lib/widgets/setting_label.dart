import 'package:flutter/material.dart';
import 'package:we_repkg/config/custom_theme.dart';

class SettingLabel extends StatelessWidget {
  const SettingLabel(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 8),
      child: Text(label, style: Theme.of(context).meta.captionStyle),
    );
  }
}
