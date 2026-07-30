import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data' show ByteData;
// Scoped: an unrestricted dart:ui import collides with material's Image.
import 'dart:ui'
    show
        Codec,
        FrameInfo,
        ImageByteFormat,
        ImageDescriptor,
        ImageFilter,
        ImmutableBuffer,
        TileMode;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:we_repkg/constants/i10n.dart';
import 'package:we_repkg/constants/wallpaper_type.dart';
import 'package:we_repkg/cores/base.dart';
import 'package:we_repkg/cores/extract.dart';
import 'package:we_repkg/models/wallpaper.dart';
import 'package:we_repkg/provider/wallpaper.dart';
import 'package:we_repkg/utils/preview_image.dart';
import 'package:we_repkg/widgets/custom_btn.dart';

import 'wallpaper_meta.dart';

/// What the dialog needs to know about a preview before it opens: the shape to
/// cut itself to, and how bright the strip sitting behind the frosted panel is.
typedef PreviewStats = ({double aspect, double luminance});

final Set<String> _openingWallpaperDetails = <String>{};

/// Tallest the preview pane ever gets, so nothing decodes larger than it draws.
const double _paneMaxHeight = 500;

/// Both panes and the precache have to agree, or they land in different cache
/// slots and the blur flickers partway through the open animation.
ImageProvider<Object> _paneImage(BuildContext context, String path) =>
    previewImage(
      path,
      cacheHeight: (_paneMaxHeight * MediaQuery.devicePixelRatioOf(context))
          .round(),
    );

/// Aspect and mean brightness of [previews], from one cheap 32px decode.
/// Null if the file is missing or unreadable, or takes more than two seconds.
Future<PreviewStats?> _previewStats(String previews) {
  return Future(() async {
    if (previews.isEmpty) return null;
    final File file = File(previews);
    if (!await file.exists()) return null;

    ImageDescriptor? descriptor;
    try {
      final ImmutableBuffer buffer = await ImmutableBuffer.fromUint8List(
        await file.readAsBytes(),
      );
      descriptor = await ImageDescriptor.encoded(buffer);
      final double aspect = descriptor.width / descriptor.height;

      final Codec codec = await descriptor.instantiateCodec(targetWidth: 32);
      final FrameInfo frame = await codec.getNextFrame();
      final ByteData? data = await frame.image.toByteData(
        format: ImageByteFormat.rawRgba,
      );
      final int w = frame.image.width;
      final int h = frame.image.height;
      frame.image.dispose();
      codec.dispose();
      if (data == null) return (aspect: aspect, luminance: .5);

      // Middle 40% of columns only: cover centres its crop, so that is the
      // part of the image the panel actually sits over.
      final int from = (w * .3).floor();
      final int to = (w * .7).ceil().clamp(from + 1, w);
      double total = 0;
      int count = 0;
      for (int y = 0; y < h; y++) {
        for (int x = from; x < to; x++) {
          final int i = (y * w + x) * 4;
          final int r = data.getUint8(i);
          final int g = data.getUint8(i + 1);
          final int b = data.getUint8(i + 2);
          total += (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255;
          count++;
        }
      }
      return (aspect: aspect, luminance: count == 0 ? .5 : total / count);
    } catch (_) {
      return null;
    } finally {
      descriptor?.dispose();
    }
  }).timeout(const Duration(seconds: 2), onTimeout: () => null);
}

/// Opens the details for [wallpaper], growing from [origin] when a grid tile
/// supplies its on-screen rectangle. Other callers open from the window centre.
Future<void> showWallpaperDetail(
  BuildContext context,
  WallpaperInfo wallpaper, {
  Rect? origin,
}) async {
  // Measuring and cache warming happen before the route is pushed, so a second
  // double click in that window would open two overlapping dialogs.
  if (!_openingWallpaperDetails.add(wallpaper.id)) return;
  try {
    await _showWallpaperDetail(context, wallpaper, origin: origin);
  } finally {
    _openingWallpaperDetails.remove(wallpaper.id);
  }
}

Future<void> _showWallpaperDetail(
  BuildContext context,
  WallpaperInfo wallpaper, {
  Rect? origin,
}) async {
  // Measured before opening: doing it inside would resize the dialog
  // mid-animation.
  final PreviewStats? stats = await _previewStats(wallpaper.previews);
  if (!context.mounted) return;

  // The preview and the frosted panel are two Images over one file. Uncached
  // they resolve on separate frames and the blur flickers partway through the
  // open animation.
  if (wallpaper.previews.isNotEmpty) {
    await precacheImage(
      _paneImage(context, wallpaper.previews),
      context,
      // Both widgets have an errorBuilder; failing here would just block.
      onError: (Object error, StackTrace? stack) {},
    );
    if (!context.mounted) return;
  }

  final Size screen = MediaQuery.of(context).size;
  final Alignment from = origin == null
      ? Alignment.center
      : Alignment(
          (origin.center.dx / screen.width) * 2 - 1,
          (origin.center.dy / screen.height) * 2 - 1,
        );

  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: tr(AppI10n.homeDetails),
    // Transparent, so the window behind is not repainted just to dim it.
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 240),
    pageBuilder: (_, _, _) =>
        WallpaperDetailDialog(wallpaper: wallpaper, stats: stats),
    transitionBuilder: (context, animation, _, child) {
      final Animation<double> dialogAnimation = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: dialogAnimation,
        child: ScaleTransition(
          scale: Tween<double>(begin: .35, end: 1).animate(dialogAnimation),
          alignment: from,
          filterQuality: FilterQuality.medium,
          child: RepaintBoundary(child: child),
        ),
      );
    },
  );
}

