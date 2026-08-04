import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:we_repkg/constants/i10n.dart';
import 'package:we_repkg/constants/nums.dart';
import 'package:we_repkg/utils/preview_image.dart';
import 'package:we_repkg/models/error.dart';
import 'package:we_repkg/utils/tool.dart';
import 'package:we_repkg/widgets/app_dialog_surface.dart';

class ErrorView extends StatelessWidget {
  const ErrorView(this.errors, this.cancelFunc, {super.key});

  final List<ErrorInfo> errors;
  final void Function() cancelFunc;

  @override
  Widget build(BuildContext context) {
    // BotToast's layer sits above the Navigator, so the SelectionArea below has
    // no Overlay to reach without this one.
    return Overlay(
      initialEntries: [
        OverlayEntry(
          builder: (context) => Center(child: _buildDialog(context)),
        ),
      ],
    );
  }

  Widget _buildDialog(BuildContext context) {
    final ThemeData theme = Theme.of(context);
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
              tr(AppI10n.dialogErrorTitle),
              style: theme.textTheme.titleLarge?.copyWith(fontSize: 20),
            ),
          ),
          Flexible(child: _errorList()),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(LayoutNums.surfaceRadius),
              mouseCursor: SystemMouseCursors.click,
              onTap: cancelFunc,
              child: Container(
                height: 40,
                width: double.infinity,
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

  Widget _errorList() {
    return ListView.separated(
      itemCount: errors.length,
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemBuilder: (context, index) {
        ErrorInfo err = errors[index];
        if (err.wallpaper == null) {
          List<String> texts = splitOnFirstColon(err.message);
          return ErrorTextInfo(title: texts.first, label: texts.last);
        }

        return Row(
          key: ValueKey(index),
          spacing: 8,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(LayoutNums.controlRadius),
                color: Colors.grey[200],
              ),
              clipBehavior: Clip.hardEdge,
              child: Image(
                image: previewImage(err.wallpaper!.previews),
                width: 80,
                height: 80,
                fit: BoxFit.cover,
                frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                  if (wasSynchronouslyLoaded) return child;
                  return AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: frame != null
                        ? child
                        : const Center(child: CircularProgressIndicator()),
                  );
                },
                errorBuilder: (context, error, stackTrace) =>
                    const Icon(Icons.broken_image_outlined),
              ),
            ),
            Expanded(
              child: ErrorTextInfo(
                title: '${err.wallpaper!.title} (${err.wallpaper!.id})',
                label: err.message,
              ),
            ),
          ],
        );
      },
      separatorBuilder: (context, index) => SizedBox(height: 8),
    );
  }
}

class ErrorTextInfo extends StatelessWidget {
  const ErrorTextInfo({super.key, required this.title, required this.label});
  final String title;
  final String label;

  @override
  Widget build(BuildContext context) {
    ThemeData theme = Theme.of(context);
    return Center(
      child: Column(
        spacing: 2,
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          SelectionArea(
            child: Text(label.trim(), style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
