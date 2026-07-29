import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:we_repkg/constants/keys.dart';
import 'package:we_repkg/constants/nums.dart';
import 'package:we_repkg/cores/context_menu.dart';
import 'package:we_repkg/models/wallpaper.dart';
import 'package:we_repkg/provider/wallpaper.dart';
import 'package:we_repkg/utils/modifier_keys.dart';
import 'package:we_repkg/utils/storage.dart';
import 'package:we_repkg/views/content/detail_dialog.dart';
import 'package:we_repkg/views/content/hover_hint.dart';
import 'package:we_repkg/views/content/image.dart';
import 'package:we_repkg/views/content/title.dart';

import 'wallpaper_checkbox.dart';

class ImageItem extends ConsumerStatefulWidget {
  const ImageItem({
    super.key,
    required this.width,
    required this.index,
    required this.wallpaper,
  });

  final double width;
  final int index;
  final WallpaperInfo wallpaper;

  @override
  ConsumerState<ImageItem> createState() => _ImageItemState();
}

class _ImageItemState extends ConsumerState<ImageItem>
    with SingleTickerProviderStateMixin {
  /// The last plain left click, so a double click can be told from two separate
  /// clicks. See [_onPointerDown].
  String? _lastClickId;
  DateTime? _lastClickAt;
  AnimationController? _hoverController;
  Animation<double>? _hoverOpacity;
  Animation<double>? _hoverScale;
  bool _hoverHintBuilt = false;
  bool _isHovered = false;

  void _ensureHoverAnimations() {
    if (_hoverController != null) return;
    final AnimationController controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
      reverseDuration: const Duration(milliseconds: 140),
    );
    final Animation<double> opacity = CurvedAnimation(
      parent: controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _hoverController = controller;
    _hoverOpacity = opacity;
    _hoverScale = Tween<double>(begin: 1, end: 1.06).animate(opacity);
  }

  @override
  void dispose() {
    _hoverController?.dispose();
    super.dispose();
  }

  void _onHoverEnter(PointerEnterEvent event) {
    // The hint's icon/text/layout is unnecessary for every cached grid tile at
    // startup. The controller and transform are lazy for the same reason.
    _ensureHoverAnimations();
    if (!_hoverHintBuilt || !_isHovered) {
      setState(() {
        _hoverHintBuilt = true;
        _isHovered = true;
      });
    }
    _hoverController!.forward();
  }

  void _onHoverExit(PointerExitEvent event) {
    if (_isHovered) {
      setState(() => _isHovered = false);
    }
    _hoverController?.reverse();
  }

  /// This tile's rectangle on screen, so the detail dialog can grow out of it.
  Rect? _tileRect() {
    final RenderBox? box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  Future<void> _onPointerDown(PointerDownEvent event) async {
    if (event.buttons != kPrimaryButton || event.localPosition == Offset.zero) {
      return;
    }
    final WallpaperInfo wallpaper = widget.wallpaper;
    if (isCtrlPressed) {
      await StorageUtil.setInt(AppKeys.ctrlPressedIndex, widget.index);
      ref.read(wallpaperListProvider.notifier).toggleChecked(wallpaper);
    } else if (isShiftPressed) {
      int beginIndex = 0, endIndex = widget.index;
      List<WallpaperInfo> list = ref.read(filterWallpaperListProvider);
      List<WallpaperInfo> checkedList = ref.read(checkedWallpaperListProvider);
      if (checkedList.isNotEmpty) {
        beginIndex =
            StorageUtil.getInt(AppKeys.ctrlPressedIndex) ??
            list.indexOf(checkedList.last);
        if (widget.index < beginIndex) {
          endIndex = beginIndex;
          beginIndex = widget.index;
        }
      }
      await StorageUtil.remove(AppKeys.ctrlPressedIndex);
      // The stored anchor index can outlive the list it referred to (changing
      // the filter or the search term reshuffles it), so clamp before slicing
      // rather than letting sublist throw RangeError.
      beginIndex = beginIndex.clamp(0, list.length - 1);
      endIndex = endIndex.clamp(beginIndex, list.length - 1);
      final ids = list
          .sublist(beginIndex, endIndex + 1)
          .map((e) => e.id)
          .toSet();
      ref.read(wallpaperListProvider.notifier).setCheckedByIds(ids, true);
    } else {
      // Plain click: this one only. Ctrl adds, Shift extends.
      //
      // Both clicks of a double click arrive here, because Listener sits
      // outside the gesture arena and never loses to the double tap
      // recogniser. setExclusiveChecked clears the selection when the target is
      // already the only one selected, so running it twice would select on the
      // way down and deselect on the way back up, leaving the detail dialog
      // open over a tile that just blanked its checkbox.
      final DateTime now = DateTime.now();
      final bool isSecondClick =
          _lastClickId == wallpaper.id &&
          _lastClickAt != null &&
          now.difference(_lastClickAt!) < kDoubleTapTimeout;
      _lastClickId = wallpaper.id;
      _lastClickAt = now;

      if (!isSecondClick) {
        ref
            .read(wallpaperListProvider.notifier)
            .setExclusiveChecked(wallpaper.id);
      }
      ref.read(selectedWallpaperProvider.notifier).update(wallpaper);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      key: Key(widget.wallpaper.id),
      onPointerDown: _onPointerDown,
      child: InkWell(
        overlayColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
        splashFactory: NoSplash.splashFactory,
        onDoubleTap: () =>
            showWallpaperDetail(context, widget.wallpaper, origin: _tileRect()),
        onSecondaryTapDown: (details) =>
            showRightMenu(context, details, ref, widget.wallpaper),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: _onHoverEnter,
          onExit: _onHoverExit,
          child: Container(
            key: ValueKey(widget.wallpaper.id),
            width: widget.width,
            decoration: BoxDecoration(
              // The shadow has to know the radius too, or it keeps painting
              // square corners behind the rounded tile.
              borderRadius: BorderRadius.circular(LayoutNums.tileRadius),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: .5),
                  blurRadius: 4,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            // Clips the whole stack at once, so the preview, the hover scrim
            // and the title strip along the bottom all take the same corners.
            child: ClipRRect(
              borderRadius: BorderRadius.circular(LayoutNums.tileRadius),
              clipBehavior: Clip.hardEdge,
              child: Stack(
                children: [
                  ImageView(
                    size: widget.width,
                    wallpaper: widget.wallpaper,
                    scale: _hoverScale,
                  ),
                  if (_hoverHintBuilt) HoverHint(opacity: _hoverOpacity!),
                  ImageTitle(title: widget.wallpaper.title),
                  if (_hoverHintBuilt || widget.wallpaper.checked)
                    IgnorePointer(
                      // Opacity does not affect hit testing. Once the pointer
                      // exits, the fading checkbox must not intercept a click.
                      ignoring: !_isHovered && !widget.wallpaper.checked,
                      child: WallpaperCheckbox(
                        wallpaper: widget.wallpaper,
                        hoverOpacity:
                            _hoverOpacity ??
                            const AlwaysStoppedAnimation<double>(0),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
