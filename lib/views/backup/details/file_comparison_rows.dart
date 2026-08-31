part of 'content_details.dart';

//====================
// File-Type Comparisons
//====================
/// Expands a modified JSON file into field-level differences on demand.
class _JsonFileDiff extends StatefulWidget {
  const _JsonFileDiff({
    super.key,
    required this.depth,
    required this.filePath,
    required this.beforeFolder,
    required this.afterFolder,
    required this.beforeLabel,
    required this.afterLabel,
    required this.colour,
    required this.foreground,
    this.subtitle,
    this.choice,
    this.hoverHighlight = true,
  });

  final int depth;
  final String filePath;
  final String beforeFolder;
  final String afterFolder;
  final String beforeLabel;
  final String afterLabel;
  final Color colour;
  final Color foreground;
  final String? subtitle;
  final FileTreeRowChoice? choice;
  final bool hoverHighlight;

  @override
  State<_JsonFileDiff> createState() => _JsonFileDiffState();
}

class _JsonFileDiffState extends State<_JsonFileDiff> {
  Future<List<BackupJsonFieldChange>?>? _changes;
  bool _expanded = false;

  @override
  void didUpdateWidget(covariant _JsonFileDiff oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filePath != widget.filePath ||
        oldWidget.beforeFolder != widget.beforeFolder ||
        oldWidget.afterFolder != widget.afterFolder) {
      _changes = null;
      _expanded = false;
    }
  }

  Future<List<BackupJsonFieldChange>?> _read() => compareBackupJsonChanges(
    beforeFolder: widget.beforeFolder,
    afterFolder: widget.afterFolder,
    relativePath: widget.filePath,
  );

  void _toggle() {
    setState(() {
      _expanded = !_expanded;
      if (_expanded) _changes ??= _read();
    });
  }

  Widget _rootRow({required bool loading}) {
    final FileTreeCompareAction compareAction = _fileCompareAction(
      key: ValueKey<String>('backup-file-compare-${widget.filePath}'),
      firstLabel: widget.beforeLabel,
      firstPath: path.join(widget.beforeFolder, widget.filePath),
      secondLabel: widget.afterLabel,
      secondPath: path.join(widget.afterFolder, widget.filePath),
      foreground: widget.foreground,
      hoverInert: !widget.hoverHighlight,
    );
    return FileTreeRow(
      key: ValueKey<String>('backup-json-${widget.filePath}'),
      depth: widget.depth,
      disclosure: _expanded
          ? Icons.keyboard_arrow_down_rounded
          : Icons.keyboard_arrow_right_rounded,
      icon: Icons.data_object_rounded,
      iconColor: widget.colour,
      label: _treePath(widget.filePath),
      subtitle: widget.subtitle,
      foreground: widget.foreground,
      onTap: _toggle,
      tooltip: widget.hoverHighlight
          ? tr(
              _expanded
                  ? AppI10n.backupDetailCollapseJson
                  : AppI10n.backupDetailExpandJson,
            )
          : null,
      hoverHighlight: widget.hoverHighlight,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (loading) ...<Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: SizedBox.square(
                dimension: 13,
                child: CircularProgressIndicator(
                  strokeWidth: 1.8,
                  color: widget.foreground.withValues(alpha: .65),
                ),
              ),
            ),
          ],
          compareAction,
        ],
      ),
      choice: widget.choice,
      contextActions: <FileTreeContextAction>[
        _compareContextAction(compareAction),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final Future<List<BackupJsonFieldChange>?>? changes = _expanded
        ? (_changes ??= _read())
        : null;
    // Keep the disclosure row under the same FutureBuilder/Column for its whole
    // lifetime. Moving that interactive row under a new parent on expansion
    // recreates its semantics node, which can make the Windows AX bridge reject
    // the same-frame tree update while the JSON children are materializing.
    return FutureBuilder<List<BackupJsonFieldChange>?>(
      future: changes,
      builder:
          (
            BuildContext context,
            AsyncSnapshot<List<BackupJsonFieldChange>?> snapshot,
          ) {
            final List<Widget> rows = <Widget>[
              _rootRow(
                loading:
                    _expanded &&
                    snapshot.connectionState != ConnectionState.done,
              ),
            ];
            if (!_expanded ||
                snapshot.connectionState != ConnectionState.done) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: rows,
              );
            }
            final List<BackupJsonFieldChange>? fieldChanges = snapshot.data;
            if (snapshot.hasError || fieldChanges == null) {
              rows.add(
                FileTreeRow(
                  depth: widget.depth + 1,
                  icon: Icons.info_outline_rounded,
                  label: tr(AppI10n.backupDetailJsonUnavailable),
                  foreground: widget.foreground,
                ),
              );
            } else if (fieldChanges.isEmpty) {
              rows.add(
                FileTreeRow(
                  depth: widget.depth + 1,
                  icon: Icons.format_align_left_rounded,
                  label: tr(AppI10n.backupDetailJsonFormattingOnly),
                  foreground: widget.foreground,
                ),
              );
            } else {
              final int visibleCount =
                  fieldChanges.length < _inlineJsonChangePreviewLimit
                  ? fieldChanges.length
                  : _inlineJsonChangePreviewLimit;
              for (final BackupJsonFieldChange change in fieldChanges.take(
                visibleCount,
              )) {
                rows.add(
                  FileTreeRow(
                    depth: widget.depth + 1,
                    icon: Icons.compare_arrows_rounded,
                    label: formatJsonFieldPath(change.field),
                    subtitle:
                        '${_jsonChangeValue(change.before, change.beforePresent)}  →  '
                        '${_jsonChangeValue(change.after, change.afterPresent)}',
                    foreground: widget.foreground,
                    iconColor: widget.colour,
                  ),
                );
              }
              if (fieldChanges.length > visibleCount) {
                final String previewText =
                    tr(AppI10n.backupDetailJsonPreviewLimited)
                        .replaceAll('{shown}', '$visibleCount')
                        .replaceAll('{total}', '${fieldChanges.length}');
                rows.add(
                  FileTreeRow(
                    depth: widget.depth + 1,
                    icon: Icons.more_horiz_rounded,
                    label: previewText,
                    foreground: widget.foreground,
                    iconColor: widget.colour,
                  ),
                );
              }
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: rows,
            );
          },
    );
  }
}

