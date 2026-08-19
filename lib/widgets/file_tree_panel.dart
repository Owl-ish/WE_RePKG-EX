import 'dart:io';

import 'package:flutter/material.dart';
import 'package:we_repkg/config/theme_extensions.dart';
import 'package:path/path.dart' as path;

// Library colours stay the same anywhere a file tree is shown.
enum FileTreeLibrary { workshop, myProjects }

Color fileTreeLibraryColour(BuildContext context, FileTreeLibrary library) {
  final StatusPalette colours = Theme.of(context).status;
  return switch (library) {
    FileTreeLibrary.workshop => colours.note,
    FileTreeLibrary.myProjects => colours.good,
  };
}

/// Shared frame for file and folder trees.
class FileTreeSurface extends StatelessWidget {
  const FileTreeSurface({
    super.key,
    required this.foreground,
    required this.child,
  });

  final Color foreground;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      border: Border.all(color: foreground.withValues(alpha: .22)),
      borderRadius: BorderRadius.circular(8),
      color: foreground.withValues(alpha: .05),
    ),
    child: child,
  );
}

/// Shared two-axis tree viewport.
class FileTreeScrollView extends StatefulWidget {
  const FileTreeScrollView({
    super.key,
    required this.foreground,
    required this.child,
    this.maxHeight,
    this.semanticLabel,
  });

  final Color foreground;
  final Widget child;
  final double? maxHeight;
  final String? semanticLabel;

  @override
  State<FileTreeScrollView> createState() => _FileTreeScrollViewState();
}

class _FileTreeScrollViewState extends State<FileTreeScrollView> {
  final ScrollController _verticalController = ScrollController();
  final ScrollController _horizontalController = ScrollController();

  @override
  void dispose() {
    _verticalController.dispose();
    _horizontalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget tree = FileTreeSurface(
      foreground: widget.foreground,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          Widget scroll = Scrollbar(
            controller: _verticalController,
            thumbVisibility: true,
            interactive: true,
            child: SingleChildScrollView(
              controller: _verticalController,
              scrollDirection: Axis.vertical,
              child: Scrollbar(
                controller: _horizontalController,
                thumbVisibility: true,
                interactive: true,
                notificationPredicate: (ScrollNotification notification) =>
                    notification.metrics.axis == Axis.horizontal,
                child: SingleChildScrollView(
                  controller: _horizontalController,
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: constraints.maxWidth),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(0, 6, 16, 18),
                      child: widget.child,
                    ),
                  ),
                ),
              ),
            ),
          );
          if (widget.semanticLabel case final String label) {
            scroll = Semantics(
              container: true,
              label: label,
              child: ExcludeSemantics(child: scroll),
            );
          }
          return scroll;
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

/// Shared group header used by virtual file trees.
class FileTreeGroupHeader extends StatelessWidget {
  const FileTreeGroupHeader({
    super.key,
    required this.title,
    required this.foreground,
    this.accent,
    this.count,
    this.trailing,
  });

  final String title;
  final Color foreground;
  final Color? accent;
  final int? count;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final Color groupColour = accent ?? foreground;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 5),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 10,
        runSpacing: 4,
        children: <Widget>[
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.folder_open_rounded, size: 17, color: groupColour),
              const SizedBox(width: 7),
              Text(
                count == null ? title : '$title ($count)',
                style: TextStyle(
                  color: foreground,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Header plus rows for one logical group in a file tree.
class FileTreeGroup extends StatelessWidget {
  const FileTreeGroup({
    super.key,
    required this.title,
    required this.foreground,
    required this.children,
    this.accent,
    this.count,
    this.trailing,
  });

  final String title;
  final Color foreground;
  final Color? accent;
  final int? count;
  final Widget? trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        FileTreeGroupHeader(
          title: title,
          foreground: foreground,
          accent: accent,
          count: count,
          trailing: trailing,
        ),
        Divider(
          height: 1,
          thickness: 1,
          color: foreground.withValues(alpha: .12),
        ),
        ...children,
      ],
    ),
  );
}

/// Shared row styling for files and folders.
class FileTreeRow extends StatelessWidget {
  const FileTreeRow({
    super.key,
    required this.depth,
    required this.icon,
    required this.label,
    required this.foreground,
    this.disclosure,
    this.subtitle,
    this.trailing,
    this.iconColor,
  });

  final int depth;
  final IconData icon;
  final IconData? disclosure;
  final String label;
  final String? subtitle;
  final Widget? trailing;
  final Color foreground;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final Color rowIcon = iconColor ?? foreground.withValues(alpha: .82);
    final Widget labelWidget = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          maxLines: 1,
          style: TextStyle(color: foreground, fontSize: 12),
        ),
        if (subtitle case final String text)
          Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: foreground.withValues(alpha: .65),
              fontSize: 11,
            ),
          ),
      ],
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(8 + depth * 16.0, 3, 8, 3),
      child: Row(
        mainAxisSize: trailing == null ? MainAxisSize.min : MainAxisSize.max,
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
          Icon(icon, size: 16, color: rowIcon),
          const SizedBox(width: 6),
          if (trailing == null) labelWidget else Expanded(child: labelWidget),
          if (trailing != null) ...<Widget>[
            const SizedBox(width: 10),
            trailing!,
          ],
        ],
      ),
    );
  }
}

/// Reusable read-only folder tree for details surfaces.
class FileTreePanel extends StatefulWidget {
  const FileTreePanel({
    super.key,
    required this.folderPath,
    required this.foreground,
    this.library,
    this.accent,
    this.maxHeight,
  });

  final String folderPath;
  final Color foreground;
  final FileTreeLibrary? library;
  final Color? accent;
  final double? maxHeight;

  @override
  State<FileTreePanel> createState() => _FileTreePanelState();
}

class _FileTreePanelState extends State<FileTreePanel> {
  late Future<List<FileSystemEntity>> _children;

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
    required this.depth,
    required this.foreground,
    this.accent,
  });

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
    }
  }

  void _openDirectoryByDefault() {
    // Detail trees start expanded so the first view exposes useful contents.
    final bool directory = widget.entity is Directory;
    _expanded = directory;
    _children = directory ? _listTreeChildren(widget.entity.path) : null;
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
        InkWell(
          onTap: directory ? _toggle : null,
          child: FileTreeRow(
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
