import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;

/// One concrete side of an explicit file comparison.
class FileComparisonSide {
  const FileComparisonSide({required this.label, required this.path});

  final String label;
  final String path;
}

/// Compatibility name for existing image-only callers.
typedef FileImageSide = FileComparisonSide;

bool isPreviewableImagePath(String filePath) {
  final String lower = filePath.toLowerCase();
  return const <String>[
    '.png',
    '.jpg',
    '.jpeg',
    '.webp',
    '.gif',
    '.bmp',
  ].any(lower.endsWith);
}

const Set<String> _textComparisonExtensions = <String>{
  '.cfg',
  '.conf',
  '.css',
  '.csv',
  '.frag',
  '.glsl',
  '.hlsl',
  '.html',
  '.ini',
  '.js',
  '.json',
  '.log',
  '.lua',
  '.md',
  '.shader',
  '.txt',
  '.vert',
  '.xml',
  '.yaml',
  '.yml',
};

bool isTextComparisonPath(String filePath) =>
    _textComparisonExtensions.contains(path.extension(filePath).toLowerCase());

/// Whether the shared comparison launcher can explain this pair.
///
/// Two concrete file paths are always comparable. Matching image pairs use the
/// image viewer, matching text pairs use JSON/text inspection, and every other
/// pair falls back to metadata plus a streamed SHA-256 comparison.
bool canCompareFilePaths(String firstPath, String secondPath) =>
    firstPath.trim().isNotEmpty && secondPath.trim().isNotEmpty;

/// Converts the internal flattened JSON locator into a compact UI breadcrumb.
///
/// The comparer keeps the exact locator only for identity/internal matching;
/// users see hierarchy rather than JSONPath-like implementation syntax.
String formatJsonFieldPath(String field) {
  String display = field.trim();
  if (display == r'$') return display;
  if (display.startsWith(r'$.')) {
    display = display.substring(2);
  } else if (display.startsWith(r'$')) {
    display = display.substring(1);
  }
  display = display.replaceAllMapped(
    RegExp(r'\[(\d+)\]'),
    (Match match) => '  ›  [${match.group(1)}]',
  );
  return display.replaceAll('.', '  ›  ').trim();
}

/// Shared explicit Compare action for two concrete files.
///
/// This chooses a presentation mode from the selected files only. It never
/// infers that the files are related, renamed, or part of an automatic plan.
class FileTreeCompareAction extends StatelessWidget {
  const FileTreeCompareAction({
    super.key,
    required this.first,
    required this.second,
    required this.title,
    required this.tooltip,
    required this.unavailableText,
    required this.jsonModeLabel,
    required this.textModeLabel,
    required this.jsonNoDifferencesText,
    required this.missingValueText,
    required this.truncatedText,
    required this.binaryModeLabel,
    required this.fileTypeLabel,
    required this.fileSizeLabel,
    required this.fileModifiedLabel,
    required this.hashLabel,
    required this.sameText,
    required this.differentText,
    required this.noExtensionText,
    required this.foreground,
    this.imageZoomOutTooltip = 'Zoom out',
    this.imageResetViewTooltip = 'Reset view',
    this.imageZoomInTooltip = 'Zoom in',
    this.imageLinkViewsTooltip = 'Link zoom and pan',
    this.imageUnlinkViewsTooltip = 'Unlink zoom and pan',
    this.imageSideBySideLabel = 'Side by side',
    this.imageOverlayLabel = 'Overlay',
    this.imageBlinkLabel = 'Blink',
    this.imageDifferenceLabel = 'Difference',
    this.imageOverlayOpacityLabel = 'New image opacity',
    this.imageDifferenceSameHint =
        'Black means matching pixels. Increase intensity to reveal subtle differences.',
    this.imageDifferenceIntensityLabel = 'Difference intensity',
    this.imageDifferenceSizeMismatch =
        'Difference view requires matching image dimensions.',
  });

  final FileComparisonSide first;
  final FileComparisonSide second;
  final String title;
  final String tooltip;
  final String unavailableText;
  final String jsonModeLabel;
  final String textModeLabel;
  final String jsonNoDifferencesText;
  final String missingValueText;
  final String truncatedText;
  final String binaryModeLabel;
  final String fileTypeLabel;
  final String fileSizeLabel;
  final String fileModifiedLabel;
  final String hashLabel;
  final String sameText;
  final String differentText;
  final String noExtensionText;
  final Color foreground;
  final String imageZoomOutTooltip;
  final String imageResetViewTooltip;
  final String imageZoomInTooltip;
  final String imageLinkViewsTooltip;
  final String imageUnlinkViewsTooltip;
  final String imageSideBySideLabel;
  final String imageOverlayLabel;
  final String imageBlinkLabel;
  final String imageDifferenceLabel;
  final String imageOverlayOpacityLabel;
  final String imageDifferenceSameHint;
  final String imageDifferenceIntensityLabel;
  final String imageDifferenceSizeMismatch;

  bool get enabled => canCompareFilePaths(first.path, second.path);

  /// Opens the same comparison used by the inline button.
  ///
  /// File-tree context menus call this so secondary-click and the visible
  /// compare icon cannot drift into separate comparison implementations.
  Future<void> open(BuildContext context) {
    if (!enabled) return Future<void>.value();
    return showFileComparisonDialog(
      context,
      first: first,
      second: second,
      title: title,
      unavailableText: unavailableText,
      jsonModeLabel: jsonModeLabel,
      textModeLabel: textModeLabel,
      jsonNoDifferencesText: jsonNoDifferencesText,
      missingValueText: missingValueText,
      truncatedText: truncatedText,
      binaryModeLabel: binaryModeLabel,
      fileTypeLabel: fileTypeLabel,
      fileSizeLabel: fileSizeLabel,
      fileModifiedLabel: fileModifiedLabel,
      hashLabel: hashLabel,
      sameText: sameText,
      differentText: differentText,
      noExtensionText: noExtensionText,
      imageZoomOutTooltip: imageZoomOutTooltip,
      imageResetViewTooltip: imageResetViewTooltip,
      imageZoomInTooltip: imageZoomInTooltip,
      imageLinkViewsTooltip: imageLinkViewsTooltip,
      imageUnlinkViewsTooltip: imageUnlinkViewsTooltip,
      imageSideBySideLabel: imageSideBySideLabel,
      imageOverlayLabel: imageOverlayLabel,
      imageBlinkLabel: imageBlinkLabel,
      imageDifferenceLabel: imageDifferenceLabel,
      imageOverlayOpacityLabel: imageOverlayOpacityLabel,
      imageDifferenceSameHint: imageDifferenceSameHint,
      imageDifferenceIntensityLabel: imageDifferenceIntensityLabel,
      imageDifferenceSizeMismatch: imageDifferenceSizeMismatch,
    );
  }

  @override
  Widget build(BuildContext context) {
    final VoidCallback? onPressed = enabled ? () => open(context) : null;
    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(
          Icons.compare_rounded,
          size: 17,
          color: foreground.withValues(alpha: .75),
        ),
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints.tightFor(width: 30, height: 30),
      ),
    );
  }
}

