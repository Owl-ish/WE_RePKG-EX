import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:we_repkg/cores/toast.dart';
import 'package:we_repkg/widgets/app_icon_button.dart';

class CopyBtn extends StatelessWidget {
  const CopyBtn({super.key, required this.text, this.size = 16, this.color});

  final String text;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2.0),
      child: AppIconButton(
        icon: Icons.copy_outlined,
        width: size + 8,
        height: size + 8,
        iconSize: size,
        color: color,
        onPressed: () {
          Clipboard.setData(ClipboardData(text: text));
          showCopyToast();
        },
      ),
    );
  }
}