Widget _differenceFileEntry({
  required int depth,
  required String filePath,
  required Color colour,
  required Color foreground,
  String? firstFolder,
  String? firstLabel,
  String? secondFolder,
  String? secondLabel,
  bool directional = false,
  String? subtitle,
  FileTreeRowChoice? choice,
  FileTreeCompareCandidate? compareCandidate,
  Set<String> compareSelection = const <String>{},
  FileTreeCompareAction? manualCompareAction,
  void Function(FileTreeCompareCandidate, bool, bool)? onCompareSelect,
  bool hoverHighlight = true,
}) {
  if (_isJsonPath(filePath) && firstFolder != null && secondFolder != null) {
    return _JsonFileDiff(
      key: ValueKey<String>('backup-json-diff-$filePath'),
      depth: depth,
      filePath: filePath,
      beforeFolder: firstFolder,
      afterFolder: secondFolder,
      beforeLabel: firstLabel ?? path.basename(firstFolder),
      afterLabel: secondLabel ?? path.basename(secondFolder),
      colour: colour,
      foreground: foreground,
      subtitle: subtitle,
      choice: choice,
      hoverHighlight: hoverHighlight,
    );
  }
  return _differenceFileRow(
    depth: depth,
    filePath: filePath,
    colour: colour,
    foreground: foreground,
    firstFolder: firstFolder,
    firstLabel: firstLabel,
    secondFolder: secondFolder,
    secondLabel: secondLabel,
    directional: directional,
    subtitle: subtitle,
    choice: choice,
    compareCandidate: compareCandidate,
    compareSelection: compareSelection,
    manualCompareAction: manualCompareAction,
    onCompareSelect: onCompareSelect,
    hoverHighlight: hoverHighlight,
  );
}

String _jsonChangeValue(Object? value, bool present) {
  if (!present) return tr(AppI10n.backupDetailValueMissing);
  final String encoded = jsonEncode(value);
  const int maxLength = 160;
  return encoded.length <= maxLength
      ? encoded
      : '${encoded.substring(0, maxLength - 1)}…';
}

String _treePath(String filePath) =>
    filePath.replaceAll('\\', '  ›  ').replaceAll('/', '  ›  ');

String _oldImageLabel(String? label) => label == null
    ? tr(AppI10n.backupDetailOldVersion)
    : '${tr(AppI10n.backupDetailOldVersion)} · $label';

String _newImageLabel(String? label) => label == null
    ? tr(AppI10n.backupDetailNewVersion)
    : '${tr(AppI10n.backupDetailNewVersion)} · $label';