/// Opens the correct explicit comparison view for [first] and [second].
Future<void> showFileComparisonDialog(
  BuildContext context, {
  required FileComparisonSide first,
  required FileComparisonSide second,
  required String title,
  required String unavailableText,
  required String jsonModeLabel,
  required String textModeLabel,
  required String jsonNoDifferencesText,
  required String missingValueText,
  required String truncatedText,
  required String binaryModeLabel,
  required String fileTypeLabel,
  required String fileSizeLabel,
  required String fileModifiedLabel,
  required String hashLabel,
  required String sameText,
  required String differentText,
  required String noExtensionText,
  String imageZoomOutTooltip = 'Zoom out',
  String imageResetViewTooltip = 'Reset view',
  String imageZoomInTooltip = 'Zoom in',
  String imageLinkViewsTooltip = 'Link zoom and pan',
  String imageUnlinkViewsTooltip = 'Unlink zoom and pan',
  String imageSideBySideLabel = 'Side by side',
  String imageOverlayLabel = 'Overlay',
  String imageBlinkLabel = 'Blink',
  String imageDifferenceLabel = 'Difference',
  String imageOverlayOpacityLabel = 'New image opacity',
  String imageDifferenceSameHint =
      'Black means matching pixels. Increase intensity to reveal subtle differences.',
  String imageDifferenceIntensityLabel = 'Difference intensity',
  String imageDifferenceSizeMismatch =
      'Difference view requires matching image dimensions.',
}) {
  if (isPreviewableImagePath(first.path) &&
      isPreviewableImagePath(second.path)) {
    return _showImageDialog(
      context,
      first: first,
      second: second,
      title: title,
      unavailableText: unavailableText,
      zoomOutTooltip: imageZoomOutTooltip,
      resetViewTooltip: imageResetViewTooltip,
      zoomInTooltip: imageZoomInTooltip,
      linkViewsTooltip: imageLinkViewsTooltip,
      unlinkViewsTooltip: imageUnlinkViewsTooltip,
      sideBySideLabel: imageSideBySideLabel,
      overlayLabel: imageOverlayLabel,
      blinkLabel: imageBlinkLabel,
      differenceLabel: imageDifferenceLabel,
      overlayOpacityLabel: imageOverlayOpacityLabel,
      differenceSameHint: imageDifferenceSameHint,
      differenceIntensityLabel: imageDifferenceIntensityLabel,
      differenceSizeMismatch: imageDifferenceSizeMismatch,
    );
  }
  if (isTextComparisonPath(first.path) && isTextComparisonPath(second.path)) {
    return _showTextDialog(
      context,
      first: first,
      second: second,
      title: title,
      unavailableText: unavailableText,
      jsonModeLabel: jsonModeLabel,
      textModeLabel: textModeLabel,
      jsonNoDifferencesText: jsonNoDifferencesText,
      missingValueText: missingValueText,
      truncatedText: truncatedText,
    );
  }
  return _showBinaryDialog(
    context,
    first: first,
    second: second,
    title: title,
    unavailableText: unavailableText,
    modeLabel: binaryModeLabel,
    fileTypeLabel: fileTypeLabel,
    fileSizeLabel: fileSizeLabel,
    fileModifiedLabel: fileModifiedLabel,
    hashLabel: hashLabel,
    sameText: sameText,
    differentText: differentText,
    noExtensionText: noExtensionText,
  );
}

/// Optional image capability that callers can attach to a shared file-tree row.
class FileTreeImageAction extends StatelessWidget {
  const FileTreeImageAction({
    super.key,
    required this.first,
    required this.title,
    required this.tooltip,
    required this.unavailableText,
    required this.foreground,
    this.second,
    this.directional = false,
    this.zoomOutTooltip = 'Zoom out',
    this.resetViewTooltip = 'Reset view',
    this.zoomInTooltip = 'Zoom in',
    this.linkViewsTooltip = 'Link zoom and pan',
    this.unlinkViewsTooltip = 'Unlink zoom and pan',
    this.sideBySideLabel = 'Side by side',
    this.overlayLabel = 'Overlay',
    this.blinkLabel = 'Blink',
    this.differenceLabel = 'Difference',
    this.overlayOpacityLabel = 'New image opacity',
    this.differenceSameHint =
        'Black means matching pixels. Increase intensity to reveal subtle differences.',
    this.differenceIntensityLabel = 'Difference intensity',
    this.differenceSizeMismatch =
        'Difference view requires matching image dimensions.',
  });

  final FileImageSide first;
  final FileImageSide? second;
  final String title;
  final String tooltip;
  final String unavailableText;
  final Color foreground;
  final bool directional;
  final String zoomOutTooltip;
  final String resetViewTooltip;
  final String zoomInTooltip;
  final String linkViewsTooltip;
  final String unlinkViewsTooltip;
  final String sideBySideLabel;
  final String overlayLabel;
  final String blinkLabel;
  final String differenceLabel;
  final String overlayOpacityLabel;
  final String differenceSameHint;
  final String differenceIntensityLabel;
  final String differenceSizeMismatch;

  @override
  Widget build(BuildContext context) {
    void onPressed() {
      unawaited(
        _showImageDialog(
          context,
          first: first,
          second: second,
          title: title,
          unavailableText: unavailableText,
          directional: directional,
          zoomOutTooltip: zoomOutTooltip,
          resetViewTooltip: resetViewTooltip,
          zoomInTooltip: zoomInTooltip,
          linkViewsTooltip: linkViewsTooltip,
          unlinkViewsTooltip: unlinkViewsTooltip,
          sideBySideLabel: sideBySideLabel,
          overlayLabel: overlayLabel,
          blinkLabel: blinkLabel,
          differenceLabel: differenceLabel,
          overlayOpacityLabel: overlayOpacityLabel,
          differenceSameHint: differenceSameHint,
          differenceIntensityLabel: differenceIntensityLabel,
          differenceSizeMismatch: differenceSizeMismatch,
        ),
      );
    }

    final IconData icon = second == null
        ? Icons.image_outlined
        : Icons.compare_rounded;
    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: 17, color: foreground.withValues(alpha: .75)),
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints.tightFor(width: 30, height: 30),
      ),
    );
  }
}

