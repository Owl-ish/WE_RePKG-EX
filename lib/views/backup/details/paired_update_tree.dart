part of 'content_details.dart';

class _PairedUpdateTree extends StatefulWidget {
  const _PairedUpdateTree({
    super.key,
    required this.configuration,
    required this.changes,
    this.matching = const <String>[],
    required this.toolbar,
    required this.manualSelection,
    required this.manualAction,
    required this.onCompareSelect,
    this.fileAction,
    this.inspectPackages = true,
  });

  final Widget Function(String, bool)? fileAction;
  final bool inspectPackages;
  final UpdateFileChanges configuration;
  final BackupFileChanges changes;
  final List<String> matching;
  final Widget toolbar;
  final FileTreeCompareSelection manualSelection;
  final FileTreeCompareAction? manualAction;
  final void Function(FileTreeCompareCandidate, bool, bool) onCompareSelect;

  @override
  State<_PairedUpdateTree> createState() => _PairedUpdateTreeState();
}

class _PairedUpdateTreeState extends State<_PairedUpdateTree> {
  final LinkedVerticalScroll _scroll = LinkedVerticalScroll();
  final ScrollController _rail = ScrollController();
  final Set<String> _collapsed = <String>{};
  late Set<String> _added;
  late Set<String> _removed;
  late Set<String> _modified;
  late Set<String> _matching;

  UpdateFileChanges get config => widget.configuration;
  Color get foreground => config.foreground;

  @override
  void initState() {
    super.initState();
    _indexChanges();
    _scroll.first.addListener(_syncRail);
  }

  void _indexChanges() {
    _added = widget.changes.onlyLive.toSet();
    _removed = widget.changes.onlyBackup.toSet();
    _modified = widget.changes.modified.toSet();
    _matching = widget.matching.toSet();
  }

