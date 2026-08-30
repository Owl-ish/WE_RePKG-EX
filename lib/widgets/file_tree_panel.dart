// Public library for the shared file-tree widget system. Private part files
// separate comparison controls, AX-sensitive row interaction, and filesystem
// browsing without widening the API between these tightly coupled pieces.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:we_repkg/config/theme_extensions.dart';
import 'package:we_repkg/cores/context_menu.dart';
import 'package:we_repkg/utils/grid_selection.dart';
import 'package:we_repkg/utils/modifier_keys.dart';
import 'package:we_repkg/widgets/right_menu_item.dart';

part 'file_tree_compare_controls.dart';
part 'file_tree_browser.dart';
part 'file_tree_row.dart';

// Library colours stay the same anywhere a file tree is shown.
enum FileTreeLibrary { workshop, myProjects }

// Keep hover/selection treatment consistent across every shared file-tree row.
// These values stay local to the file-tree system until another UI surface
// proves it needs the exact same interaction language.
const double _fileTreeRowInteractiveRadius = 7;
const double _fileTreeRowHoverAlpha = .065;
const double _fileTreeRowSelectedAlpha = .12;

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
            // Do not put a custom Semantics node above a dynamic two-axis tree.
            // Windows can reject the rapid reparenting when a large difference
            // tree appears. The native scrollables and interactive rows already
            // contribute their own semantics; this keyed subtree keeps stable
            // widget identity without creating another AX parent.
            scroll = KeyedSubtree(
              key: ValueKey<String>('file-tree-semantics-$label'),
              child: scroll,
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
    // Flutter #182444 can serialize orphaned Tooltip OverlayPortal nodes in
    // Windows scrollable semantics. Preserve tooltip descriptions for
    // accessibility, but suppress their visual overlays until the framework
    // fix is available in the project's minimum Flutter version.
    return TooltipVisibility(visible: !Platform.isWindows, child: tree);
  }
}

/// Tooltip contract for controls rendered inside [FileTreeScrollView].
///
/// Windows uses stable inline semantics without constructing the framework's
/// tooltip overlay. Other platforms retain the normal visual tooltip.
class FileTreeTooltip extends StatelessWidget {
  const FileTreeTooltip({
    super.key,
    required this.message,
    required this.child,
  });

  final String message;
  final Widget child;

  @override
  Widget build(BuildContext context) => TooltipVisibility.of(context)
      ? Tooltip(message: message, child: child)
      : Semantics(tooltip: message, child: child);
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

/// Two-way choice shown at the far right of a file row or group.
///
/// The tree owns presentation only. Callers define what reject and accept mean
/// and provide their accessible descriptions.
class FileTreeRowChoice extends StatelessWidget {
  const FileTreeRowChoice({
    super.key,
    required this.selected,
    required this.onChanged,
    required this.rejectTooltip,
    required this.acceptTooltip,
    required this.foreground,
    this.rejectKey,
    this.acceptKey,
  });

  final bool? selected;
  final ValueChanged<bool> onChanged;
  final String rejectTooltip;
  final String acceptTooltip;
  final Color foreground;
  final Key? rejectKey;
  final Key? acceptKey;

  Widget _button({
    required bool value,
    required IconData icon,
    required String tooltip,
    required Key? key,
  }) => SizedBox.square(
    dimension: 28,
    child: FileTreeTooltip(
      message: tooltip,
      child: IconButton(
        key: key,
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        onPressed: () => onChanged(value),
        color: selected == value
            ? foreground
            : foreground.withValues(alpha: .35),
        icon: Icon(icon, size: 17),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      _button(
        value: false,
        icon: Icons.close_rounded,
        tooltip: rejectTooltip,
        key: rejectKey,
      ),
      _button(
        value: true,
        icon: Icons.check_rounded,
        tooltip: acceptTooltip,
        key: acceptKey,
      ),
    ],
  );
}
