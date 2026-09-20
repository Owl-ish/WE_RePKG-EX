part of 'file_tree_panel.dart';

/// Reusable read-only folder tree for details surfaces.
class FileTreePanel extends StatefulWidget {
  const FileTreePanel({
    super.key,
    required this.folderPath,
    required this.foreground,
    this.library,
    this.accent,
    this.maxHeight,
    this.verticalController,
  });

  final String folderPath;
  final Color foreground;
  final FileTreeLibrary? library;
  final Color? accent;
  final double? maxHeight;

  /// The caller retains ownership when linking two folder views.
  final ScrollController? verticalController;

  @override
  State<FileTreePanel> createState() => _FileTreePanelState();
}

class _FileTreePanelState extends State<FileTreePanel> {
  late Future<List<FileSystemEntity>> _children;
  ({bool expanded, int revision}) _expansion = (expanded: true, revision: 0);

  void _setExpanded(bool expanded) => setState(() {
    _expansion = (expanded: expanded, revision: _expansion.revision + 1);
  });

  @override
  void initState() {
    super.initState();
    _children = _listTreeChildren(widget.folderPath);
  }

  @override
  void didUpdateWidget(covariant FileTreePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.folderPath != widget.folderPath) {
      _children = _listTreeChildren(widget.folderPath);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color? accent = widget.library == null
        ? widget.accent
        : fileTreeLibraryColour(context, widget.library!);
    return FileTreeScrollView(
      key: ValueKey<String>('file-tree-${widget.folderPath}'),
      foreground: widget.foreground,
      maxHeight: widget.maxHeight,
      verticalController: widget.verticalController,
      child: FutureBuilder<List<FileSystemEntity>>(
        future: _children,
        builder:
            (
              BuildContext context,
              AsyncSnapshot<List<FileSystemEntity>> snapshot,
            ) {
              final List<FileSystemEntity>? children = snapshot.data;
              return FileTreeGroup(
                title: path.basename(widget.folderPath),
                trailing: FileTreeExpansionActions(
                  foreground: widget.foreground,
                  onExpandAll: () => _setExpanded(true),
                  onCollapseAll: () => _setExpanded(false),
                ),
                count: children?.length,
                accent: accent,
                foreground: widget.foreground,
                children: <Widget>[
                  if (snapshot.connectionState != ConnectionState.done)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Center(
                        child: SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: widget.foreground.withValues(alpha: .7),
                          ),
                        ),
                      ),
                    )
                  else
                    for (final FileSystemEntity child
                        in children ?? const <FileSystemEntity>[])
                      _TreeEntityNode(
                        expansion: _expansion,
                        entity: child,
                        depth: 1,
                        foreground: widget.foreground,
                        accent: accent,
                      ),
                ],
              );
            },
      ),
    );
  }
}

/// Lists one tree level with directories first.
///
/// Missing or unreadable branches render empty instead of failing the entire
/// details surface.
Future<List<FileSystemEntity>> _listTreeChildren(String folderPath) async {
  try {
    final Directory folder = Directory(folderPath);
    if (!await folder.exists()) return const <FileSystemEntity>[];
    final List<FileSystemEntity> children = await folder
        .list(followLinks: false)
        .toList();
    children.sort((FileSystemEntity a, FileSystemEntity b) {
      final bool aDir = a is Directory;
      final bool bDir = b is Directory;
      if (aDir != bDir) return aDir ? -1 : 1;
      return path
          .basename(a.path)
          .toLowerCase()
          .compareTo(path.basename(b.path).toLowerCase());
    });
    return children;
  } on FileSystemException {
    return const <FileSystemEntity>[];
  }
}

class _TreeEntityNode extends StatefulWidget {
  const _TreeEntityNode({
    required this.entity,
    required this.expansion,
    required this.depth,
    required this.foreground,
    this.accent,
  });

  final ({bool expanded, int revision}) expansion;
  final FileSystemEntity entity;
  final int depth;
  final Color foreground;
  final Color? accent;

  @override
  State<_TreeEntityNode> createState() => _TreeEntityNodeState();
}

class _TreeEntityNodeState extends State<_TreeEntityNode> {
  bool _expanded = false;
  Future<List<FileSystemEntity>>? _children;

  @override
  void initState() {
    super.initState();
    _openDirectoryByDefault();
  }

  @override
  void didUpdateWidget(covariant _TreeEntityNode oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entity.path != widget.entity.path) {
      _openDirectoryByDefault();
    } else if (oldWidget.expansion != widget.expansion) {
      _expanded = widget.entity is Directory && widget.expansion.expanded;
      if (_expanded) _children ??= _listTreeChildren(widget.entity.path);
    }
  }

  void _openDirectoryByDefault() {
    // New branches follow the latest bulk action; individual toggles stay local.
    final bool directory = widget.entity is Directory;
    _expanded = directory && widget.expansion.expanded;
    _children = _expanded ? _listTreeChildren(widget.entity.path) : null;
  }

  void _toggle() {
    if (widget.entity is! Directory) return;
    setState(() {
      _expanded = !_expanded;
      if (_expanded) _children ??= _listTreeChildren(widget.entity.path);
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool directory = widget.entity is Directory;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        FileTreeRow(
          depth: widget.depth,
          icon: directory
              ? (_expanded ? Icons.folder_open_rounded : Icons.folder_rounded)
              : widget.entity is Link
              ? Icons.link_rounded
              : Icons.insert_drive_file_outlined,
          label: path.basename(widget.entity.path),
          foreground: widget.foreground,
          iconColor: widget.accent,
          disclosure: directory
              ? (_expanded
                    ? Icons.expand_more_rounded
                    : Icons.chevron_right_rounded)
              : null,
          onTap: directory ? _toggle : null,
        ),
        if (_expanded)
          FutureBuilder<List<FileSystemEntity>>(
            future: _children,
            builder:
                (
                  BuildContext context,
                  AsyncSnapshot<List<FileSystemEntity>> snapshot,
                ) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return Padding(
                      padding: EdgeInsets.only(
                        left: 18.0 * (widget.depth + 1),
                        bottom: 4,
                      ),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: SizedBox.square(
                          dimension: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: widget.foreground.withValues(alpha: .65),
                          ),
                        ),
                      ),
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      for (final FileSystemEntity child
                          in snapshot.data ?? const <FileSystemEntity>[])
                        _TreeEntityNode(
                          expansion: widget.expansion,
                          entity: child,
                          depth: widget.depth + 1,
                          foreground: widget.foreground,
                          accent: widget.accent,
                        ),
                    ],
                  );
                },
          ),
      ],
    );
  }
}
