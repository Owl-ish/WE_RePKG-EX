import 'dart:async';

import 'package:bot_toast/bot_toast.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:we_repkg/config/custom_theme.dart';
import 'package:we_repkg/constants/i10n.dart';
import 'package:we_repkg/widgets/app_dialog_surface.dart';

/// Asks before something destructive, resolving true only if the user confirms.
///
/// Deleting moves folders to the Recycle Bin, which is recoverable but still a
/// nuisance to undo across a large selection, and the delete button sits right
/// beside the extract buttons.
Future<bool> showConfirmDialog({
  required String title,
  required String message,
  String? confirmLabel,
  bool destructive = true,
}) {
  final completer = Completer<bool>();
  late final CancelFunc close;

  void finish(bool value) {
    if (completer.isCompleted) return;
    completer.complete(value);
    close();
  }

  close = BotToast.showCustomLoading(
    backgroundColor: Colors.black.withValues(alpha: .6),
    // Clicking the backdrop is a dismissal, which for a destructive prompt has
    // to mean "no".
    clickClose: true,
    onClose: () => finish(false),
    toastBuilder: (_) => _ConfirmDialog(
      title: title,
      message: message,
      confirmLabel: confirmLabel ?? tr(AppI10n.confirm),
      destructive: destructive,
      onResult: finish,
    ),
  );

  return completer.future;
}

class _ConfirmDialog extends StatelessWidget {
  const _ConfirmDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.destructive,
    required this.onResult,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final bool destructive;
  final void Function(bool) onResult;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final actionColors = theme.actionButtons;
    return AppDialogSurface(
      width: 420,
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleLarge?.copyWith(fontSize: 18),
          ),
          const SizedBox(height: 12),
          Text(message, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => onResult(false),
                child: Text(tr(AppI10n.cancel)),
              ),
              const SizedBox(width: 8),
              FilledButton(
                style: destructive
                    ? FilledButton.styleFrom(
                        backgroundColor: actionColors.destructiveBackground,
                        foregroundColor: actionColors.destructiveForeground,
                        side: BorderSide(color: actionColors.destructiveBorder),
                      )
                    : null,
                onPressed: () => onResult(true),
                child: Text(confirmLabel),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