Future<void> _showImageDialog(
  BuildContext context, {
  required FileImageSide first,
  required String title,
  required String unavailableText,
  required String zoomOutTooltip,
  required String resetViewTooltip,
  required String zoomInTooltip,
  required String linkViewsTooltip,
  required String unlinkViewsTooltip,
  String sideBySideLabel = 'Side by side',
  String overlayLabel = 'Overlay',
  String blinkLabel = 'Blink',
  String differenceLabel = 'Difference',
  String overlayOpacityLabel = 'New image opacity',
  String differenceSameHint = 'Black means matching pixels',
  String differenceIntensityLabel = 'Difference intensity',
  String differenceSizeMismatch =
      'Difference view requires matching image dimensions.',
  FileImageSide? second,
  bool directional = false,
}) => showDialog<void>(
  context: context,
  builder: (BuildContext context) {
    final Size screen = MediaQuery.sizeOf(context);
    return Dialog(
      key: const ValueKey<String>('file-image-compare-dialog'),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: min(1080.0, screen.width * .88),
        height: min(760.0, screen.height * .82),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    key: const ValueKey<String>('file-image-dialog-close'),
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Expanded(
                child: second == null
                    ? _ImagePane(
                        sideKey: 'single',
                        side: first,
                        unavailableText: unavailableText,
                        zoomOutTooltip: zoomOutTooltip,
                        resetViewTooltip: resetViewTooltip,
                        zoomInTooltip: zoomInTooltip,
                      )
                    : _ImageComparisonPair(
                        first: first,
                        second: second,
                        directional: directional,
                        unavailableText: unavailableText,
                        zoomOutTooltip: zoomOutTooltip,
                        resetViewTooltip: resetViewTooltip,
                        zoomInTooltip: zoomInTooltip,
                        linkViewsTooltip: linkViewsTooltip,
                        unlinkViewsTooltip: unlinkViewsTooltip,
                        sideBySideLabel: sideBySideLabel,
                        overlayLabel: overlayLabel,
                        blinkLabel: blinkLabel,
                        differenceLabel: differenceLabel,
                        overlayOpacityLabel: overlayOpacityLabel,
                        differenceSameHint: differenceSameHint,
                        differenceIntensityLabel: differenceIntensityLabel,
                        differenceSizeMismatch: differenceSizeMismatch,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  },
);

enum _ImageComparisonMode { sideBySide, overlay, blink, difference }

class _ImageComparisonPair extends StatefulWidget {
  const _ImageComparisonPair({
    required this.first,
    required this.second,
    required this.directional,
    required this.unavailableText,
    required this.zoomOutTooltip,
    required this.resetViewTooltip,
    required this.zoomInTooltip,
    required this.linkViewsTooltip,
    required this.unlinkViewsTooltip,
    required this.sideBySideLabel,
    required this.overlayLabel,
    required this.blinkLabel,
    required this.differenceLabel,
    required this.overlayOpacityLabel,
    required this.differenceSameHint,
    required this.differenceIntensityLabel,
    required this.differenceSizeMismatch,
  });

  final FileImageSide first;
  final FileImageSide second;
  final bool directional;
  final String unavailableText;
  final String zoomOutTooltip;
  final String resetViewTooltip;
  final String zoomInTooltip;
  final String linkViewsTooltip;
  final String unlinkViewsTooltip;
  final String sideBySideLabel;
  final String overlayLabel;
  final String blinkLabel;
  final String differenceLabel;
  final String overlayOpacityLabel;
  final String differenceSameHint;
  final String differenceIntensityLabel;
  final String differenceSizeMismatch;

  @override
  State<_ImageComparisonPair> createState() => _ImageComparisonPairState();
}

class _ImageComparisonPairState extends State<_ImageComparisonPair> {
  final TransformationController _firstController = TransformationController();
  final TransformationController _secondController = TransformationController();
  bool _linked = true;
  bool _syncing = false;
  _ImageComparisonMode _mode = _ImageComparisonMode.sideBySide;
  double _overlayOpacity = .5;
  double _differenceGain = 4;
  bool _blinkShowsSecond = false;
  Timer? _blinkTimer;

  @override
  void initState() {
    super.initState();
    _firstController.addListener(_syncFirstToSecond);
    _secondController.addListener(_syncSecondToFirst);
  }

  void _syncFirstToSecond() => _sync(_firstController, _secondController);

  void _syncSecondToFirst() => _sync(_secondController, _firstController);

  void _sync(
    TransformationController source,
    TransformationController destination,
  ) {
    if (!_linked || _syncing) return;
    _syncing = true;
    destination.value = source.value.clone();
    _syncing = false;
  }

  void _toggleLinked() {
    setState(() => _linked = !_linked);
    if (_linked) {
      _syncing = true;
      _secondController.value = _firstController.value.clone();
      _syncing = false;
    }
  }

  void _setMode(_ImageComparisonMode mode) {
    if (_mode == mode) return;
    _blinkTimer?.cancel();
    _blinkTimer = null;
    setState(() {
      _mode = mode;
      _blinkShowsSecond = false;
    });
    if (mode == _ImageComparisonMode.blink) {
      _blinkTimer = Timer.periodic(const Duration(milliseconds: 650), (_) {
        if (!mounted || _mode != _ImageComparisonMode.blink) return;
        setState(() => _blinkShowsSecond = !_blinkShowsSecond);
      });
    }
  }

  void _zoomComposite(double factor) {
    final next = _firstController.value.clone();
    final double currentScale = next.entry(0, 0).abs();
    final double targetScale = (currentScale * factor).clamp(.5, 8).toDouble();
    next.setEntry(0, 0, targetScale);
    next.setEntry(1, 1, targetScale);
    _firstController.value = next;
  }

  void _resetComposite() {
    _firstController.value = _firstController.value.clone()..setIdentity();
  }

  @override
  void dispose() {
    _blinkTimer?.cancel();
    _firstController.removeListener(_syncFirstToSecond);
    _secondController.removeListener(_syncSecondToFirst);
    _firstController.dispose();
    _secondController.dispose();
    super.dispose();
  }

  Widget _modeChip(
    _ImageComparisonMode mode,
    String label,
    IconData icon,
    String keyName,
  ) => ChoiceChip(
    key: ValueKey<String>('file-image-mode-$keyName'),
    label: Text(label),
    avatar: Icon(icon, size: 16),
    selected: _mode == mode,
    onSelected: (_) => _setMode(mode),
    visualDensity: VisualDensity.compact,
  );

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 6,
        runSpacing: 4,
        children: <Widget>[
          _modeChip(
            _ImageComparisonMode.sideBySide,
            widget.sideBySideLabel,
            Icons.view_column_outlined,
            'side-by-side',
          ),
          _modeChip(
            _ImageComparisonMode.overlay,
            widget.overlayLabel,
            Icons.layers_outlined,
            'overlay',
          ),
          _modeChip(
            _ImageComparisonMode.blink,
            widget.blinkLabel,
            Icons.visibility_outlined,
            'blink',
          ),
          _modeChip(
            _ImageComparisonMode.difference,
            widget.differenceLabel,
            Icons.difference_outlined,
            'difference',
          ),
          if (_mode == _ImageComparisonMode.sideBySide)
            IconButton(
              key: const ValueKey<String>('file-image-link-views'),
              tooltip: _linked
                  ? widget.unlinkViewsTooltip
                  : widget.linkViewsTooltip,
              onPressed: _toggleLinked,
              visualDensity: VisualDensity.compact,
              icon: Icon(
                _linked ? Icons.link_rounded : Icons.link_off_rounded,
                size: 18,
              ),
            ),
        ],
      ),
      if (_mode == _ImageComparisonMode.overlay)
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              '${widget.overlayOpacityLabel}: '
              '${(_overlayOpacity * 100).round()}%',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            SizedBox(
              width: min(320.0, MediaQuery.sizeOf(context).width * .32),
              child: Slider(
                key: const ValueKey<String>('file-image-overlay-opacity'),
                value: _overlayOpacity,
                onChanged: (double value) =>
                    setState(() => _overlayOpacity = value),
              ),
            ),
          ],
        ),
      if (_mode == _ImageComparisonMode.difference) ...<Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              '${widget.differenceIntensityLabel}: '
              '${_differenceGain.toStringAsFixed(0)}×',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            SizedBox(
              width: min(320.0, MediaQuery.sizeOf(context).width * .32),
              child: Slider(
                key: const ValueKey<String>('file-image-difference-intensity'),
                min: 1,
                max: 16,
                divisions: 15,
                value: _differenceGain,
                onChanged: (double value) =>
                    setState(() => _differenceGain = value),
              ),
            ),
          ],
        ),
        Text(
          widget.differenceSameHint,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
      const SizedBox(height: 4),
      Expanded(
        child: _mode == _ImageComparisonMode.sideBySide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Expanded(
                    child: _ImagePane(
                      sideKey: 'first',
                      side: widget.first,
                      controller: _firstController,
                      unavailableText: widget.unavailableText,
                      zoomOutTooltip: widget.zoomOutTooltip,
                      resetViewTooltip: widget.resetViewTooltip,
                      zoomInTooltip: widget.zoomInTooltip,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Icon(
                      widget.directional
                          ? Icons.arrow_forward_rounded
                          : Icons.compare_arrows_rounded,
                    ),
                  ),
                  Expanded(
                    child: _ImagePane(
                      sideKey: 'second',
                      side: widget.second,
                      controller: _secondController,
                      unavailableText: widget.unavailableText,
                      zoomOutTooltip: widget.zoomOutTooltip,
                      resetViewTooltip: widget.resetViewTooltip,
                      zoomInTooltip: widget.zoomInTooltip,
                    ),
                  ),
                ],
              )
            : _CompositeImagePane(
                first: widget.first,
                second: widget.second,
                mode: _mode,
                overlayOpacity: _overlayOpacity,
                differenceGain: _differenceGain,
                blinkShowsSecond: _blinkShowsSecond,
                controller: _firstController,
                unavailableText: widget.unavailableText,
                zoomOutTooltip: widget.zoomOutTooltip,
                resetViewTooltip: widget.resetViewTooltip,
                zoomInTooltip: widget.zoomInTooltip,
                differenceSizeMismatch: widget.differenceSizeMismatch,
                onZoomOut: () => _zoomComposite(.8),
                onReset: _resetComposite,
                onZoomIn: () => _zoomComposite(1.25),
              ),
      ),
    ],
  );
}

