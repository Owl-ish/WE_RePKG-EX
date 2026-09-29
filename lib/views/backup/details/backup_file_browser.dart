import 'dart:async';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:we_repkg/actions/wallpaper_actions.dart';
import 'package:we_repkg/constants/i10n.dart';
import 'package:we_repkg/cores/backup.dart';
import 'package:we_repkg/cores/scene_pkg_inspection.dart';
import 'package:we_repkg/cores/toast.dart';
import 'package:we_repkg/models/wallpaper.dart';
import 'package:we_repkg/views/content/detail_dialog.dart';
import 'package:we_repkg/widgets/app_dialog_surface.dart';
import 'package:we_repkg/widgets/file_tree_panel.dart';
import 'package:we_repkg/widgets/input_controls.dart';
import 'package:we_repkg/widgets/linked_scroll.dart';

import 'content_details.dart';

/// Shared file dialog for browsing and changes; Update retains its session's choices.
class BackupFileBrowser extends StatefulWidget {
  const BackupFileBrowser({
    super.key,
    required this.wallpaperName,
    required this.liveFolder,
    required this.backupFolder,
    this.rePKGPath,
    this.updateSelection,
    this.wallpaper,
    this.overview,
    this.underlyingDifferences,
    this.packedSource,
    this.underlyingIncomplete = false,
    this.semanticMatch = false,
    this.defaultTrueDifferences = false,
    this.showChanges = false,
    this.comparisonOnly = false,
    this.sourceLabel,
    this.destinationLabel,
    this.sourceOnlyTitle,
    this.destinationOnlyTitle,
    this.sourceOpenLabel,
    this.destinationOpenLabel,
    this.sourceDeleteLabel,
    this.destinationDeleteLabel,
    this.onDeleteSource,
    this.onDeleteDestination,
  });

  final String wallpaperName;
  final String? liveFolder;
  final String? backupFolder;
  final String? rePKGPath;
  final BackupUpdateSelection? updateSelection;
  final WallpaperInfo? wallpaper;
  final FolderFileOverview? overview;
  final FolderFileOverview? underlyingDifferences;
  final bool? packedSource;
  final bool underlyingIncomplete;
  final bool semanticMatch;
  final bool defaultTrueDifferences;
  final bool showChanges;
  final bool comparisonOnly;
  final String? sourceLabel;
  final String? destinationLabel;
  final String? sourceOnlyTitle;
  final String? destinationOnlyTitle;
  final String? sourceOpenLabel;
  final String? destinationOpenLabel;
  final String? sourceDeleteLabel;
  final String? destinationDeleteLabel;
  final Future<bool> Function()? onDeleteSource;
  final Future<bool> Function()? onDeleteDestination;

  @override
  State<BackupFileBrowser> createState() => _BackupFileBrowserState();
}

class _BackupFileBrowserState extends State<BackupFileBrowser> {
  final LinkedVerticalScroll _scroll = LinkedVerticalScroll();
  final ScenePkgInspectionSession _underlyingSession =
      ScenePkgInspectionSession();
  bool _showComparison = false;
  bool _comparisonRequested = false;
  bool _deleting = false;
  bool _showUnderlying = false;
  bool _unpacking = false;
  bool _showExtracted = false;
  String? _extractedFolder;
  FolderFileOverview? _extractedOverview;

  String get _sourceLabel => widget.sourceLabel ?? tr(AppI10n.backupLiveFiles);
  String get _destinationLabel =>
      widget.destinationLabel ?? tr(AppI10n.backupBackupFiles);

  @override
  void initState() {
    super.initState();
    _showUnderlying =
        widget.defaultTrueDifferences && widget.underlyingDifferences != null;
    if ((widget.showChanges || widget.comparisonOnly) &&
        widget.liveFolder != null &&
        widget.backupFolder != null) {
      _requestComparison();
    }
  }

  void _requestComparison() {
    _comparisonRequested = true;
    _showComparison = true;
  }

  void _compare() {
    setState(_requestComparison);
  }

