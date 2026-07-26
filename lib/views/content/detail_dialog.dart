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
import 'package:we_repkg/widgets/custom_btn.dart';

import 'wallpaper_meta.dart';

/// What the dialog needs to know about a preview before it opens: the shape to
/// cut itself to, and how bright the strip sitting behind the frosted panel is.
typedef PreviewStats = ({double aspect, double luminance});

final Set<String> _openingWallpaperDetails = <String>{};

/// Measures [previews] from a 32px decode.
///
/// Two things come out of one cheap decode. The aspect lets the dialog match
/// the image instead of cropping it, and the luminance decides whether the
/// panel's text goes light or dark, which fixed theme colours can't do over an
/// arbitrary wallpaper.
///
/// Returns null for a missing or unreadable file, and gives up after two
/// seconds rather than leaving a double click with nothing to show.
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

      // 32px across is far more than averaging a colour needs, and decoding
      // that is close to free even for a 4K preview.
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

      // Sample the middle 40% of columns, because BoxFit.cover centres its
      // crop: a tall narrow panel over a landscape preview shows the middle of
      // the image, not the end nearest the panel.
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
  // Preview inspection and cache warming happen before the route is pushed.
  // Ignore a second activation during that window and while this wallpaper's
  // dialog is already open, otherwise two routes and barriers briefly overlap.
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
  // Resolved before opening rather than inside the dialog: measuring after the
  // first frame would resize the dialog mid-animation and repaint its text.
  final PreviewStats? stats = await _previewStats(wallpaper.previews);
  if (!context.mounted) return;

  // Warm the image cache before the route is pushed.
  //
  // The sharp preview and the frosted panel are two Image widgets over one
  // file. Uncached they resolve on separate frames, so the panel's backdrop
  // arrives after the preview and the blur flickers partway through the open
  // animation. _previewStats doesn't help: it decodes through ImageDescriptor,
  // which never touches the ImageCache that FileImage reads.
  if (wallpaper.previews.isNotEmpty) {
    await precacheImage(
      FileImage(File(wallpaper.previews)),
      context,
      // A preview that fails to load is already handled by both widgets'
      // errorBuilder; failing here would just block the dialog.
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
    // Retain outside-click dismissal without visually darkening or repainting
    // the main window behind the dialog.
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
  /// Guards against popping twice. The membership listener and the close button
  /// can both fire for the same dismissal, and the second pop would take the
  /// route underneath this one.
  bool _popped = false;

  void _close() {
    if (_popped || !mounted) return;
    _popped = true;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    // Close as soon as the wallpaper leaves the visible list. Deleting from the
    // buttons below moves the folder to the Recycle Bin, and without this the
    // dialog stays up rendering a preview whose file is gone, with a delete
    // button that now points at a missing path. Filtering and searching while
    // the dialog is open land here too.
    ref.listen(filterWallpaperListProvider, (_, List<WallpaperInfo> next) {
      if (!next.contains(widget.wallpaper)) _close();
    });

    final Size screen = MediaQuery.of(context).size;

    // Shape the preview pane to the image rather than the other way round: at a
    // pane matching the file's own ratio, cover crops nothing and there are no
    // bars to hide. Only when that would push the dialog past the window does
    // the pane get squared off and give up a few percent to the crop.
    const double panelWidth = 340;
    final double maxWidth = screen.width * .84;
    final double aspect = widget.stats?.aspect ?? 16 / 9;
    final double height = min(screen.height * .72, 500);
    double previewWidth = height * aspect;
    if (previewWidth + panelWidth > maxWidth) {
      previewWidth = maxWidth - panelWidth;
    }
    final double width = previewWidth + panelWidth;

    // The panel normalises every wallpaper to the same brightness, so the text
    // colour follows that target rather than the wallpaper it sits on. Lower
    // _GlassPanel.panelLuminance past .5 and the text flips to white on its own.
    const bool onDark = _GlassPanel.panelLuminance < .5;
    const Color foreground = onDark ? Colors.white : Color(0xFF101010);

    return Dialog(
      backgroundColor: Colors.transparent,
      // A transparent Dialog still inherits Material's default elevation.
      // Its shadow is strongest on the right and bottom, and re-rasterizing
      // that shadow during the scale transition produces a visible edge flash
      // on Windows.
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      // The wallpaper runs edge to edge underneath, so the rounded corners have
      // to clip the image rather than a panel colour sitting on top of it.
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
/// It carries its own backdrop rather than blurring a full-bleed image shared
/// with the preview, because a shared image would have to cover the whole
/// dialog and that is what was cropping the preview. This copy is blurred past
/// recognition, so it can crop freely.
class _GlassPanel extends StatelessWidget {
  const _GlassPanel({
    required this.wallpaper,
    required this.onDark,
    required this.luminance,
    required this.child,
  });

  final WallpaperInfo wallpaper;

  /// Whether the finished panel is dark. Follows [panelLuminance], not the
  /// wallpaper, since the backdrop is normalised to that target either way.
  final bool onDark;

  /// Mean brightness of the wallpaper strip behind this pane, 0 to 1. The gap
  /// between this and [panelLuminance] is what gets corrected out.
  final double luminance;

  final Widget child;

  /// Brightness every panel is pulled towards, 0 to 1.
  ///
  /// Without this a dark red wallpaper made a dark red panel and a pale one
  /// made a pale panel, so the dialog changed character with every wallpaper.
  /// Correcting each backdrop to a common target keeps the panel consistent
  /// and easy on the eyes while the silhouette still shows through. Raise for
  /// a lighter panel; below .5 the text flips to white on its own.
  static const double panelLuminance = .7;

  /// How much of the wallpaper's colour survives, 0 to 1. 0 is greyscale, 1 is
  /// untouched. Low values are what stop a strongly coloured wallpaper from
  /// staining the whole panel; the blurred shapes come through regardless,
  /// because desaturating leaves brightness alone.
  static const double _saturation = .55;

  /// How much flat tint sits over the corrected backdrop. Kept low so the
  /// silhouette survives; legibility comes from the text colour and its halo.
  static const double _scrimOpacity = .25;

  /// Higher is blurrier and flatter. Around 15 leaves shapes recognisable.
  static const double _blurSigma = 35;

  /// Desaturate by [saturation] and shift brightness by [lift], as a 4x5 colour
  /// matrix. The luma weights match the ones [_previewStats] measures with, so
  /// desaturation leaves the measured brightness untouched and only [lift]
  /// moves it.
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
    // Clamped: a nearly black wallpaper lifted all the way to the target washes
    // out to flat grey and loses the silhouette that makes this worth doing.
    final double lift = (panelLuminance - luminance).clamp(-.35, .45);

    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // ImageFiltered, not BackdropFilter.
          //
          // BackdropFilter blurs whatever the layer beneath it painted, and its
          // kernel reaches about 2x sigma outside its own bounds. While the
          // dialog scales open there is nothing valid out there, so the top and
          // right edges churned frame to frame. This pane owns its backdrop
          // rather than borrowing one, so the image can be blurred directly and
          // the filter never looks outside this subtree.
          //
          // TileMode.clamp extends the edge pixels instead of fading to
          // transparent, which is what keeps the border clean without having to
          // overscale the image past the clip.
          ImageFiltered(
            imageFilter: ImageFilter.blur(
              sigmaX: _blurSigma,
              sigmaY: _blurSigma,
              tileMode: TileMode.clamp,
            ),
            child: ColorFiltered(
              colorFilter: ColorFilter.matrix(_correction(_saturation, lift)),
              child: Image.file(
                File(wallpaper.previews),
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
      // cover, not contain: contain letterboxed a 16:9 preview inside a nearly
      // square pane and put black bars down both sides. Filling the dialog
      // costs a crop off the top and bottom, and the grid tile is the place
      // that already shows the whole frame.
      //
      // No cacheWidth either: a single image at the largest size the app ever
      // draws it is what a full resolution decode is for.
      child: Image.file(
        File(wallpaper.previews),
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
            // No pop here: deleteCurrent drops the wallpaper from the list, and
            // the membership listener closes the dialog. Popping as well would
            // close it before the confirm prompt is answered.
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
