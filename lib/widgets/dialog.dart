import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:we_repkg/constants/i10n.dart';
import 'package:we_repkg/widgets/app_dialog_surface.dart';

class DialogView extends StatelessWidget {
  const DialogView({
    super.key,
    required this.title,
    required this.content,
    required this.onClose,
  });

  final String title;
  final Widget content;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    ThemeData theme = Theme.of(context);
    return AppDialogSurface(
      width: 600,
      maxHeight: MediaQuery.of(context).size.height * .9,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 48,
            alignment: Alignment.center,
            child: Text(
              title,
              style: theme.textTheme.titleLarge?.copyWith(fontSize: 20),
            ),
          ),
          Flexible(child: content),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              mouseCursor: SystemMouseCursors.click,
              onTap: onClose,
              child: Container(
                height: 40,
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Text(
                  tr(AppI10n.close),
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