  @override
  void didUpdateWidget(covariant _PairedUpdateTree oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.changes != widget.changes ||
        oldWidget.matching != widget.matching) {
      _indexChanges();
      _collapsed.clear();
    }
  }

  void _syncRail() {
    if (!_scroll.first.hasClients ||
        !_rail.hasClients ||
        !_rail.position.hasContentDimensions) {
      return;
    }
    final double offset = _scroll.first.offset.clamp(
      0.0,
      _rail.position.maxScrollExtent,
    );
    if ((_rail.offset - offset).abs() > .1) _rail.jumpTo(offset);
  }

  @override
  void dispose() {
    _scroll.dispose();
    _rail.dispose();
    super.dispose();
  }

  List<({String name, String relative, bool folder, int depth})> _rows({
    bool includeCollapsed = false,
  }) {
    final Map<String, String> files = <String, String>{
      for (final String relative in <String>[
        ...widget.changes.modified,
        ...widget.changes.onlyLive,
        ...widget.changes.onlyBackup,
        ...widget.matching,
      ])
        relative.replaceAll('\\', '/'): relative,
    };
    final Set<String> folders = <String>{};
    for (final String file in files.keys) {
      final List<String> parts = file.split('/');
      for (int i = 1; i < parts.length; i++) {
        folders.add(parts.take(i).join('/'));
      }
    }
    final Map<String, List<String>> childrenByParent = <String, List<String>>{};
    for (final String entry in <String>[...folders, ...files.keys]) {
      final int slash = entry.lastIndexOf('/');
      final String parent = slash < 0 ? '' : entry.substring(0, slash);
      childrenByParent.putIfAbsent(parent, () => <String>[]).add(entry);
    }
    final List<({String name, String relative, bool folder, int depth})> rows =
        [];
    void visit(String parent, int depth) {
      final List<String> children = childrenByParent[parent] ?? <String>[]
        ..sort((String a, String b) {
          if (folders.contains(a) != folders.contains(b)) {
            return folders.contains(a) ? -1 : 1;
          }
          return a.toLowerCase().compareTo(b.toLowerCase());
        });
      for (final String child in children) {
        final bool folder = folders.contains(child);
        rows.add((
          name: child,
          relative: files[child] ?? child,
          folder: folder,
          depth: depth,
        ));
        if (folder && (includeCollapsed || !_collapsed.contains(child))) {
          visit(child, depth + 1);
        }
      }
    }

    visit('', 0);
    return rows;
  }

  bool _openingPackage = false;

  Future<void> _inspectPackage(String relative) async {
    if (_openingPackage) return;
    _openingPackage = true;
    final session = ScenePkgInspectionSession();
    bool transferred = false;
    try {
      // Do not construct the explorer until the confirmation has been accepted.
      if (!await _confirmPackageInspection(context, session) || !mounted) {
        return;
      }
      await showWallpaperDetailSurface(
        context: context,
        builder: (context) {
          transferred = true;
          final body = Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        tr(AppI10n.backupDetailInsidePackage),
                        style: TextStyle(color: foreground),
                      ),
                    ),
                    IconButton(
                      key: const ValueKey<String>('update-package-close'),
                      tooltip: tr(AppI10n.close),
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(Icons.close_rounded, color: foreground),
                    ),
                  ],
                ),
                Expanded(
                  child: _ScenePkgInspector(
                    wallpaperName: config.wallpaperName,
                    filePath: relative,
                    leftFolder: config.liveFolder!,
                    rightFolder: config.backupFolder!,
                    leftLabel: config.sourceLabel,
                    rightLabel: config.destinationLabel,
                    directionalVisual: true,
                    rePKGPath: config.rePKGPath,
                    foreground: foreground,
                    accent: Theme.of(context).status.warn,
                    confirmedSession: session,
                    fullView: true,
                  ),
                ),
              ],
            ),
          );
          final content = DefaultTextStyle.merge(
            style: TextStyle(color: foreground),
            child: IconTheme.merge(
              data: IconThemeData(color: foreground),
              child: body,
            ),
          );
          return LayoutBuilder(
            builder: (context, constraints) => AppDialogSurface(
              width: AppDialogSurface.fileViewSize(constraints.biggest).width,
              child: SizedBox(
                height: AppDialogSurface.fileViewSize(
                  constraints.biggest,
                ).height,
                child: config.wallpaper == null
                    ? content
                    : WallpaperDetailBackdrop(
                        wallpaper: config.wallpaper!,
                        child: content,
                      ),
              ),
            ),
          );
        },
      );
    } finally {
      if (!transferred) await session.dispose();
      _openingPackage = false;
    }
  }

  Future<void> _inspect(String relative) => showDialog<void>(
    context: context,
    builder: (BuildContext context) => LayoutBuilder(
      builder: (context, constraints) => AppDialogSurface(
        width: AppDialogSurface.fileViewSize(constraints.biggest).width,
        child: SizedBox(
          height: AppDialogSurface.fileViewSize(constraints.biggest).height,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        relative,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      key: const ValueKey<String>('update-file-details-close'),
                      tooltip: tr(AppI10n.close),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                Expanded(
                  child: FileTreeScrollView(
                    foreground: Theme.of(context).colorScheme.onSurface,
                    child: ListenableBuilder(
                      listenable:
                          config.selection ??
                          const AlwaysStoppedAnimation<int>(0),
                      builder: (context, _) => _ChangedFileGroup(
                        title: tr(AppI10n.backupDetailModified),
                        paths: <String>[relative],
                        wallpaperName: config.wallpaperName,
                        leftFolder: config.liveFolder,
                        rightFolder: config.backupFolder,
                        leftLabel: config.sourceLabel,
                        rightLabel: config.destinationLabel,
                        directionalVisual: true,
                        rePKGPath: config.rePKGPath,
                        colour: Theme.of(context).status.warn,
                        foreground: Theme.of(context).colorScheme.onSurface,
                        selection: config.selection,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _cell(
    ({String name, String relative, bool folder, int depth}) row,
    bool live,
  ) {
    final String side = live ? 'live' : 'backup';
    if (row.folder) {
      return FileTreeRow(
        key: ValueKey<String>('update-folder-$side-${row.name}'),
        depth: row.depth,
        icon: Icons.folder_open_outlined,
        disclosure: _collapsed.contains(row.name)
            ? Icons.chevron_right
            : Icons.expand_more,
        label: row.name.split('/').last,
        foreground: foreground,
        onTap: () => setState(() {
          if (!_collapsed.remove(row.name)) _collapsed.add(row.name);
        }),
      );
    }
    final bool added = _added.contains(row.relative);
    final bool removed = _removed.contains(row.relative);
    final bool missing = live ? removed : added;
    final BackupUpdateSelection? selection = config.selection;
    final FileTreeRowChoice? choice = live || selection == null
        ? null
        : removed
        ? _deletionChoice(selection, row.relative, foreground)
        : _copyChoice(selection, row.relative, foreground);
    final Color colour = added
        ? Theme.of(context).status.good
        : removed
        ? Theme.of(context).status.note
        : _modified.contains(row.relative)
        ? Theme.of(context).status.warn
        : Theme.of(context).status.good;
    if (missing) {
      return FileTreeRow(
        depth: row.depth,
        icon: Icons.remove_circle_outline,
        label: tr(
          live ? AppI10n.backupMissingLive : AppI10n.backupMissingBackup,
        ),
        tooltip: row.relative,
        foreground: foreground.withValues(alpha: .65),
        choice: choice,
      );
    }
    final String folder = (live ? config.liveFolder : config.backupFolder)!;
    final String label = live ? config.sourceLabel : config.destinationLabel;
    final bool inspectablePackage =
        widget.inspectPackages &&
        _modified.contains(row.relative) &&
        _pathNamed(row.relative, WallpaperFiles.packedScene);
    final FileTreeCompareCandidate? candidate = added || removed
        ? FileTreeCompareCandidate(
            id: '$side::${row.relative}',
            path: path.join(folder, row.relative),
            label: label,
          )
        : null;
    return _differenceFileRow(
      depth: row.depth,
      filePath: row.relative,
      displayLabel: row.name.split('/').last,
      colour: colour,
      foreground: foreground,
      firstFolder: folder,
      firstLabel: label,
      choice: choice,
      subtitle: removed && selection != null
          ? _deletionSubtitle(selection, row.relative)
          : null,
      compareCandidate: candidate,
      compareSelection: widget.manualSelection.selected,
      manualCompareAction: widget.manualAction,
      onCompareSelect: widget.onCompareSelect,
      onOpenDetails: inspectablePackage
          ? () => _inspectPackage(row.relative)
          : _modified.contains(row.relative)
          ? () => _inspect(row.relative)
          : null,
      extraTrailing:
          widget.fileAction?.call(row.relative, live) ??
          (inspectablePackage
              ? TextButton.icon(
                  key: ValueKey<String>(
                    'update-inspect-package-$side-${row.relative}',
                  ),
                  onPressed: () => _inspectPackage(row.relative),
                  icon: const Icon(Icons.manage_search_rounded, size: 16),
                  label: Text(tr(AppI10n.backupDetailInspectPackageAction)),
                )
              : null),
      pairedCompareAction: !added && !removed
          ? _fileCompareAction(
              firstLabel: config.sourceLabel,
              firstPath: path.join(config.liveFolder!, row.relative),
              secondLabel: config.destinationLabel,
              secondPath: path.join(config.backupFolder!, row.relative),
              foreground: foreground,
            )
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows();
    // Equal row heights keep missing counterparts and comparison actions aligned.
    final double rowHeight =
        35 * MediaQuery.textScalerOf(context).scale(12) / 12;
    Widget pane(bool live) => FileTreeScrollView(
      key: ValueKey<String>('update-paired-${live ? 'live' : 'backup'}'),
      verticalController: live ? _scroll.first : _scroll.second,
      foreground: foreground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final row in rows)
            SizedBox(
              key: ValueKey<String>(
                'paired-slot-${live ? 'live' : 'backup'}-${row.name}',
              ),
              height: rowHeight,
              child: Align(
                alignment: Alignment.centerLeft,
                child: KeyedSubtree(
                  key: ValueKey<String>(
                    'update-row-${live ? 'live' : 'backup'}-${row.relative}',
                  ),
                  child: _cell(row, live),
                ),
              ),
            ),
        ],
      ),
    );
    Widget rail() => Stack(
      children: <Widget>[
        Positioned.fill(
          child: Center(
            child: Container(
              width: 1,
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
        ),
        Positioned.fill(
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(
              context,
            ).copyWith(scrollbars: false),
            child: Padding(
              // Match the file surface's one-pixel border and bottom gutter.
              padding: const EdgeInsets.fromLTRB(0, 1, 0, 19),
              child: SingleChildScrollView(
                key: const ValueKey<String>('update-compare-rail'),
                controller: _rail,
                physics: const NeverScrollableScrollPhysics(),
                child: Column(
                  children: <Widget>[
                    const SizedBox(height: 6),
                    for (final row in rows)
                      SizedBox(
                        height: rowHeight,
                        child: Center(
                          child:
                              !row.folder &&
                                  (_modified.contains(row.relative) ||
                                      _matching.contains(row.relative))
                              ? _fileCompareAction(
                                  key: ValueKey<String>(
                                    'update-pair-compare-${row.relative}',
                                  ),
                                  firstLabel: config.sourceLabel,
                                  firstPath: path.join(
                                    config.liveFolder!,
                                    row.relative,
                                  ),
                                  secondLabel: config.destinationLabel,
                                  secondPath: path.join(
                                    config.backupFolder!,
                                    row.relative,
                                  ),
                                  foreground: foreground,
                                )
                              : const SizedBox.shrink(),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
    return TooltipVisibility(
      visible: !Platform.isWindows,
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: constraints.maxWidth < 640 ? 640 : constraints.maxWidth,
            height: constraints.maxHeight,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: constraints.maxHeight * .4,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      children: <Widget>[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Expanded(
                              child: _paneHeader(
                                config.sourceLabel,
                                config.sourceActions,
                              ),
                            ),
                            SizedBox(
                              width: 32,
                              child: Icon(
                                config.bidirectional
                                    ? Icons.compare_arrows_rounded
                                    : Icons.arrow_forward_rounded,
                                size: 22,
                                color: foreground,
                              ),
                            ),
                            Expanded(
                              child: _paneHeader(
                                config.destinationLabel,
                                config.destinationActions,
                              ),
                            ),
                          ],
                        ),
                        widget.toolbar,
                      ],
                    ),
                  ),
                ),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: FileTreeExpansionActions(
                          foreground: foreground,
                          onExpandAll: () => setState(_collapsed.clear),
                          onCollapseAll: () => setState(() {
                            _collapsed.addAll(
                              _rows(includeCollapsed: true)
                                  .where((row) => row.folder)
                                  .map((row) => row.name),
                            );
                          }),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 32,
                      child: ListenableBuilder(
                        listenable: _scroll,
                        builder: (context, _) => LinkedScrollToggle(
                          key: const ValueKey<String>('update-link-scrolling'),
                          linked: _scroll.linked,
                          onPressed: _scroll.toggle,
                          linkLabel: tr(AppI10n.backupLinkedScrolling),
                          unlinkLabel: tr(AppI10n.backupIndependentScrolling),
                        ),
                      ),
                    ),
                    const Expanded(child: SizedBox.shrink()),
                  ],
                ),
                Expanded(
                  flex: 3,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Expanded(child: pane(true)),
                      SizedBox(width: 32, child: rail()),
                      Expanded(child: pane(false)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _paneHeader(String label, Widget? actions) => Column(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(color: foreground, fontWeight: FontWeight.w600),
      ),
      if (actions != null) ...<Widget>[const SizedBox(height: 6), actions],
    ],
  );
}
