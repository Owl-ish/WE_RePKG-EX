import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:we_repkg/models/wallpaper.dart';
import 'package:we_repkg/utils/preview_image.dart';
import 'package:we_repkg/provider/system.dart';
import 'package:we_repkg/provider/wallpaper.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:we_repkg/constants/i10n.dart';
import 'package:we_repkg/widgets/ellipsis_animation_text.dart';

class LoadingView extends ConsumerStatefulWidget {
  const LoadingView(this.list, {super.key});

  final List<WallpaperInfo> list;

  @override
  ConsumerState<LoadingView> createState() => _LoadingViewState();
}

class _LoadingViewState extends ConsumerState<LoadingView>
    with TickerProviderStateMixin {
  late AnimationController _imageController;
  late Animation<double> _imageAnimation;
  late AnimationController _textController;
  late Animation<double> _textAnimation;
  late AnimationController _progressController;
  late Animation<double> _progressAnimation;
  String? _previousId;

  @override
  void initState() {
    super.initState();
    _imageController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _imageAnimation = CurvedAnimation(
      parent: _imageController,
      curve: Curves.easeInOut,
    );

    _textController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _textAnimation = CurvedAnimation(
      parent: _textController,
      curve: Curves.easeInOut,
    );

    _progressController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _progressAnimation = CurvedAnimation(
      parent: _progressController,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _imageController.dispose();
    _textController.dispose();
    _progressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ThemeData theme = Theme.of(context);
    if (widget.list.isEmpty) return const SizedBox.shrink();
    int total = widget.list.length;
    // Completed count, not a cursor. Extraction runs several wallpapers at once
    // now, so this reaches total and indexing widget.list with it would throw.
    int completed = ref.watch(currentIndexProvider);
    double newProgress = total > 0 ? completed / total : 0;
    // Preview follows whichever wallpaper a worker picked up most recently, and
    // falls back to the first entry before the batch starts.
    final WallpaperInfo current =
        ref.watch(processingWallpaperProvider) ?? widget.list.first;

    // 进度和壁纸各自触发动画: 一次只提取一张壁纸时预览图不会变化,
    // 若共用同一个条件, 进度条将永远停在起点
    if (_progressController.value != newProgress) {
      _progressController.animateTo(
        newProgress,
        duration: const Duration(milliseconds: 500),
      );
    }
    if (_previousId != current.id) {
      _previousId = current.id;
      _imageController.forward(from: 0);
      _textController.forward(from: 0);
    }
    return Material(
      elevation: 2,
      borderRadius: BorderRadius.circular(8),
      color: theme.scaffoldBackgroundColor,
      child: Container(
        width: 520,
        // minHeight, not a fixed height: the cancel button pushed the column
        // past 360 and clipped it.
        constraints: const BoxConstraints(minHeight: 360),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          // color: Colors.white,
          borderRadius: BorderRadius.circular(8),
        ),
        // No `alignment` here. A Container with one set expands to fill its
        // parent, which with the fixed height gone stretched the panel down the
        // whole window. Without it the box hugs the column and honours
        // minHeight.
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 16,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ScaleTransition(
              scale: _imageAnimation,
              child: FadeTransition(
                opacity: _imageAnimation,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image(
                    image: previewImage(current.previews),
                    key: ValueKey(current.id),
                    width: 160,
                    height: 160,
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
                  style: TextStyle(
                    color: Colors.blue,
                    fontSize: 14,
                    fontFamily: 'Microsoft YaHei',
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            // 添加带动画效果的进度条
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: AnimatedBuilder(
                animation: _progressAnimation,
                builder: (context, child) {
                  return LinearProgressIndicator(
                    value: _progressAnimation.value,
                    minHeight: 8,
                    color: Colors.blue,
                    backgroundColor: Colors.grey[200],
                  );
                },
              ),
            ),
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
                  icon: const Icon(Icons.close_rounded, size: 18),
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
