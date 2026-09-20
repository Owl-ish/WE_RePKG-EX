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
    this.showChanges = false,
  });

  final String wallpaperName;
  final String? liveFolder;
  final String? backupFolder;
  final String? rePKGPath;
  final BackupUpdateSelection? updateSelection;
  final WallpaperInfo? wallpaper;
  final bool showChanges;

  @override
  State<BackupFileBrowser> createState() => _BackupFileBrowserState();
}

class _BackupFileBrowserState extends State<BackupFileBrowser> {
  final LinkedVerticalScroll _scroll = LinkedVerticalScroll();
  Future<FolderFileComparison?>? _comparison;
  bool _showComparison = false;
  bool _comparisonRequested = false;

  @override
  void initState() {
    super.initState();
    if (widget.showChanges &&
        widget.liveFolder != null &&
        widget.backupFolder != null) {
      _requestComparison();
    }
  }

  void _requestComparison() {
    if (widget.updateSelection == null) {
      _comparison ??= compareFolderFilesDetailed(
        firstFolder: widget.liveFolder!,
        secondFolder: widget.backupFolder!,
      );
    }
    _comparisonRequested = true;
    _showComparison = true;
  }

  void _compare() {
    setState(_requestComparison);
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
            tr(
              liveFolder != null
                  ? AppI10n.backupLiveFiles
                  : AppI10n.backupBackupFiles,
            ),
            foreground,
            _scroll.first,
          );
        }
        final Widget live = _folder(
          liveFolder,
          tr(AppI10n.backupLiveFiles),
          foreground,
          _scroll.first,
        );
        final Widget backup = _folder(
          backupFolder,
          tr(AppI10n.backupBackupFiles),
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
    if (widget.updateSelection case final BackupUpdateSelection selection) {
      return UpdateFileChanges(
        wallpaper: widget.wallpaper,
        wallpaperName: widget.wallpaperName,
        liveFolder: widget.liveFolder,
        backupFolder: widget.backupFolder,
        sourceLabel: tr(AppI10n.backupLiveFiles),
        destinationLabel: tr(AppI10n.backupBackupFiles),
        rePKGPath: widget.rePKGPath,
        foreground: foreground,
        selection: selection,
      );
    }
    return FutureBuilder<FolderFileComparison?>(
      future: _comparison,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Center(child: Text(tr(AppI10n.backupDetailComparingFiles)));
        }
        final FolderFileComparison? result = snapshot.data;
        if (snapshot.hasError || result == null) {
          return Center(
            child: Text(tr(AppI10n.backupDetailFileComparisonUnavailable)),
          );
        }
        final FolderFileChanges changes = result.changes;
        if (changes.modified.isEmpty &&
            changes.onlyFirst.isEmpty &&
            changes.onlySecond.isEmpty) {
          return FileTreeScrollView(
            foreground: foreground,
            child: BackupDetailGroup(
              title: tr(AppI10n.backupDetailMatchingFiles),
              items: result.matching.isEmpty
                  ? <String>[tr(AppI10n.backupDetailSame)]
                  : result.matching,
              foreground: foreground,
            ),
          );
        }
        return FolderDifferenceFileTree(
          wallpaperName: widget.wallpaperName,
          changes: changes,
          firstFolder: widget.liveFolder,
          secondFolder: widget.backupFolder,
          firstLabel: tr(AppI10n.backupLiveFiles),
          secondLabel: tr(AppI10n.backupBackupFiles),
          modifiedTitle: tr(AppI10n.backupDetailModified),
          firstOnlyTitle: tr(AppI10n.backupLiveFiles),
          secondOnlyTitle: tr(AppI10n.backupBackupFiles),
          semanticLabel: tr(AppI10n.backupDetailFileChanges),
          unavailableText: tr(AppI10n.backupDetailFileComparisonUnavailable),
          openFolderTooltip: tr(AppI10n.homeOpenFileLocation),
          keyBase: 'backup-browser-comparison',
          firstSideId: 'live',
          secondSideId: 'backup',
          firstFolderActionKey: 'backup-browser-compare-live',
          secondFolderActionKey: 'backup-browser-compare-backup',
          rePKGPath: widget.rePKGPath,
          foreground: foreground,
        );
      },
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
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  if (widget.liveFolder case final String folder)
                    OutlinedButton.icon(
                      style: toolbarButtonStyle,
                      onPressed: () => browserFolder(folder),
                      icon: const Icon(Icons.folder_open_outlined),
                      label: Text(tr(AppI10n.backupOpenLiveFolder)),
                    ),
                  if (widget.backupFolder case final String folder)
                    OutlinedButton.icon(
                      style: toolbarButtonStyle,
                      onPressed: () => browserFolder(folder),
                      icon: const Icon(Icons.folder_open_outlined),
                      label: Text(tr(AppI10n.backupOpenBackupFolder)),
                    ),
                  if (widget.liveFolder != null && widget.backupFolder != null)
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
                child: IndexedStack(
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