class _CompositeImagePane extends StatelessWidget {
  const _CompositeImagePane({
    required this.first,
    required this.second,
    required this.mode,
    required this.overlayOpacity,
    required this.differenceGain,
    required this.blinkShowsSecond,
    required this.controller,
    required this.unavailableText,
    required this.zoomOutTooltip,
    required this.resetViewTooltip,
    required this.zoomInTooltip,
    required this.differenceSizeMismatch,
    required this.onZoomOut,
    required this.onReset,
    required this.onZoomIn,
  });

  final FileImageSide first;
  final FileImageSide second;
  final _ImageComparisonMode mode;
  final double overlayOpacity;
  final double differenceGain;
  final bool blinkShowsSecond;
  final TransformationController controller;
  final String unavailableText;
  final String zoomOutTooltip;
  final String resetViewTooltip;
  final String zoomInTooltip;
  final String differenceSizeMismatch;
  final VoidCallback onZoomOut;
  final VoidCallback onReset;
  final VoidCallback onZoomIn;

  Widget _image(String filePath) => Image.file(
    File(filePath),
    fit: BoxFit.contain,
    errorBuilder: (_, _, _) => Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Text(unavailableText, textAlign: TextAlign.center),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final Color outline = Theme.of(context).colorScheme.outlineVariant;
    final Widget content = switch (mode) {
      _ImageComparisonMode.overlay => Stack(
        fit: StackFit.expand,
        children: <Widget>[
          _image(first.path),
          Opacity(opacity: overlayOpacity, child: _image(second.path)),
        ],
      ),
      _ImageComparisonMode.blink => _image(
        blinkShowsSecond ? second.path : first.path,
      ),
      _ImageComparisonMode.difference => _DifferenceImage(
        firstPath: first.path,
        secondPath: second.path,
        unavailableText: unavailableText,
        sizeMismatchText: differenceSizeMismatch,
        gain: differenceGain,
      ),
      _ImageComparisonMode.sideBySide => const SizedBox.shrink(),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          '${first.label}  ↔  ${second.label}',
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        Text(
          '${path.basename(first.path)}  ↔  ${path.basename(second.path)}',
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        SizedBox(
          height: 30,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              IconButton(
                key: const ValueKey<String>('file-image-composite-zoom-out'),
                tooltip: zoomOutTooltip,
                onPressed: onZoomOut,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.remove_rounded, size: 18),
              ),
              IconButton(
                key: const ValueKey<String>('file-image-composite-reset'),
                tooltip: resetViewTooltip,
                onPressed: onReset,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.center_focus_strong_rounded, size: 17),
              ),
              IconButton(
                key: const ValueKey<String>('file-image-composite-zoom-in'),
                tooltip: zoomInTooltip,
                onPressed: onZoomIn,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.add_rounded, size: 18),
              ),
            ],
          ),
        ),
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: outline),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: InteractiveViewer(
                transformationController: controller,
                minScale: .5,
                maxScale: 8,
                child: SizedBox.expand(child: content),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DifferenceImage extends StatefulWidget {
  const _DifferenceImage({
    required this.firstPath,
    required this.secondPath,
    required this.unavailableText,
    required this.sizeMismatchText,
    required this.gain,
  });

  final String firstPath;
  final String secondPath;
  final String unavailableText;
  final String sizeMismatchText;
  final double gain;

  @override
  State<_DifferenceImage> createState() => _DifferenceImageState();
}

class _DifferenceImageState extends State<_DifferenceImage> {
  ui.Image? _first;
  ui.Image? _second;
  bool _loading = true;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _DifferenceImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.firstPath != widget.firstPath ||
        oldWidget.secondPath != widget.secondPath) {
      _load();
    }
  }

  Future<void> _load() async {
    final int generation = ++_generation;
    if (mounted) setState(() => _loading = true);
    final ui.Image? first = await _decodeUiImage(widget.firstPath);
    final ui.Image? second = await _decodeUiImage(widget.secondPath);
    if (!mounted || generation != _generation) {
      first?.dispose();
      second?.dispose();
      return;
    }
    _first?.dispose();
    _second?.dispose();
    setState(() {
      _first = first;
      _second = second;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _generation++;
    _first?.dispose();
    _second?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final ui.Image? first = _first;
    final ui.Image? second = _second;
    if (first == null || second == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(widget.unavailableText, textAlign: TextAlign.center),
        ),
      );
    }
    if (first.width != second.width || first.height != second.height) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(widget.sizeMismatchText, textAlign: TextAlign.center),
        ),
      );
    }
    return CustomPaint(
      key: const ValueKey<String>('file-image-difference-view'),
      painter: _DifferencePainter(first, second, widget.gain),
      child: const SizedBox.expand(),
    );
  }
}

