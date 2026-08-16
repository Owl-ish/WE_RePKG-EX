import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;

/// Reusable read-only folder tree for details surfaces.
///
/// Directories start expanded. Loading stays asynchronous so opening a details
/// surface does not block on a large folder. The tree never mutates disk.
class FileTreePanel extends StatefulWidget {
  const FileTreePanel({
    super.key,
    required this.folderPath,
    required this.foreground,
    this.maxHeight,
  });

  final String folderPath;
  final Color foreground;

  /// Optional cap for callers that place the tree in an unbounded column.
  /// Leave null when the parent already gives the tree a bounded height.
  final double? maxHeight;

  @override
  State<FileTreePanel> createState() => _FileTreePanelState();
}

class _FileTreePanelState extends State<FileTreePanel> {
  late Future<List<FileSystemEntity>> _children;
  final ScrollController _verticalController = ScrollController();
  final ScrollController _horizontalController = ScrollController();

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
      if (_verticalController.hasClients) _verticalController.jumpTo(0);
      if (_horizontalController.hasClients) _horizontalController.jumpTo(0);
    }
  }

  @override
  void dispose() {
    _verticalController.dispose();
    _horizontalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget tree = Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        border: Border.all(color: widget.foreground.withValues(alpha: .22)),
        borderRadius: BorderRadius.circular(8),
        color: widget.foreground.withValues(alpha: .05),
      ),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          return Scrollbar(
            controller: _verticalController,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: _verticalController,
              scrollDirection: Axis.vertical,
              child: Scrollbar(
                controller: _horizontalController,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: _horizontalController,
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: constraints.maxWidth),
                    child: Padding(
                      // Dedicated gutters keep both scrollbar tracks clear of
                      // the filename text even when both axes are scrollable.
                      padding: const EdgeInsets.fromLTRB(0, 6, 16, 18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          _TreeRow(
                            depth: 0,
                            icon: Icons.folder_open_rounded,
                            label: path.basename(widget.folderPath),
                            foreground: widget.foreground,
                          ),
                          FutureBuilder<List<FileSystemEntity>>(
                            future: _children,
                            builder:
                                (
                                  BuildContext context,
                                  AsyncSnapshot<List<FileSystemEntity>>
                                  snapshot,
                                ) {
                                  if (snapshot.connectionState !=
                                      ConnectionState.done) {
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 8,
                                      ),
                                      child: Center(
                                        child: SizedBox.square(
                                          dimension: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: widget.foreground.withValues(
                                              alpha: .7,
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  }
                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: <Widget>[
                                      for (final FileSystemEntity child
                                          in snapshot.data ??
                                              const <FileSystemEntity>[])
                                        _TreeEntityNode(
                                          entity: child,
                                          depth: 1,
                                          foreground: widget.foreground,
                                        ),
                                    ],
                                  );
                                },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );

    if (widget.maxHeight case final double maxHeight) {
      tree = ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: tree,
      );
    }
    return tree;
  }
}

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
    required this.depth,
    required this.foreground,
  });

  final FileSystemEntity entity;
  final int depth;
  final Color foreground;

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
    }
  }

  void _openDirectoryByDefault() {
    final bool directory = widget.entity is Directory;
    _expanded = directory;
    _children = directory ? _listTreeChildren(widget.entity.path) : null;
  }

  void _toggle() {
    if (widget.entity is! Directory) return;
    setState(() {
      _expanded = !_expanded;
      if (_expanded) {
        _children ??= _listTreeChildren(widget.entity.path);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool directory = widget.entity is Directory;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        InkWell(
          onTap: directory ? _toggle : null,
          child: _TreeRow(
            depth: widget.depth,
            icon: directory
                ? (_expanded ? Icons.folder_open_rounded : Icons.folder_rounded)
                : widget.entity is Link
                ? Icons.link_rounded
                : Icons.insert_drive_file_outlined,
            label: path.basename(widget.entity.path),
            foreground: widget.foreground,
            disclosure: directory
                ? (_expanded
                      ? Icons.expand_more_rounded
                      : Icons.chevron_right_rounded)
                : null,
          ),
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
                          entity: child,
                          depth: widget.depth + 1,
                          foreground: widget.foreground,
                        ),
                    ],
                  );
                },
          ),
      ],
    );
  }
}

class _TreeRow extends StatelessWidget {
  const _TreeRow({
    required this.depth,
    required this.icon,
    required this.label,
    required this.foreground,
    this.disclosure,
  });

  final int depth;
  final IconData icon;
  final IconData? disclosure;
  final String label;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(8 + depth * 16.0, 3, 8, 3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox(
            width: 18,
            child: disclosure == null
                ? null
                : Icon(
                    disclosure,
                    size: 16,
                    color: foreground.withValues(alpha: .75),
                  ),
          ),
          Icon(icon, size: 16, color: foreground.withValues(alpha: .82)),
          const SizedBox(width: 6),
          Text(
            label,
            maxLines: 1,
            style: TextStyle(color: foreground, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
