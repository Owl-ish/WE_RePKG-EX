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

/// One button down the right of the dialog.
class DetailAction {
  const DetailAction({
    required this.label,
    required this.onPressed,
    this.destructive = false,
  });

  const DetailAction.destructive({required this.label, required this.onPressed})
    : destructive = true;

  final String label;
  final VoidCallback onPressed;
  final bool destructive;
}

/// Extra caller-owned content inside the normal metadata panel.
/// Kept optional so ordinary wallpaper details are unchanged.
typedef DetailExtraBuilder =
    Widget Function(BuildContext context, Color foreground);

/// Opens the details for [wallpaper], growing from [origin] when a grid tile
/// supplies its on-screen rectangle. Other callers open from the window centre.
///
/// [actions] replaces the extract buttons, for a caller whose wallpaper is not
/// in the extract grid's library.
Future<void> showWallpaperDetail(
  BuildContext context,
  WallpaperInfo wallpaper, {
  Rect? origin,
  List<DetailAction>? actions,
  DetailExtraBuilder? extraContentBuilder,
  bool includePreview = true,
}) async {
  // Measuring and cache warming happen before the route is pushed, so a second
  // double click in that window would open two overlapping dialogs.
  if (!_openingWallpaperDetails.add(wallpaper.id)) return;
  try {
    await _showWallpaperDetail(
      context,
      wallpaper,
      origin: origin,
      actions: actions,
      extraContentBuilder: extraContentBuilder,
      includePreview: includePreview,
    );
  } finally {
    _openingWallpaperDetails.remove(wallpaper.id);
  }
}