Future<ui.Image?> _decodeUiImage(String filePath) async {
  ui.Codec? codec;
  try {
    final bytes = await File(filePath).readAsBytes();
    codec = await ui.instantiateImageCodec(bytes);
    final ui.FrameInfo frame = await codec.getNextFrame();
    return frame.image;
  } on FileSystemException {
    return null;
  } catch (_) {
    return null;
  } finally {
    codec?.dispose();
  }
}

class _DifferencePainter extends CustomPainter {
  const _DifferencePainter(this.first, this.second, this.gain);

  final ui.Image first;
  final ui.Image second;
  final double gain;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final double scale = min(
      size.width / first.width,
      size.height / first.height,
    );
    final Size fitted = Size(first.width * scale, first.height * scale);
    final Rect destination = Rect.fromLTWH(
      (size.width - fitted.width) / 2,
      (size.height - fitted.height) / 2,
      fitted.width,
      fitted.height,
    );
    final Rect source = Rect.fromLTWH(
      0,
      0,
      first.width.toDouble(),
      first.height.toDouble(),
    );
    canvas.saveLayer(
      destination,
      Paint()
        ..colorFilter = ColorFilter.matrix(<double>[
          gain,
          0,
          0,
          0,
          0,
          0,
          gain,
          0,
          0,
          0,
          0,
          0,
          gain,
          0,
          0,
          0,
          0,
          0,
          1,
          0,
        ]),
    );
    canvas.drawImageRect(first, source, destination, Paint());
    canvas.drawImageRect(
      second,
      source,
      destination,
      Paint()..blendMode = BlendMode.difference,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _DifferencePainter oldDelegate) =>
      oldDelegate.first != first ||
      oldDelegate.second != second ||
      oldDelegate.gain != gain;
}

typedef _ImageFileInfo = ({int bytes, int width, int height, String format});

Future<_ImageFileInfo?> _readImageInfo(String filePath) async {
  final File file = File(filePath);
  if (!await file.exists()) return null;
  ui.ImageDescriptor? descriptor;
  ui.ImmutableBuffer? buffer;
  try {
    final FileStat stat = await file.stat();
    buffer = await ui.ImmutableBuffer.fromUint8List(await file.readAsBytes());
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    final String extension = path.extension(filePath).replaceFirst('.', '');
    return (
      bytes: stat.size,
      width: descriptor.width,
      height: descriptor.height,
      format: extension.isEmpty ? 'IMAGE' : extension.toUpperCase(),
    );
  } on FileSystemException {
    return null;
  } catch (_) {
    return null;
  } finally {
    descriptor?.dispose();
    buffer?.dispose();
  }
}

const int _maxTextPreviewBytes = 1024 * 1024;
typedef _TextFileInfo = ({int bytes, String text, bool truncated});

Future<_TextFileInfo?> _readTextInfo(String filePath) async {
  final File file = File(filePath);
  if (!await file.exists()) return null;
  RandomAccessFile? handle;
  try {
    final FileStat stat = await file.stat();
    final int readableBytes = min(stat.size, _maxTextPreviewBytes);
    handle = await file.open();
    final List<int> bytes = await handle.read(readableBytes);
    return (
      bytes: stat.size,
      text: utf8.decode(bytes, allowMalformed: true),
      truncated: stat.size > readableBytes,
    );
  } on FileSystemException {
    return null;
  } catch (_) {
    return null;
  } finally {
    if (handle != null) await handle.close();
  }
}

class _JsonDifference {
  const _JsonDifference({
    required this.field,
    required this.before,
    required this.after,
    required this.beforePresent,
    required this.afterPresent,
  });

  final String field;
  final Object? before;
  final Object? after;
  final bool beforePresent;
  final bool afterPresent;
}

class _JsonComparison {
  const _JsonComparison(this.differences);

  final List<_JsonDifference> differences;
}

_JsonComparison? _tryJsonComparison(_TextFileInfo first, _TextFileInfo second) {
  if (first.truncated || second.truncated) return null;
  Object? left;
  Object? right;
  try {
    left = jsonDecode(first.text);
    right = jsonDecode(second.text);
  } on FormatException {
    return null;
  }

  final Map<String, Object?> before = <String, Object?>{};
  final Map<String, Object?> after = <String, Object?>{};
  _flattenJson(left, r'$', before);
  _flattenJson(right, r'$', after);
  final List<String> fields = <String>{...before.keys, ...after.keys}.toList()
    ..sort();

  final List<_JsonDifference> differences = <_JsonDifference>[];
  for (final String field in fields) {
    final bool beforePresent = before.containsKey(field);
    final bool afterPresent = after.containsKey(field);
    final Object? beforeValue = before[field];
    final Object? afterValue = after[field];
    if (beforePresent == afterPresent &&
        (!beforePresent || jsonEncode(beforeValue) == jsonEncode(afterValue))) {
      continue;
    }
    differences.add(
      _JsonDifference(
        field: field,
        before: beforeValue,
        after: afterValue,
        beforePresent: beforePresent,
        afterPresent: afterPresent,
      ),
    );
  }
  return _JsonComparison(differences);
}

void _flattenJson(Object? value, String field, Map<String, Object?> output) {
  if (value is Map) {
    if (value.isEmpty) {
      output[field] = const <String, Object?>{};
      return;
    }
    for (final Object? rawKey in value.keys) {
      final String key = rawKey.toString();
      _flattenJson(value[rawKey], '$field.$key', output);
    }
    return;
  }
  if (value is List) {
    if (value.isEmpty) {
      output[field] = const <Object?>[];
      return;
    }
    for (int index = 0; index < value.length; index++) {
      _flattenJson(value[index], '$field[$index]', output);
    }
    return;
  }
  output[field] = value;
}

typedef _BinaryFileInfo = ({
  int bytes,
  DateTime modified,
  String extension,
  String sha256,
});

Future<_BinaryFileInfo?> _readBinaryInfo(String filePath) async {
  final File file = File(filePath);
  if (!await file.exists()) return null;
  try {
    final FileStat before = await file.stat();
    if (before.type != FileSystemEntityType.file) return null;

    final Digest digest = await sha256.bind(file.openRead()).first;
    final FileStat after = await file.stat();

    // Do not present a hash as authoritative if the file changed while it was
    // being read. A retry from the Compare action will produce a fresh result.
    if (after.type != FileSystemEntityType.file ||
        before.size != after.size ||
        before.modified != after.modified) {
      return null;
    }

    return (
      bytes: after.size,
      modified: after.modified,
      extension: path.extension(filePath).toLowerCase(),
      sha256: digest.toString(),
    );
  } on FileSystemException {
    return null;
  } catch (_) {
    return null;
  }
}

