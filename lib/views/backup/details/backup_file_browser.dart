import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:we_repkg/actions/wallpaper_actions.dart';
import 'package:we_repkg/constants/i10n.dart';
import 'package:we_repkg/cores/backup.dart';
import 'package:we_repkg/models/wallpaper.dart';
import 'package:we_repkg/views/content/detail_dialog.dart';
import 'package:we_repkg/widgets/app_dialog_surface.dart';
import 'package:we_repkg/widgets/file_tree_panel.dart';
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
  bool _showComparison = false;
  bool _comparisonRequested = false;
  bool _deleting = false;

  String get _sourceLabel => widget.sourceLabel ?? tr(AppI10n.backupLiveFiles);
  String get _destinationLabel =>
      widget.destinationLabel ?? tr(AppI10n.backupBackupFiles);

  @override
  void initState() {
    super.initState();
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
    super.dispose();
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

  Widget _changes(Color foreground) {
    return UpdateFileChanges(
      wallpaper: widget.wallpaper,
      wallpaperName: widget.wallpaperName,
      liveFolder: widget.liveFolder,
      backupFolder: widget.backupFolder,
      sourceLabel: _sourceLabel,
      destinationLabel: _destinationLabel,
      sourceOnlyTitle: widget.sourceOnlyTitle,
      destinationOnlyTitle: widget.destinationOnlyTitle,
      sourceActions: widget.comparisonOnly
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
      destinationActions: widget.comparisonOnly
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
      includeMatchingFiles: widget.updateSelection == null,
      overview: widget.overview,
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
              const SizedBox(height: 16),
              Expanded(
                // Keep package sessions and folder expansion while switching views.
                child: widget.comparisonOnly
                    ? _changes(foreground)
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
