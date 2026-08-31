import 'dart:async';

import 'package:bot_toast/bot_toast.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:we_repkg/config/theme_extensions.dart';
import 'package:we_repkg/constants/i10n.dart';
import 'package:we_repkg/constants/nums.dart';
import 'package:we_repkg/widgets/app_dialog_surface.dart';
import 'package:we_repkg/widgets/input_controls.dart';

typedef ConfirmDetail = ({String label, String value});
typedef ConfirmPathDetail = ({
  String label,
  String path,
  String copyTooltip,
  String openTooltip,
  FutureOr<void> Function()? onOpen,
});

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
  List<ConfirmDetail> details = const <ConfirmDetail>[],
  List<ConfirmPathDetail> pathDetails = const <ConfirmPathDetail>[],
}) {
  final completer = Completer<bool>();
  late final CancelFunc close;
  bool closing = false;
  bool? requestedResult;

  // Resolve only after BotToast has actually removed the overlay. Callers may
  // immediately replace the widget tree after awaiting this Future, so
  // completing before the close animation finishes can leave BotToast holding
  // a stale navigator host.
  void finish(bool value) {
    if (completer.isCompleted || closing) return;
    closing = true;
    requestedResult = value;
    close();
  }

  void finishClose() {
    if (completer.isCompleted) return;
    completer.complete(requestedResult ?? false);
  }

  close = BotToast.showCustomLoading(
    backgroundColor: Colors.black.withValues(alpha: .6),
    // Clicking the backdrop is a dismissal, which for a destructive prompt has
    // to mean "no".
    clickClose: true,
    onClose: finishClose,
    toastBuilder: (_) => _ConfirmDialog(
      title: title,
      message: message,
      confirmLabel: confirmLabel ?? tr(AppI10n.confirm),
      destructive: destructive,
      details: details,
      pathDetails: pathDetails,
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
    required this.details,
    required this.pathDetails,
    required this.onResult,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final bool destructive;
  final List<ConfirmDetail> details;
  final List<ConfirmPathDetail> pathDetails;
  final void Function(bool) onResult;

  static const double _width = 600;
  static const double _messageMaxHeight = 280;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ActionButtonTheme actions = theme.actionButtons;
    final Color accent = destructive
        ? actions.destructiveForeground
        : actions.primaryForeground;
    final Color accentBackground = destructive
        ? actions.destructiveBackground
        : actions.primaryBackground;
    final Color accentBorder = destructive
        ? actions.destructiveBorder
        : actions.primaryBorder;
    return AppDialogSurface(
      width: _width,
      padding: const EdgeInsets.all(LayoutNums.edgeInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          AppDialogHeader(
            icon: destructive
                ? Icons.delete_outline_rounded
                : Icons.auto_fix_high_rounded,
            title: title,
            foreground: accent,
            background: accentBackground,
          ),
          const SizedBox(height: LayoutNums.largeGap),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: _messageMaxHeight),
            padding: const EdgeInsets.all(LayoutNums.largeGap),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: .55,
              ),
              border: Border.all(
                color: theme.dividerColor.withValues(alpha: .35),
              ),
              borderRadius: BorderRadius.circular(LayoutNums.surfaceRadius),
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    message,
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
                  ),
                  for (final ConfirmDetail detail in details) ...<Widget>[
                    const SizedBox(height: LayoutNums.mediumGap),
                    Text(
                      detail.label,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: LayoutNums.tinyGap),
                    Container(
                      width: double.infinity,
                      height: LayoutNums.controlHeight,
                      padding: const EdgeInsets.symmetric(
                        horizontal: LayoutNums.mediumGap,
                      ),
                      alignment: Alignment.centerLeft,
                      decoration: BoxDecoration(
                        color: accentBackground,
                        border: Border.all(color: accentBorder),
                        borderRadius: LayoutNums.pill,
                      ),
                      child: Text(
                        detail.value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontFamily: 'Consolas',
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                  for (final ConfirmPathDetail detail
                      in pathDetails) ...<Widget>[
                    const SizedBox(height: LayoutNums.mediumGap),
                    Text(
                      detail.label,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: LayoutNums.tinyGap),
                    PathActionBox(
                      path: detail.path,
                      copyTooltip: detail.copyTooltip,
                      openTooltip: detail.openTooltip,
                      onOpen: detail.onOpen,
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: LayoutNums.sectionGap),
          SizedBox(
            width: double.infinity,
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: LayoutNums.smallGap,
              runSpacing: LayoutNums.smallGap,
              children: <Widget>[
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(88, LayoutNums.controlHeight),
                  ),
                  onPressed: () => onResult(false),
                  child: Text(tr(AppI10n.cancel)),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(88, LayoutNums.controlHeight),
                    backgroundColor: accentBackground,
                    foregroundColor: accent,
                    side: BorderSide(color: accentBorder),
                  ),
                  onPressed: () => onResult(true),
                  child: Text(confirmLabel),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
