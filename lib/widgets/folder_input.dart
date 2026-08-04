import 'package:flutter/material.dart';
import 'package:we_repkg/widgets/app_icon_button.dart';

import 'custom_input.dart';

/// A read-only path box with a browse button beside it.
///
/// Owns its controller rather than taking one. Every caller used to build a
/// fresh `TextEditingController` inside `build`, so choosing a folder handed the
/// TextField a different controller and threw away its editable subtree, taking
/// a batch of accessibility nodes with it. None of them were ever disposed
/// either.
class FolderInput extends StatefulWidget {
  const FolderInput({
    super.key,
    this.width,
    this.height,
    required this.text,
    this.fontSize,
    required this.hintText,
    required this.onPressed,
  });

  final double? width;
  final double? height;
  final String? text;
  final double? fontSize;
  final String hintText;
  final void Function() onPressed;

  @override
  State<FolderInput> createState() => _FolderInputState();
}

class _FolderInputState extends State<FolderInput> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.text ?? '',
  );

  @override
  void didUpdateWidget(FolderInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    final String next = widget.text ?? '';
    if (_controller.text != next) _controller.text = next;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomInput(
      width: widget.width,
      height: widget.height,
      controller: _controller,
      padding: const EdgeInsets.only(left: 8),
      fontSize: widget.fontSize,
      readOnly: true,
      hintText: widget.hintText,
      extraIcon: Container(
        width: 1,
        height: 20,
        color: Theme.of(context).dividerColor,
      ),
      suffix: AppIconButton(
        icon: Icons.folder_open_rounded,
        onPressed: widget.onPressed,
      ),
    );
  }
}