class WallpaperDetailDialog extends ConsumerStatefulWidget {
  const WallpaperDetailDialog({super.key, required this.wallpaper, this.stats});

  final WallpaperInfo wallpaper;

  /// Shape and brightness of the preview, or null when it couldn't be read.
  final PreviewStats? stats;

  @override
  ConsumerState<WallpaperDetailDialog> createState() =>
      _WallpaperDetailDialogState();
}

class _WallpaperDetailDialogState extends ConsumerState<WallpaperDetailDialog> {
  /// The close button and the membership listener can both fire for one
  /// dismissal, and the second pop would take the route underneath.
  bool _popped = false;

  void _close() {
    if (_popped || !mounted) return;
    _popped = true;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    // Deleting from the buttons below would otherwise leave the dialog showing
    // a wallpaper whose folder is now in the Recycle Bin.
    ref.listen(filterWallpaperListProvider, (_, List<WallpaperInfo> next) {
      if (!next.contains(widget.wallpaper)) _close();
    });

    final Size screen = MediaQuery.of(context).size;

    // Pane takes the image's ratio so cover crops nothing, unless that would
    // push the dialog past the window edge.
    const double panelWidth = 340;
    final double maxWidth = screen.width * .84;
    // Square, not 16/9, when the preview could not be measured: every Wallpaper
    // Engine preview is square, so a wide fallback is the odd one out.
    final double aspect = widget.stats?.aspect ?? 1;
    final double height = min(screen.height * .72, _paneMaxHeight);
    double previewWidth = height * aspect;
    if (previewWidth + panelWidth > maxWidth) {
      previewWidth = maxWidth - panelWidth;
    }
    final double width = previewWidth + panelWidth;

    // Text follows the panel's target brightness, not the wallpaper's, since
    // the panel corrects every wallpaper towards that target anyway.
    const bool onDark = _GlassPanel.panelLuminance < .5;
    const Color foreground = onDark ? Colors.white : Color(0xFF101010);

    return Dialog(
      backgroundColor: Colors.transparent,
      // Material's default shadow re-rasterizes during the scale transition and
      // flashes along the edges on Windows.
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: width,
        height: height,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: previewWidth,
              child: _Preview(wallpaper: widget.wallpaper),
            ),
            SizedBox(
              width: panelWidth,
              child: _GlassPanel(
                wallpaper: widget.wallpaper,
                onDark: onDark,
                luminance: widget.stats?.luminance ?? .5,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 12, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: Alignment.centerRight,
                        child: IconButton(
                          onPressed: _close,
                          icon: Icon(Icons.close_rounded, color: foreground),
                          tooltip: tr(AppI10n.close),
                        ),
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          child: WallpaperMeta(
                            wallpaper: widget.wallpaper,
                            copyable: true,
                            foreground: foreground,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _Actions(wallpaper: widget.wallpaper),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Frosted pane: its own copy of the wallpaper, blurred, under a scrim.
///
/// Its own copy rather than a shared full-bleed one, which would have to cover
/// the whole dialog and crop the preview. Blurred past recognition anyway, so
/// this copy can crop freely.
class _GlassPanel extends StatelessWidget {
  const _GlassPanel({
    required this.wallpaper,
    required this.onDark,
    required this.luminance,
    required this.child,
  });

  final WallpaperInfo wallpaper;

  final bool onDark;

  /// Mean brightness of the wallpaper behind this pane, 0 to 1.
  final double luminance;

  final Widget child;

  /// Brightness every panel is corrected towards, so the dialog doesn't change
  /// character with each wallpaper. Below .5 the text flips to white.
  static const double panelLuminance = .7;

  /// 0 is greyscale, 1 untouched. Low enough that a strongly coloured wallpaper
  /// doesn't stain the panel.
  static const double _saturation = .55;

  static const double _scrimOpacity = .25;
  static const double _blurSigma = 35;

  /// Desaturate and shift brightness, as a 4x5 colour matrix. Luma weights
  /// match [_previewStats], so only [lift] moves the measured brightness.
  static List<double> _correction(double saturation, double lift) {
    const double lr = .2126, lg = .7152, lb = .0722;
    final double s = saturation;
    final double ir = (1 - s) * lr;
    final double ig = (1 - s) * lg;
    final double ib = (1 - s) * lb;
    final double o = lift * 255;
    return <double>[
      ir + s, ig, ib, 0, o, //
      ir, ig + s, ib, 0, o, //
      ir, ig, ib + s, 0, o, //
      0, 0, 0, 1, 0, //
    ];
  }

  @override
  Widget build(BuildContext context) {
    final Color tint = onDark ? Colors.black : Colors.white;
    // Clamped, or a nearly black wallpaper washes out to flat grey.
    final double lift = (panelLuminance - luminance).clamp(-.35, .45);

    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // ImageFiltered, not BackdropFilter: a backdrop filter's kernel
          // reaches outside its own bounds, where nothing valid exists while
          // the dialog is scaling open, and the edges churn. TileMode.clamp
          // keeps the border clean without overscaling past the clip.
          ImageFiltered(
            imageFilter: ImageFilter.blur(
              sigmaX: _blurSigma,
              sigmaY: _blurSigma,
              tileMode: TileMode.clamp,
            ),
            child: ColorFiltered(
              colorFilter: ColorFilter.matrix(_correction(_saturation, lift)),
              child: Image(
                image: _paneImage(context, wallpaper.previews),
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    ColoredBox(color: tint),
              ),
            ),
          ),
          Container(
            key: const ValueKey<String>('wallpaper-detail-panel-scrim'),
            decoration: BoxDecoration(
              color: tint.withValues(alpha: _scrimOpacity),
            ),
            child: child,
          ),
        ],
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.wallpaper});

  final WallpaperInfo wallpaper;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      // cover, not contain: the pane takes the preview's own ratio, so cover
      // crops nothing until the dialog is clamped to the window width.
      child: Image(
        image: _paneImage(context, wallpaper.previews),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) =>
            const Center(child: Icon(Icons.broken_image, size: 64)),
      ),
    );
  }
}