Future<void> _showBinaryDialog(
  BuildContext context, {
  required FileComparisonSide first,
  required FileComparisonSide second,
  required String title,
  required String unavailableText,
  required String modeLabel,
  required String fileTypeLabel,
  required String fileSizeLabel,
  required String fileModifiedLabel,
  required String hashLabel,
  required String sameText,
  required String differentText,
  required String noExtensionText,
}) => showDialog<void>(
  context: context,
  builder: (BuildContext context) {
    final Size screen = MediaQuery.sizeOf(context);
    return Dialog(
      key: const ValueKey<String>('file-binary-compare-dialog'),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: min(980.0, screen.width * .88),
        height: min(620.0, screen.height * .76),
        child: _BinaryComparisonBody(
          first: first,
          second: second,
          title: title,
          unavailableText: unavailableText,
          modeLabel: modeLabel,
          fileTypeLabel: fileTypeLabel,
          fileSizeLabel: fileSizeLabel,
          fileModifiedLabel: fileModifiedLabel,
          hashLabel: hashLabel,
          sameText: sameText,
          differentText: differentText,
          noExtensionText: noExtensionText,
        ),
      ),
    );
  },
);

class _BinaryComparisonBody extends StatefulWidget {
  const _BinaryComparisonBody({
    required this.first,
    required this.second,
    required this.title,
    required this.unavailableText,
    required this.modeLabel,
    required this.fileTypeLabel,
    required this.fileSizeLabel,
    required this.fileModifiedLabel,
    required this.hashLabel,
    required this.sameText,
    required this.differentText,
    required this.noExtensionText,
  });

  final FileComparisonSide first;
  final FileComparisonSide second;
  final String title;
  final String unavailableText;
  final String modeLabel;
  final String fileTypeLabel;
  final String fileSizeLabel;
  final String fileModifiedLabel;
  final String hashLabel;
  final String sameText;
  final String differentText;
  final String noExtensionText;

  @override
  State<_BinaryComparisonBody> createState() => _BinaryComparisonBodyState();
}

class _BinaryComparisonBodyState extends State<_BinaryComparisonBody> {
  late Future<List<_BinaryFileInfo?>> _files;

  @override
  void initState() {
    super.initState();
    _files = _read();
  }

  @override
  void didUpdateWidget(covariant _BinaryComparisonBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.first.path != widget.first.path ||
        oldWidget.second.path != widget.second.path) {
      _files = _read();
    }
  }

  Future<List<_BinaryFileInfo?>> _read() =>
      Future.wait(<Future<_BinaryFileInfo?>>[
        _readBinaryInfo(widget.first.path),
        _readBinaryInfo(widget.second.path),
      ]);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                widget.title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            IconButton(
              key: const ValueKey<String>('file-binary-dialog-close'),
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Expanded(
          child: FutureBuilder<List<_BinaryFileInfo?>>(
            future: _files,
            builder:
                (
                  BuildContext context,
                  AsyncSnapshot<List<_BinaryFileInfo?>> snapshot,
                ) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final List<_BinaryFileInfo?>? files = snapshot.data;
                  if (snapshot.hasError ||
                      files == null ||
                      files.length != 2 ||
                      files[0] == null ||
                      files[1] == null) {
                    return Center(child: Text(widget.unavailableText));
                  }
                  return _BinaryComparisonContent(
                    key: const ValueKey<String>('file-binary-compare-content'),
                    firstSide: widget.first,
                    secondSide: widget.second,
                    first: files[0]!,
                    second: files[1]!,
                    modeLabel: widget.modeLabel,
                    fileTypeLabel: widget.fileTypeLabel,
                    fileSizeLabel: widget.fileSizeLabel,
                    fileModifiedLabel: widget.fileModifiedLabel,
                    hashLabel: widget.hashLabel,
                    sameText: widget.sameText,
                    differentText: widget.differentText,
                    noExtensionText: widget.noExtensionText,
                  );
                },
          ),
        ),
      ],
    ),
  );
}

class _BinaryComparisonContent extends StatelessWidget {
  const _BinaryComparisonContent({
    super.key,
    required this.firstSide,
    required this.secondSide,
    required this.first,
    required this.second,
    required this.modeLabel,
    required this.fileTypeLabel,
    required this.fileSizeLabel,
    required this.fileModifiedLabel,
    required this.hashLabel,
    required this.sameText,
    required this.differentText,
    required this.noExtensionText,
  });

  final FileComparisonSide firstSide;
  final FileComparisonSide secondSide;
  final _BinaryFileInfo first;
  final _BinaryFileInfo second;
  final String modeLabel;
  final String fileTypeLabel;
  final String fileSizeLabel;
  final String fileModifiedLabel;
  final String hashLabel;
  final String sameText;
  final String differentText;
  final String noExtensionText;

