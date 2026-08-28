import 'dart:io';

import 'package:flutter/material.dart';
import 'package:we_repkg/config/theme_extensions.dart';
import 'package:path/path.dart' as path;

part 'file_tree_browser.dart';
part 'file_tree_row.dart';

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
