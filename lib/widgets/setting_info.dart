import 'package:flutter/material.dart';

class SettingInfo extends StatelessWidget {
  const SettingInfo.text({
    super.key,
    required this.title,
    required String content,
  }) : _content = content,
       _child = null;

  const SettingInfo.custom({
    super.key,
    required this.title,
    required Widget child,
  }) : _content = null,
       _child = child;

  final String title;
  final String? _content;
  final Widget? _child;

  @override
  Widget build(BuildContext context) {
    final TextStyle? textStyle = Theme.of(context).textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: _child == null
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        children: [
          Text('$title:', style: textStyle),
          const SizedBox(width: 8),
          _child ?? Text(_content!, style: textStyle),
        ],
      ),
    );
  }
}