Future<void> _showWallpaperDetail(
  BuildContext context,
  WallpaperInfo wallpaper, {
  Rect? origin,
  List<DetailAction>? actions,
  DetailExtraBuilder? extraContentBuilder,
  required bool includePreview,
}) async {
  // Measured before opening: doing it inside would resize the dialog
  // mid-animation. Callers that have no useful preview skip the decode entirely.
  final PreviewStats? stats = includePreview
      ? await _previewStats(wallpaper.previews)
      : null;
  if (!context.mounted) return;

  // The preview and the frosted panel are two Images over one file. Uncached
  // they resolve on separate frames and the blur flickers partway through the
  // open animation.
  if (includePreview && wallpaper.previews.isNotEmpty) {
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
    pageBuilder: (_, _, _) => WallpaperDetailDialog(
      wallpaper: wallpaper,
      stats: stats,
      actions: actions,
      extraContentBuilder: extraContentBuilder,
      includePreview: includePreview,
    ),
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
  const WallpaperDetailDialog({
    super.key,
    required this.wallpaper,
    this.stats,
    this.actions,
    this.extraContentBuilder,
    this.includePreview = true,
  });

  final WallpaperInfo wallpaper;

  /// Shape and brightness of the preview, or null when it couldn't be read.
  final PreviewStats? stats;

  /// Buttons in place of the extract ones. Null for the extract grid's own.
  final List<DetailAction>? actions;

  /// Optional content supplied by specialized callers.
  final DetailExtraBuilder? extraContentBuilder;

  /// Whether the caller supplied a meaningful wallpaper preview.
  /// When false, the details content reclaims that pane instead of rendering
  /// an empty/broken preview placeholder.
  final bool includePreview;

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
    // a wallpaper whose folder is now in the Recycle Bin. Only for the extract
    // grid's own buttons: another caller's wallpaper need not be in that list,
    // and watching it would close the dialog the moment it opened.
    if (widget.actions == null) {
      ref.listen(filterWallpaperListProvider, (_, List<WallpaperInfo> next) {
        if (!next.contains(widget.wallpaper)) _close();
      });
    }

    final Size screen = MediaQuery.of(context).size;

    // Preview-backed details keep the existing 340px metadata panel. When a
    // caller has no meaningful preview, the dialog keeps the same outer size a
    // square preview would have used and gives all of that space to content.
    const double standardPanelWidth = 340;
    final double maxWidth = screen.width * .84;
    final double height = min(screen.height * .72, _paneMaxHeight);
    final double aspect = widget.stats?.aspect ?? 1;
    double previewWidth = 0;
    double panelWidth = min(maxWidth, height + standardPanelWidth);
    if (widget.includePreview) {
      previewWidth = height * aspect;
      if (previewWidth + standardPanelWidth > maxWidth) {
        previewWidth = maxWidth - standardPanelWidth;
      }
      panelWidth = standardPanelWidth;
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
            if (widget.includePreview)
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
                useWallpaperBackdrop: widget.includePreview,
                child: _DetailPanelContent(
                  wallpaper: widget.wallpaper,
                  foreground: foreground,
                  actions: widget.actions,
                  extraContentBuilder: widget.extraContentBuilder,
                  contentOnly: !widget.includePreview,
                  onClose: _close,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailPanelContent extends StatelessWidget {
  const _DetailPanelContent({
    required this.wallpaper,
    required this.foreground,
    required this.actions,
    required this.extraContentBuilder,
    required this.contentOnly,
    required this.onClose,
  });

  final WallpaperInfo wallpaper;
  final Color foreground;
  final List<DetailAction>? actions;
  final DetailExtraBuilder? extraContentBuilder;
  final bool contentOnly;
  final VoidCallback onClose;

  Widget _actions() => switch (actions) {
    final List<DetailAction> given => _GivenActions(actions: given),
    null => _Actions(wallpaper: wallpaper),
  };

  Widget _meta() => WallpaperMeta(
    wallpaper: wallpaper,
    copyable: true,
    foreground: foreground,
  );

  @override
  Widget build(BuildContext context) {
    final DetailExtraBuilder? extra = extraContentBuilder;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              onPressed: onClose,
              icon: Icon(Icons.close_rounded, color: foreground),
              tooltip: tr(AppI10n.close),
            ),
          ),
          if (contentOnly && extra != null)
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Expanded(
                    flex: 5,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.only(right: 16),
                      child: _meta(),
                    ),
                  ),
                  VerticalDivider(
                    color: foreground.withValues(alpha: .25),
                    width: 1,
                    thickness: 1,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 7,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Expanded(child: extra(context, foreground)),
                        const SizedBox(height: 16),
                        _actions(),
                      ],
                    ),
                  ),
                ],
              ),
            )
          else ...<Widget>[
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _meta(),
                    if (extra != null) ...<Widget>[
                      const SizedBox(height: 16),
                      Divider(
                        color: foreground.withValues(alpha: .25),
                        height: 1,
                      ),
                      const SizedBox(height: 14),
                      extra(context, foreground),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            _actions(),
          ],
        ],
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
    required this.useWallpaperBackdrop,
    required this.child,
  });

  final WallpaperInfo wallpaper;

  final bool onDark;

  /// Mean brightness of the wallpaper behind this pane, 0 to 1.
  final double luminance;

  final bool useWallpaperBackdrop;

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
          if (useWallpaperBackdrop)
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
            )
          else
            ColoredBox(color: tint),
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

/// The caller's own buttons, laid out like the extract ones above.
class _GivenActions extends StatelessWidget {
  const _GivenActions({required this.actions});

  final List<DetailAction> actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: const ValueKey<String>('wallpaper-detail-actions'),
      padding: const EdgeInsets.only(bottom: _DetailActionLayout.bottomInset),
      child: Column(
        spacing: _DetailActionLayout.spacing,
        children: <Widget>[
          for (final DetailAction action in actions)
            if (action.destructive)
              _DetailActionButton.destructive(
                label: action.label,
                onPressed: action.onPressed,
              )
            else
              _DetailActionButton(
                label: action.label,
                onPressed: action.onPressed,
              ),
        ],
      ),
    );
  }
}

abstract final class _DetailActionLayout {
  /// Wide enough for the longest label either tab puts here, in either
  /// language, at the full font size.
  static const double width = 210;
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