  Future<void> _unpack() async {
    if (_unpacking || widget.packedSource == null || widget.rePKGPath == null) {
      return;
    }
    final bool packedSource = widget.packedSource!;
    final String? packedFolder = packedSource
        ? widget.liveFolder
        : widget.backupFolder;
    final String? otherFolder = packedSource
        ? widget.backupFolder
        : widget.liveFolder;
    if (packedFolder == null || otherFolder == null) return;
    setState(() => _unpacking = true);
    try {
      final String? extracted = await _underlyingSession.unpackForInspection(
        packedFolder: Directory(packedFolder),
        tool: widget.rePKGPath!,
      );
      if (extracted == null) return;
      final FolderFileOverview? overview = await compareFolderFileOverview(
        firstFolder: packedSource ? extracted : otherFolder,
        secondFolder: packedSource ? otherFolder : extracted,
      );
      if (!mounted) return;
      if (overview == null) {
        showErrorToast(tr(AppI10n.backupDetailUnpackFailed));
        return;
      }
      setState(() {
        _extractedFolder = extracted;
        _extractedOverview = overview;
        _showExtracted = true;
      });
    } catch (_) {
      if (mounted) showErrorToast(tr(AppI10n.backupDetailUnpackFailed));
    } finally {
      if (mounted) setState(() => _unpacking = false);
    }
  }

