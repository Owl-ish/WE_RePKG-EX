import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:we_repkg/widgets/file_tree_panel.dart';

part 'file_compare/image_comparison.dart';
part 'file_compare/text_comparison.dart';
part 'file_compare/binary_comparison.dart';

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
    this.hoverInert = false,
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
  final bool hoverInert;

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
    if (hoverInert) {
      return _FileTreeHoverInertAction(
        label: tooltip,
        icon: Icons.compare_rounded,
        foreground: foreground,
        onPressed: onPressed,
      );
    }
    return FileTreeTooltip(
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

/// Preserves pointer, keyboard, and accessibility activation without creating
/// Material hover state or inserting a tooltip overlay into a live AX subtree.
class _FileTreeHoverInertAction extends StatelessWidget {
  const _FileTreeHoverInertAction({
    required this.label,
    required this.icon,
    required this.foreground,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final Color foreground;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final VoidCallback? activate = onPressed;
    Widget child = Semantics(
      label: label,
      button: true,
      enabled: activate != null,
      onTap: activate,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          onTap: activate,
          child: SizedBox.square(
            dimension: 30,
            child: Center(
              child: Icon(
                icon,
                size: 17,
                color: foreground.withValues(alpha: .75),
              ),
            ),
          ),
        ),
      ),
    );
    if (activate == null) return child;
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              activate();
              return null;
            },
          ),
        },
        child: Focus(child: child),
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
    this.hoverInert = false,
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
  final bool hoverInert;

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
    if (hoverInert) {
      return _FileTreeHoverInertAction(
        label: tooltip,
        icon: icon,
        foreground: foreground,
        onPressed: onPressed,
      );
    }
    return FileTreeTooltip(
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

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final double kib = bytes / 1024;
  if (kib < 1024) return '${kib.toStringAsFixed(kib >= 100 ? 0 : 1)} KB';
  final double mib = kib / 1024;
  if (mib < 1024) return '${mib.toStringAsFixed(mib >= 100 ? 0 : 2)} MB';
  final double gib = mib / 1024;
  return '${gib.toStringAsFixed(2)} GB';
}