  String _type(_BinaryFileInfo info) {
    if (info.extension.isEmpty) return noExtensionText;
    return info.extension.substring(1).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final bool sameHash = first.sha256 == second.sha256;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _ComparisonModeHeader(
          modeLabel: modeLabel,
          first: firstSide,
          second: secondSide,
        ),
        const SizedBox(height: 10),
        Center(
          child: _ComparisonStateBadge(
            key: const ValueKey<String>('file-binary-content-result'),
            label: '$hashLabel: ${sameHash ? sameText : differentText}',
            same: sameHash,
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: ListView(
            children: <Widget>[
              _BinaryMetadataRow(
                rowKey: 'type',
                label: fileTypeLabel,
                firstValue: _type(first),
                secondValue: _type(second),
                sameText: sameText,
                differentText: differentText,
                sameOverride: first.extension == second.extension,
              ),
              _BinaryMetadataRow(
                rowKey: 'size',
                label: fileSizeLabel,
                firstValue: _formatBytes(first.bytes),
                secondValue: _formatBytes(second.bytes),
                sameText: sameText,
                differentText: differentText,
                sameOverride: first.bytes == second.bytes,
              ),
              _BinaryMetadataRow(
                rowKey: 'modified',
                label: fileModifiedLabel,
                firstValue: _formatModified(first.modified),
                secondValue: _formatModified(second.modified),
                sameText: sameText,
                differentText: differentText,
                sameOverride: first.modified == second.modified,
              ),
              _BinaryMetadataRow(
                rowKey: 'sha256',
                label: hashLabel,
                firstValue: first.sha256,
                secondValue: second.sha256,
                sameText: sameText,
                differentText: differentText,
                sameOverride: sameHash,
                monospace: true,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BinaryMetadataRow extends StatelessWidget {
  const _BinaryMetadataRow({
    required this.rowKey,
    required this.label,
    required this.firstValue,
    required this.secondValue,
    required this.sameText,
    required this.differentText,
    this.sameOverride,
    this.monospace = false,
  });

  final String rowKey;
  final String label;
  final String firstValue;
  final String secondValue;
  final String sameText;
  final String differentText;
  final bool? sameOverride;
  final bool monospace;

  @override
  Widget build(BuildContext context) {
    final bool same = sameOverride ?? firstValue == secondValue;
    final Color outline = Theme.of(context).colorScheme.outlineVariant;
    final TextStyle? valueStyle = monospace
        ? const TextStyle(fontFamily: 'Consolas', fontSize: 12)
        : Theme.of(context).textTheme.bodyMedium;

    return Container(
      key: ValueKey<String>('file-binary-row-$rowKey'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: outline)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: SelectableText(
              firstValue,
              key: ValueKey<String>('file-binary-before-$rowKey'),
              style: valueStyle,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: _ComparisonStateBadge(
              key: ValueKey<String>('file-binary-status-$rowKey'),
              label: same ? sameText : differentText,
              same: same,
            ),
          ),
          Expanded(
            child: SelectableText(
              secondValue,
              key: ValueKey<String>('file-binary-after-$rowKey'),
              style: valueStyle,
            ),
          ),
        ],
      ),
    );
  }
}

class _ComparisonStateBadge extends StatelessWidget {
  const _ComparisonStateBadge({
    super.key,
    required this.label,
    required this.same,
  });

  final String label;
  final bool same;

  @override
  Widget build(BuildContext context) {
    final Color colour = same
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.error;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colour.withValues(alpha: .1),
        border: Border.all(color: colour.withValues(alpha: .35)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: colour,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

String _formatModified(DateTime value) {
  final String iso = value.toLocal().toIso8601String();
  final int decimal = iso.indexOf('.');
  final String precise = decimal < 0
      ? iso
      : iso.substring(0, min(iso.length, decimal + 4));
  return precise.replaceFirst('T', ' ');
}

Future<void> _showTextDialog(
  BuildContext context, {
  required FileComparisonSide first,
  required FileComparisonSide second,
  required String title,
  required String unavailableText,
  required String jsonModeLabel,
  required String textModeLabel,
  required String jsonNoDifferencesText,
  required String missingValueText,
  required String truncatedText,
}) => showDialog<void>(
  context: context,
  builder: (BuildContext context) {
    final Size screen = MediaQuery.sizeOf(context);
    return Dialog(
      key: const ValueKey<String>('file-text-compare-dialog'),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: min(1120.0, screen.width * .9),
        height: min(760.0, screen.height * .82),
        child: _TextComparisonBody(
          first: first,
          second: second,
          title: title,
          unavailableText: unavailableText,
          jsonModeLabel: jsonModeLabel,
          textModeLabel: textModeLabel,
          jsonNoDifferencesText: jsonNoDifferencesText,
          missingValueText: missingValueText,
          truncatedText: truncatedText,
        ),
      ),
    );
  },
);

class _TextComparisonBody extends StatefulWidget {
  const _TextComparisonBody({
    required this.first,
    required this.second,
    required this.title,
    required this.unavailableText,
    required this.jsonModeLabel,
    required this.textModeLabel,
    required this.jsonNoDifferencesText,
    required this.missingValueText,
    required this.truncatedText,
  });

  final FileComparisonSide first;
  final FileComparisonSide second;
  final String title;
  final String unavailableText;
  final String jsonModeLabel;
  final String textModeLabel;
  final String jsonNoDifferencesText;
  final String missingValueText;
  final String truncatedText;

  @override
  State<_TextComparisonBody> createState() => _TextComparisonBodyState();
}

class _TextComparisonBodyState extends State<_TextComparisonBody> {
  late Future<List<_TextFileInfo?>> _files;

  @override
  void initState() {
    super.initState();
    _files = _read();
  }

  @override
  void didUpdateWidget(covariant _TextComparisonBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.first.path != widget.first.path ||
        oldWidget.second.path != widget.second.path) {
      _files = _read();
    }
  }

  Future<List<_TextFileInfo?>> _read() => Future.wait(<Future<_TextFileInfo?>>[
    _readTextInfo(widget.first.path),
    _readTextInfo(widget.second.path),
  ]);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                widget.title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            IconButton(
              key: const ValueKey<String>('file-text-dialog-close'),
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Expanded(
          child: FutureBuilder<List<_TextFileInfo?>>(
            future: _files,
            builder:
                (
                  BuildContext context,
                  AsyncSnapshot<List<_TextFileInfo?>> snapshot,
                ) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final List<_TextFileInfo?>? files = snapshot.data;
                  if (snapshot.hasError ||
                      files == null ||
                      files.length != 2 ||
                      files[0] == null ||
                      files[1] == null) {
                    return Center(child: Text(widget.unavailableText));
                  }
                  final _TextFileInfo first = files[0]!;
                  final _TextFileInfo second = files[1]!;
                  final _JsonComparison? json = _tryJsonComparison(
                    first,
                    second,
                  );
                  if (json != null) {
                    return _StructuredJsonComparison(
                      key: const ValueKey<String>('file-json-compare-content'),
                      firstSide: widget.first,
                      secondSide: widget.second,
                      comparison: json,
                      modeLabel: widget.jsonModeLabel,
                      noDifferencesText: widget.jsonNoDifferencesText,
                      missingValueText: widget.missingValueText,
                    );
                  }
                  return _PlainTextComparison(
                    key: const ValueKey<String>(
                      'file-plain-text-compare-content',
                    ),
                    firstSide: widget.first,
                    secondSide: widget.second,
                    first: first,
                    second: second,
                    modeLabel: widget.textModeLabel,
                    truncatedText: widget.truncatedText,
                  );
                },
          ),
        ),
      ],
    ),
  );
}

class _StructuredJsonComparison extends StatelessWidget {
  const _StructuredJsonComparison({
    super.key,
    required this.firstSide,
    required this.secondSide,
    required this.comparison,
    required this.modeLabel,
    required this.noDifferencesText,
    required this.missingValueText,
  });

  final FileComparisonSide firstSide;
  final FileComparisonSide secondSide;
  final _JsonComparison comparison;
  final String modeLabel;
  final String noDifferencesText;
  final String missingValueText;

  String _value(Object? value, bool present) =>
      present ? jsonEncode(value) : missingValueText;

  @override
  Widget build(BuildContext context) {
    final Color outline = Theme.of(context).colorScheme.outlineVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _ComparisonModeHeader(
          modeLabel: modeLabel,
          first: firstSide,
          second: secondSide,
        ),
        const SizedBox(height: 8),
        Expanded(
          child: comparison.differences.isEmpty
              ? Center(child: Text(noDifferencesText))
              : ListView.separated(
                  itemCount: comparison.differences.length,
                  separatorBuilder: (_, _) =>
                      Divider(height: 1, color: outline.withValues(alpha: .65)),
                  itemBuilder: (BuildContext context, int index) {
                    final _JsonDifference difference =
                        comparison.differences[index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Text(
                            formatJsonFieldPath(difference.field),
                            style: const TextStyle(
                              fontFamily: 'Consolas',
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Expanded(
                                child: SelectableText(
                                  _value(
                                    difference.before,
                                    difference.beforePresent,
                                  ),
                                  key: ValueKey<String>(
                                    'file-json-before-${difference.field}',
                                  ),
                                  style: const TextStyle(
                                    fontFamily: 'Consolas',
                                  ),
                                ),
                              ),
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 10),
                                child: Icon(
                                  Icons.compare_arrows_rounded,
                                  size: 16,
                                ),
                              ),
                              Expanded(
                                child: SelectableText(
                                  _value(
                                    difference.after,
                                    difference.afterPresent,
                                  ),
                                  key: ValueKey<String>(
                                    'file-json-after-${difference.field}',
                                  ),
                                  style: const TextStyle(
                                    fontFamily: 'Consolas',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _PlainTextComparison extends StatelessWidget {
  const _PlainTextComparison({
    super.key,
    required this.firstSide,
    required this.secondSide,
    required this.first,
    required this.second,
    required this.modeLabel,
    required this.truncatedText,
  });

  final FileComparisonSide firstSide;
  final FileComparisonSide secondSide;
  final _TextFileInfo first;
  final _TextFileInfo second;
  final String modeLabel;
  final String truncatedText;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      _ComparisonModeHeader(
        modeLabel: modeLabel,
        first: firstSide,
        second: secondSide,
      ),
      const SizedBox(height: 8),
      Expanded(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(
              child: _TextPane(
                side: firstSide,
                info: first,
                truncatedText: truncatedText,
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 10),
              child: Icon(Icons.compare_arrows_rounded),
            ),
            Expanded(
              child: _TextPane(
                side: secondSide,
                info: second,
                truncatedText: truncatedText,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class _ComparisonModeHeader extends StatelessWidget {
  const _ComparisonModeHeader({
    required this.modeLabel,
    required this.first,
    required this.second,
  });

  final String modeLabel;
  final FileComparisonSide first;
  final FileComparisonSide second;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      Text(
        modeLabel,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.labelLarge,
      ),
      const SizedBox(height: 4),
      Row(
        children: <Widget>[
          Expanded(child: _SideHeading(side: first)),
          const SizedBox(width: 36),
          Expanded(child: _SideHeading(side: second)),
        ],
      ),
    ],
  );
}

class _SideHeading extends StatelessWidget {
  const _SideHeading({required this.side});

  final FileComparisonSide side;

  @override
  Widget build(BuildContext context) => Column(
    children: <Widget>[
      Text(
        side.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      Text(
        path.basename(side.path),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ],
  );
}

class _TextPane extends StatelessWidget {
  const _TextPane({
    required this.side,
    required this.info,
    required this.truncatedText,
  });

  final FileComparisonSide side;
  final _TextFileInfo info;
  final String truncatedText;

  @override
  Widget build(BuildContext context) {
    final Color outline = Theme.of(context).colorScheme.outlineVariant;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: outline),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              _formatBytes(info.bytes),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (info.truncated)
              Text(
                truncatedText,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            const SizedBox(height: 6),
            Expanded(
              child: SingleChildScrollView(
                child: SelectableText(
                  info.text,
                  key: ValueKey<String>('file-text-${side.path}'),
                  style: const TextStyle(fontFamily: 'Consolas', fontSize: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final double kib = bytes / 1024;
  if (kib < 1024) return '${kib.toStringAsFixed(kib >= 100 ? 0 : 1)} KB';
  final double mib = kib / 1024;
  if (mib < 1024) return '${mib.toStringAsFixed(mib >= 100 ? 0 : 2)} MB';
  final double gib = mib / 1024;
  return '${gib.toStringAsFixed(2)} GB';
}

class _ImagePane extends StatefulWidget {
  const _ImagePane({
    required this.sideKey,
    required this.side,
    required this.unavailableText,
    required this.zoomOutTooltip,
    required this.resetViewTooltip,
    required this.zoomInTooltip,
    this.controller,
  });

  final String sideKey;
  final FileImageSide side;
  final String unavailableText;
  final String zoomOutTooltip;
  final String resetViewTooltip;
  final String zoomInTooltip;
  final TransformationController? controller;

  @override
  State<_ImagePane> createState() => _ImagePaneState();
}

class _ImagePaneState extends State<_ImagePane> {
  late Future<_ImageFileInfo?> _info;
  TransformationController? _ownedController;

  TransformationController get _controller =>
      widget.controller ?? _ownedController!;

  @override
  void initState() {
    super.initState();
    _info = _readImageInfo(widget.side.path);
    if (widget.controller == null) {
      _ownedController = TransformationController();
    }
  }

  @override
  void didUpdateWidget(covariant _ImagePane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.side.path != widget.side.path) {
      _info = _readImageInfo(widget.side.path);
    }
    if (oldWidget.controller != widget.controller) {
      _ownedController?.dispose();
      _ownedController = widget.controller == null
          ? TransformationController()
          : null;
    }
  }

  void _zoom(double factor) {
    final next = _controller.value.clone();
    final double currentScale = next.entry(0, 0).abs();
    final double targetScale = (currentScale * factor).clamp(.5, 8).toDouble();
    next.setEntry(0, 0, targetScale);
    next.setEntry(1, 1, targetScale);
    _controller.value = next;
  }

  void _resetView() {
    _controller.value = _controller.value.clone()..setIdentity();
  }

  @override
  void dispose() {
    _ownedController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color outline = Theme.of(context).colorScheme.outlineVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          widget.side.label,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 3),
        Text(
          path.basename(widget.side.path),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 3),
        SizedBox(
          height: 18,
          child: FutureBuilder<_ImageFileInfo?>(
            future: _info,
            builder:
                (
                  BuildContext context,
                  AsyncSnapshot<_ImageFileInfo?> snapshot,
                ) {
                  final _ImageFileInfo? info = snapshot.data;
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(
                      child: SizedBox.square(
                        dimension: 12,
                        child: CircularProgressIndicator(strokeWidth: 1.5),
                      ),
                    );
                  }
                  if (info == null) return const SizedBox.shrink();
                  return Text(
                    '${info.width} × ${info.height}  •  ${_formatBytes(info.bytes)}  •  ${info.format}',
                    key: ValueKey<String>(
                      'file-image-info-${widget.side.path}',
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  );
                },
          ),
        ),
        SizedBox(
          height: 30,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              IconButton(
                key: ValueKey<String>('file-image-${widget.sideKey}-zoom-out'),
                tooltip: widget.zoomOutTooltip,
                onPressed: () => _zoom(.8),
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.remove_rounded, size: 18),
              ),
              IconButton(
                key: ValueKey<String>('file-image-${widget.sideKey}-reset'),
                tooltip: widget.resetViewTooltip,
                onPressed: _resetView,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.center_focus_strong_rounded, size: 17),
              ),
              IconButton(
                key: ValueKey<String>('file-image-${widget.sideKey}-zoom-in'),
                tooltip: widget.zoomInTooltip,
                onPressed: () => _zoom(1.25),
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.add_rounded, size: 18),
              ),
            ],
          ),
        ),
        const SizedBox(height: 3),
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: outline),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: InteractiveViewer(
                transformationController: _controller,
                minScale: .5,
                maxScale: 8,
                child: Center(
                  child: Image.file(
                    File(widget.side.path),
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        widget.unavailableText,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
