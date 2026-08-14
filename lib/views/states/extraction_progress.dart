import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:we_repkg/models/wallpaper.dart';
import 'package:we_repkg/utils/preview_image.dart';
import 'package:we_repkg/provider/system.dart';
import 'package:we_repkg/provider/wallpaper.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:we_repkg/constants/i10n.dart';
import 'package:we_repkg/constants/nums.dart';
import 'package:we_repkg/widgets/ellipsis_animation_text.dart';
import 'package:we_repkg/widgets/progress_bar.dart';

class ExtractionProgressPanel extends ConsumerStatefulWidget {
  const ExtractionProgressPanel(this.list, {super.key});

  final List<WallpaperInfo> list;

  @override
  ConsumerState<ExtractionProgressPanel> createState() =>
      _ExtractionProgressPanelState();
}

class _ExtractionProgressPanelState
    extends ConsumerState<ExtractionProgressPanel>
    with TickerProviderStateMixin {
  static const Duration _imageTransition = Duration(milliseconds: 500);
  static const Duration _textTransition = Duration(milliseconds: 300);
  static const double _panelWidth = 520;
  static const double _panelMinHeight = 360;
  static const double _previewSize = 160;
  static const double _elevation = 2;
  static const double _cancelIconSize = 18;

  late AnimationController _imageController;
  late Animation<double> _imageAnimation;
  late AnimationController _textController;
  late Animation<double> _textAnimation;
  String? _previousId;

  @override
  void initState() {
    super.initState();
    _imageController = AnimationController(
      duration: _imageTransition,
      vsync: this,
    );
    _imageAnimation = CurvedAnimation(
      parent: _imageController,
      curve: Curves.easeInOut,
    );

    _textController = AnimationController(
      duration: _textTransition,
      vsync: this,
    );
    _textAnimation = CurvedAnimation(
      parent: _textController,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _imageController.dispose();
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    if (widget.list.isEmpty) return const SizedBox.shrink();
    final int total = widget.list.length;
    // Completed count, not a cursor. Extraction runs several wallpapers at once
    // now, so this reaches total and indexing widget.list with it would throw.
    final int completed = ref.watch(currentIndexProvider);
    final double newProgress = total > 0 ? completed / total : 0;
    // Preview follows whichever wallpaper a worker picked up most recently, and
    // falls back to the first entry before the batch starts.
    final WallpaperInfo current =
        ref.watch(processingWallpaperProvider) ?? widget.list.first;

    // 进度和壁纸各自触发动画: 一次只提取一张壁纸时预览图不会变化,
    // 若共用同一个条件, 进度条将永远停在起点
    if (_previousId != current.id) {
      _previousId = current.id;
      _imageController.forward(from: 0);
      _textController.forward(from: 0);
    }
    return Material(
      elevation: _elevation,
      borderRadius: BorderRadius.circular(LayoutNums.surfaceRadius),
      color: theme.scaffoldBackgroundColor,
      child: Container(
        width: _panelWidth,
        // minHeight, not a fixed height: the cancel button pushed the column
        // past 360 and clipped it.
        constraints: const BoxConstraints(minHeight: _panelMinHeight),
        padding: const EdgeInsets.all(LayoutNums.largeGap),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(LayoutNums.surfaceRadius),
        ),
        // No `alignment` here. A Container with one set expands to fill its
        // parent, which with the fixed height gone stretched the panel down the
        // whole window. Without it the box hugs the column and honours
        // minHeight.
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: LayoutNums.largeGap,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ScaleTransition(
              scale: _imageAnimation,
              child: FadeTransition(
                opacity: _imageAnimation,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(LayoutNums.surfaceRadius),
                  child: Image(
                    image: previewImage(current.previews),
                    key: ValueKey(current.id),
                    width: _previewSize,
                    height: _previewSize,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
            // 省略号动画文字
            EllipsisAnimationText(text: ref.watch(loadingTextProvider)),
            ScaleTransition(
              scale: _textAnimation,
              child: FadeTransition(
                opacity: _textAnimation,
                child: Text(
                  current.title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.primaryColor,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            // 添加带动画效果的进度条
            ProgressBar(value: newProgress, colour: theme.primaryColor),
            ScaleTransition(
              scale: _textAnimation,
              child: FadeTransition(
                opacity: _textAnimation,
                child: Text(
                  '$completed / $total',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ),
            // Cancelling stops workers claiming new wallpapers and kills the
            // RePKG process currently running. Disabled once it has been hit,
            // since whatever is already in flight still has to finish.
            Builder(
              builder: (context) {
                final token = ref.watch(activeCancelTokenProvider);
                final bool cancelled = token?.isCancelled ?? false;
                return TextButton.icon(
                  onPressed: token == null || cancelled
                      ? null
                      : () {
                          token.cancel();
                          setState(() {});
                        },
                  icon: const Icon(Icons.close_rounded, size: _cancelIconSize),
                  label: Text(
                    cancelled
                        ? tr(AppI10n.dialogCancelled)
                        : tr(AppI10n.cancel),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