class _Actions extends ConsumerWidget {
  const _Actions({required this.wallpaper});

  final WallpaperInfo wallpaper;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      key: const ValueKey<String>('wallpaper-detail-actions'),
      padding: const EdgeInsets.only(bottom: _DetailActionLayout.bottomInset),
      child: Column(
        spacing: _DetailActionLayout.spacing,
        children: [
          _DetailActionButton(
            onPressed: () => extractCurrent(ref, wallpaper),
            label: tr(AppI10n.homeExtractCurrent),
          ),
          if (wallpaper.type == WallpaperType.scene)
            _DetailActionButton(
              onPressed: () => extractProject(ref, [wallpaper]),
              label: tr(AppI10n.homeExtractForProject),
            ),
          if (wallpaper.type == WallpaperType.video)
            _DetailActionButton(
              onPressed: () => playVideo(wallpaper),
              label: tr(AppI10n.homePlayVideo),
            ),
          _DetailActionButton(
            onPressed: () => browserCurrent(wallpaper),
            label: tr(AppI10n.homeOpenFileLocation),
          ),
          _DetailActionButton.destructive(
            // No pop: the membership listener closes the dialog once the
            // wallpaper leaves the list. Popping here would beat the confirm
            // prompt.
            onPressed: () async => await deleteCurrent(ref, wallpaper),
            label: tr(AppI10n.homeDeleteCurrent),
          ),
        ],
      ),
    );
  }
}

abstract final class _DetailActionLayout {
  static const double width = 170;
  static const double height = 34;
  static const double spacing = 10;
  static const double bottomInset = 14;
}

class _DetailActionButton extends StatelessWidget {
  const _DetailActionButton({required this.label, required this.onPressed})
    : _destructive = false;

  const _DetailActionButton.destructive({
    required this.label,
    required this.onPressed,
  }) : _destructive = true;

  final String label;
  final VoidCallback onPressed;
  final bool _destructive;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => Align(
        child: SizedBox(
          width: min(_DetailActionLayout.width, constraints.maxWidth),
          height: _DetailActionLayout.height,
          child: _destructive
              ? CustomBtn.destructive(onPressed: onPressed, label: label)
              : CustomBtn(onPressed: onPressed, label: label),
        ),
      ),
    );
  }
}