Widget _differenceFileRow({
  required int depth,
  required String filePath,
  required Color colour,
  required Color foreground,
  String? firstFolder,
  String? firstLabel,
  String? secondFolder,
  String? secondLabel,
  bool directional = false,
  String? subtitle,
  FileTreeRowChoice? choice,
  FileTreeCompareCandidate? compareCandidate,
  Set<String> compareSelection = const <String>{},
  FileTreeCompareAction? manualCompareAction,
  void Function(FileTreeCompareCandidate, bool, bool)? onCompareSelect,
  bool hoverHighlight = true,
}) {
  final bool image = isPreviewableImagePath(filePath);
  final bool hasFirst = firstFolder != null && firstLabel != null;
  final bool hasSecond = secondFolder != null && secondLabel != null;
  final bool canDirectCompare = hasFirst && hasSecond;
  final bool canPreview = image && hasFirst;

  final FileTreeCompareAction? directCompareAction = canDirectCompare
      ? _fileCompareAction(
          key: ValueKey<String>(
            image
                ? 'backup-image-compare-$filePath'
                : 'backup-file-compare-$filePath',
          ),
          firstLabel: firstLabel,
          firstPath: path.join(firstFolder, filePath),
          secondLabel: secondLabel,
          secondPath: path.join(secondFolder, filePath),
          foreground: foreground,
          hoverInert: !hoverHighlight,
        )
      : null;
  final Widget? trailing =
      directCompareAction ??
      (canPreview
          ? FileTreeImageAction(
              key: ValueKey<String>('backup-image-preview-$filePath'),
              first: FileImageSide(
                label: firstLabel,
                path: path.join(firstFolder, filePath),
              ),
              directional: directional,
              title: tr(AppI10n.backupDetailPreviewImage),
              tooltip: tr(AppI10n.backupDetailPreviewImage),
              unavailableText: tr(AppI10n.backupDetailImageUnavailable),
              zoomOutTooltip: tr(AppI10n.backupDetailImageZoomOut),
              resetViewTooltip: tr(AppI10n.backupDetailImageResetView),
              zoomInTooltip: tr(AppI10n.backupDetailImageZoomIn),
              linkViewsTooltip: tr(AppI10n.backupDetailImageLinkViews),
              unlinkViewsTooltip: tr(AppI10n.backupDetailImageUnlinkViews),
              sideBySideLabel: tr(AppI10n.backupDetailImageSideBySide),
              overlayLabel: tr(AppI10n.backupDetailImageOverlay),
              blinkLabel: tr(AppI10n.backupDetailImageBlink),
              differenceLabel: tr(AppI10n.backupDetailImageDifference),
              overlayOpacityLabel: tr(AppI10n.backupDetailImageOverlayOpacity),
              differenceSameHint: tr(
                AppI10n.backupDetailImageDifferenceSameHint,
              ),
              differenceSizeMismatch: tr(
                AppI10n.backupDetailImageDifferenceSizeMismatch,
              ),
              foreground: foreground,
              hoverInert: !hoverHighlight,
            )
          : null);

  final bool manualCompareEnabled =
      compareCandidate != null &&
      compareSelection.contains(compareCandidate.id) &&
      manualCompareAction != null;
  final List<FileTreeContextAction> contextActions = <FileTreeContextAction>[
    if (directCompareAction != null)
      _compareContextAction(directCompareAction)
    else if (compareCandidate != null)
      FileTreeContextAction(
        label: tr(AppI10n.backupDetailCompareFiles),
        enabled: manualCompareEnabled,
        onSelected: (BuildContext context) {
          final FileTreeCompareAction? action = manualCompareAction;
          if (action != null) unawaited(action.open(context));
        },
      ),
  ];

  return FileTreeRow(
    depth: depth,
    icon: image ? Icons.image_outlined : Icons.insert_drive_file_outlined,
    iconColor: colour,
    label: _treePath(filePath),
    key: compareCandidate == null
        ? null
        : ValueKey<String>('backup-manual-compare-${compareCandidate.id}'),
    subtitle: subtitle,
    foreground: foreground,
    selected:
        compareCandidate != null &&
        compareSelection.contains(compareCandidate.id),
    onSelectionTap: compareCandidate == null || onCompareSelect == null
        ? null
        : (bool control, bool shift) =>
              onCompareSelect(compareCandidate, control, shift),
    trailing: trailing,
    choice: choice,
    hoverHighlight: hoverHighlight,
    contextActions: contextActions,
  );
}