  Future<void> _delete(Future<bool> Function() action) async {
    if (_deleting) return;
    setState(() => _deleting = true);
    final bool resolved = await action();
    if (!mounted) return;
    if (resolved) {
      Navigator.of(context).pop();
    } else {
      setState(() => _deleting = false);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    unawaited(_underlyingSession.dispose());
    super.dispose();
  }

  Future<({String firstPath, String secondPath})?> _prepareUnderlyingComparison(
    String relativePath,
  ) async {
    final bool packedSource = widget.packedSource!;
    final String? packedFolder = packedSource
        ? widget.liveFolder
        : widget.backupFolder;
    final String? unpackedFolder = packedSource
        ? widget.backupFolder
        : widget.liveFolder;
    if (packedFolder == null || unpackedFolder == null) return null;
    final prepared = await _underlyingSession.preparePackedComparison(
      packedFolder: Directory(packedFolder),
      unpackedFolder: Directory(unpackedFolder),
      relativePath: relativePath,
      tool: widget.rePKGPath,
    );
    if (prepared == null) return null;
    return packedSource
        ? (firstPath: prepared.packedPath, secondPath: prepared.unpackedPath)
        : (firstPath: prepared.unpackedPath, secondPath: prepared.packedPath);
  }

  Widget _folder(
    String folder,
    String label,
    Color foreground,
    ScrollController controller,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.titleSmall?.copyWith(color: foreground),
      ),
      const SizedBox(height: 8),
      Expanded(
        child: FileTreePanel(
          folderPath: folder,
          foreground: foreground,
          verticalController: controller,
        ),
      ),
    ],
  );

  Widget _folders(Color foreground) {
    final String? liveFolder = widget.liveFolder;
    final String? backupFolder = widget.backupFolder;
    final bool paired = liveFolder != null && backupFolder != null;
    Widget toggle() => ListenableBuilder(
      listenable: _scroll,
      builder: (context, _) => LinkedScrollToggle(
        key: const ValueKey<String>('backup-browser-link-scrolling'),
        linked: _scroll.linked,
        onPressed: _scroll.toggle,
        linkLabel: tr(AppI10n.backupLinkedScrolling),
        unlinkLabel: tr(AppI10n.backupIndependentScrolling),
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (liveFolder == null && backupFolder == null) {
          return const SizedBox.shrink();
        }
        if (!paired) {
          final String folder = liveFolder ?? backupFolder!;
          return _folder(
            folder,
            liveFolder != null ? _sourceLabel : _destinationLabel,
            foreground,
            _scroll.first,
          );
        }
        final Widget live = _folder(
          liveFolder,
          _sourceLabel,
          foreground,
          _scroll.first,
        );
        final Widget backup = _folder(
          backupFolder,
          _destinationLabel,
          foreground,
          _scroll.second,
        );
        if (constraints.maxWidth < 700) {
          return Column(
            children: <Widget>[
              Expanded(child: live),
              SizedBox(height: 34, child: Center(child: toggle())),
              Expanded(child: backup),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(child: live),
            SizedBox(
              width: 32,
              child: Column(
                children: <Widget>[
                  toggle(),
                  Expanded(
                    child: VerticalDivider(
                      width: 1,
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: backup),
          ],
        );
      },
    );
  }

  Widget _changes(
    Color foreground, {
    bool underlying = false,
    bool extracted = false,
  }) {
    final bool packedSource = widget.packedSource == true;
    final String? sourceFolder = extracted && packedSource
        ? _extractedFolder
        : widget.liveFolder;
    final String? destinationFolder = extracted && !packedSource
        ? _extractedFolder
        : widget.backupFolder;
    return UpdateFileChanges(
      key: ValueKey<String>(
        extracted
            ? 'extracted-package'
            : underlying
            ? 'true-differences'
            : 'folder-files',
      ),
      wallpaper: widget.wallpaper,
      wallpaperName: widget.wallpaperName,
      liveFolder: sourceFolder,
      backupFolder: destinationFolder,
      sourceLabel: extracted && packedSource
          ? '$_sourceLabel · ${tr(AppI10n.backupDetailUnpackedPreview)}'
          : _sourceLabel,
      destinationLabel: extracted && !packedSource
          ? '$_destinationLabel · ${tr(AppI10n.backupDetailUnpackedPreview)}'
          : _destinationLabel,
      sourceOnlyTitle: underlying
          ? tr(
              widget.packedSource == true
                  ? AppI10n.backupDetailOnlyPacked
                  : AppI10n.backupDetailOnlyUnpacked,
            )
          : widget.sourceOnlyTitle,
      destinationOnlyTitle: underlying
          ? tr(
              widget.packedSource == false
                  ? AppI10n.backupDetailOnlyPacked
                  : AppI10n.backupDetailOnlyUnpacked,
            )
          : widget.destinationOnlyTitle,
      sourceActions: widget.comparisonOnly && !extracted
          ? _paneActions(
              folder: widget.liveFolder,
              openLabel:
                  widget.sourceOpenLabel ?? tr(AppI10n.backupOpenLiveFolder),
              openKey: 'backup-file-view-open-source',
              deleteLabel: widget.sourceDeleteLabel,
              deleteKey: 'backup-file-view-delete-source',
              onDelete: widget.onDeleteSource,
            )
          : null,
      destinationActions: widget.comparisonOnly && !extracted
          ? _paneActions(
              folder: widget.backupFolder,
              openLabel:
                  widget.destinationOpenLabel ??
                  tr(AppI10n.backupOpenBackupFolder),
              openKey: 'backup-file-view-open-destination',
              deleteLabel: widget.destinationDeleteLabel,
              deleteKey: 'backup-file-view-delete-destination',
              onDelete: widget.onDeleteDestination,
            )
          : null,
      bidirectional: widget.comparisonOnly,
      includeMatchingFiles:
          extracted || (!underlying && widget.updateSelection == null),
      overview: extracted
          ? _extractedOverview
          : underlying
          ? widget.underlyingDifferences
          : widget.overview,
      virtualPackedSource: underlying ? widget.packedSource : null,
      prepareUnderlyingComparison: underlying
          ? _prepareUnderlyingComparison
          : null,
      emptyMessage: underlying
          ? tr(
              widget.semanticMatch
                  ? AppI10n.backupDetailIdenticalContents
                  : AppI10n.backupDetailNoConfirmedPaths,
            )
          : null,
      rePKGPath: widget.rePKGPath,
      foreground: foreground,
      selection: widget.updateSelection,
    );
  }

  Widget _paneActions({
    required String? folder,
    required String openLabel,
    required String openKey,
    required String? deleteLabel,
    required String deleteKey,
    required Future<bool> Function()? onDelete,
  }) {
    final ColorScheme colours = Theme.of(context).colorScheme;
    final ButtonStyle openStyle = OutlinedButton.styleFrom(
      foregroundColor: colours.onSurface,
      backgroundColor: colours.surface.withValues(alpha: .9),
      side: BorderSide(color: colours.outline),
      visualDensity: VisualDensity.compact,
    );
    final ButtonStyle deleteStyle = OutlinedButton.styleFrom(
      foregroundColor: colours.onErrorContainer,
      backgroundColor: colours.errorContainer,
      side: BorderSide(color: colours.error),
      visualDensity: VisualDensity.compact,
    );
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 6,
      children: <Widget>[
        if (folder != null)
          OutlinedButton.icon(
            key: ValueKey<String>(openKey),
            style: openStyle,
            onPressed: () => browserFolder(folder),
            icon: const Icon(Icons.folder_open_outlined, size: 17),
            label: Text(openLabel),
          ),
        if (onDelete != null)
          OutlinedButton.icon(
            key: ValueKey<String>(deleteKey),
            style: deleteStyle,
            onPressed: _deleting ? null : () => _delete(onDelete),
            icon: const Icon(Icons.delete_outline_rounded, size: 17),
            label: Text(
              deleteLabel ?? tr(AppI10n.backupActionDeleteLiveVersion),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final Color foreground = widget.wallpaper == null
        ? Theme.of(context).colorScheme.onSurface
        : WallpaperDetailBackdrop.foreground;
    final ButtonStyle toolbarButtonStyle = OutlinedButton.styleFrom(
      foregroundColor: Theme.of(context).colorScheme.onSurface,
      backgroundColor: Theme.of(
        context,
      ).colorScheme.surface.withValues(alpha: .9),
      side: BorderSide(color: Theme.of(context).colorScheme.outline),
    );
    final ButtonStyle deleteButtonStyle = OutlinedButton.styleFrom(
      foregroundColor: Theme.of(context).colorScheme.onErrorContainer,
      backgroundColor: Theme.of(context).colorScheme.errorContainer,
      side: BorderSide(color: Theme.of(context).colorScheme.error),
    );
    final Widget content = Padding(
      padding: const EdgeInsets.all(16),
      child: DefaultTextStyle.merge(
        style: TextStyle(color: foreground),
        child: IconTheme.merge(
          data: IconThemeData(color: foreground),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      '${tr(AppI10n.backupDetailFileChanges)} — ${widget.wallpaperName}',
                      style: Theme.of(
                        context,
                      ).textTheme.titleLarge?.copyWith(color: foreground),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey<String>('backup-file-view-close'),
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: tr(AppI10n.close),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              if (!widget.comparisonOnly)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    if (widget.liveFolder case final String folder)
                      OutlinedButton.icon(
                        style: toolbarButtonStyle,
                        onPressed: () => browserFolder(folder),
                        icon: const Icon(Icons.folder_open_outlined),
                        label: Text(
                          widget.sourceOpenLabel ??
                              tr(AppI10n.backupOpenLiveFolder),
                        ),
                      ),
                    if (widget.onDeleteSource
                        case final Future<bool> Function() delete)
                      OutlinedButton.icon(
                        key: const ValueKey<String>(
                          'backup-file-view-delete-source',
                        ),
                        style: deleteButtonStyle,
                        onPressed: _deleting ? null : () => _delete(delete),
                        icon: const Icon(Icons.delete_outline_rounded),
                        label: Text(
                          widget.sourceDeleteLabel ??
                              tr(AppI10n.backupActionDeleteLiveVersion),
                        ),
                      ),
                    if (widget.backupFolder case final String folder)
                      OutlinedButton.icon(
                        style: toolbarButtonStyle,
                        onPressed: () => browserFolder(folder),
                        icon: const Icon(Icons.folder_open_outlined),
                        label: Text(
                          widget.destinationOpenLabel ??
                              tr(AppI10n.backupOpenBackupFolder),
                        ),
                      ),
                    if (widget.onDeleteDestination
                        case final Future<bool> Function() delete)
                      OutlinedButton.icon(
                        key: const ValueKey<String>(
                          'backup-file-view-delete-destination',
                        ),
                        style: deleteButtonStyle,
                        onPressed: _deleting ? null : () => _delete(delete),
                        icon: const Icon(Icons.delete_outline_rounded),
                        label: Text(
                          widget.destinationDeleteLabel ??
                              tr(AppI10n.backupActionDeleteLiveVersion),
                        ),
                      ),
                    if (widget.liveFolder != null &&
                        widget.backupFolder != null)
                      OutlinedButton(
                        style: toolbarButtonStyle,
                        onPressed: _showComparison
                            ? () => setState(() => _showComparison = false)
                            : _compare,
                        child: Text(
                          tr(
                            _showComparison
                                ? AppI10n.backupBrowseFiles
                                : AppI10n.backupDetailCompareFiles,
                          ),
                        ),
                      ),
                  ],
                ),
              if (widget.comparisonOnly &&
                  widget.underlyingDifferences != null) ...<Widget>[
                const SizedBox(height: 4),
                Center(
                  child: SlidingSegmentedToggle(
                    key: const ValueKey<String>(
                      'backup-difference-view-toggle',
                    ),
                    firstLabel: tr(AppI10n.backupDetailBackupFolderFiles),
                    secondLabel: tr(AppI10n.backupDetailTrueDifferences),
                    secondSelected: _showUnderlying,
                    onChanged: (value) => setState(() {
                      _showUnderlying = value;
                      _showExtracted = false;
                    }),
                  ),
                ),
                if (_showUnderlying)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      tr(
                        widget.underlyingIncomplete
                            ? AppI10n.backupDetailUnderlyingIncomplete
                            : AppI10n.backupDetailUnderlyingInsidePackage,
                      ),
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: foreground),
                    ),
                  ),
              ],
              if (widget.comparisonOnly &&
                  widget.packedSource != null) ...<Widget>[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    key: const ValueKey<String>('backup-unpack-for-inspection'),
                    style: toolbarButtonStyle,
                    onPressed:
                        _unpacking ||
                            (_extractedFolder == null &&
                                widget.rePKGPath == null)
                        ? null
                        : _extractedFolder == null
                        ? _unpack
                        : () => setState(() {
                            _showExtracted = !_showExtracted;
                          }),
                    icon: _unpacking
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.inventory_2_outlined, size: 18),
                    label: Text(
                      tr(
                        _unpacking
                            ? AppI10n.backupDetailUnpackingPackage
                            : _extractedFolder == null
                            ? AppI10n.backupDetailUnpackForInspection
                            : _showExtracted
                            ? AppI10n.backupDetailShowOriginalFiles
                            : AppI10n.backupDetailShowUnpackedFiles,
                      ),
                    ),
                  ),
                ),
              ],
              if (widget.semanticMatch || _showExtracted) ...<Widget>[
                const SizedBox(height: 8),
                Container(
                  key: const ValueKey<String>('backup-comparison-banner'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    tr(
                      _showExtracted
                          ? AppI10n.backupDetailTemporaryUnpackedView
                          : AppI10n.backupDetailPackedUnpackedMatchBanner,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Expanded(
                // Keep package sessions and folder expansion while switching views.
                child: widget.comparisonOnly
                    ? _showExtracted
                          ? _changes(foreground, extracted: true)
                          : widget.underlyingDifferences == null
                          ? _changes(foreground)
                          : IndexedStack(
                              index: _showUnderlying ? 1 : 0,
                              children: <Widget>[
                                _changes(foreground),
                                _changes(foreground, underlying: true),
                              ],
                            )
                    : IndexedStack(
                        index: _showComparison ? 1 : 0,
                        children: <Widget>[
                          _folders(foreground),
                          if (_comparisonRequested) _changes(foreground),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
    return TooltipVisibility(
      visible: !Platform.isWindows,
      child: LayoutBuilder(
        builder: (context, constraints) => AppDialogSurface(
          width: AppDialogSurface.fileViewSize(constraints.biggest).width,
          child: SizedBox(
            height: AppDialogSurface.fileViewSize(constraints.biggest).height,
            child: widget.wallpaper != null
                ? WallpaperDetailBackdrop(
                    wallpaper: widget.wallpaper!,
                    child: content,
                  )
                : content,
          ),
        ),
      ),
    );
  }
}
