part of 'file_tree_panel.dart';

/// One concrete file that can participate in an explicit tree comparison.
class FileTreeCompareCandidate {
  const FileTreeCompareCandidate({
    required this.id,
    required this.path,
    required this.label,
  });

  final String id;
  final String path;
  final String label;
}

/// Shared two-file selection state for file-tree comparison surfaces.
///
/// Callers supply the visible candidate ordering so plain/Ctrl/Shift behavior
/// stays aligned with the project's shared selection semantics. The selection
/// is presentation-only and carries no filesystem relationship meaning.
class FileTreeCompareSelection {
  final FileTreeSelectionAdapter<String> _selection =
      FileTreeSelectionAdapter<String>();

  Set<String> selected = <String>{};
  String? anchor;

  void click(
    List<FileTreeCompareCandidate> visible,
    FileTreeCompareCandidate candidate, {
    required bool control,
    required bool shift,
  }) {
    final FileTreeSelectionState<String> next = _selection.click(
      visible: visible.map((FileTreeCompareCandidate item) => item.id).toList(),
      current: selected,
      target: candidate.id,
      control: control,
      shift: shift,
      anchor: anchor,
    );
    selected = next.selected;
    anchor = next.anchor;
  }

  void clear() {
    selected = <String>{};
    anchor = null;
  }
}

typedef FileTreeCompareActionBuilder =
    Widget Function(
      Key key,
      FileTreeCompareCandidate first,
      FileTreeCompareCandidate second,
    );

/// Shared comparison toolbar for file-tree surfaces.
///
/// The tree owns selection visibility; the caller injects the actual comparison
/// action so the generic tree never learns Backup, package, or file-type rules.
class FileTreeCompareBar extends StatelessWidget {
  const FileTreeCompareBar({
    super.key,
    required this.keyBase,
    required this.candidates,
    required this.selection,
    required this.foreground,
    required this.label,
    required this.actionBuilder,
    required this.clearTooltip,
    required this.onClear,
  });

  final String keyBase;
  final List<FileTreeCompareCandidate> candidates;
  final FileTreeCompareSelection selection;
  final Color foreground;
  final String label;
  final FileTreeCompareActionBuilder actionBuilder;
  final String clearTooltip;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final List<FileTreeCompareCandidate> selected = candidates
        .where(
          (FileTreeCompareCandidate item) =>
              selection.selected.contains(item.id),
        )
        .toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 2, 8, 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            Icons.compare_arrows_rounded,
            size: 16,
            color: foreground.withValues(alpha: .76),
          ),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: foreground, fontSize: 12)),
          const SizedBox(width: 7),
          Text(
            '${selected.length} / 2',
            key: ValueKey<String>('$keyBase-count'),
            style: TextStyle(
              color: foreground.withValues(alpha: .65),
              fontSize: 11,
            ),
          ),
          if (selected.isNotEmpty) ...<Widget>[
            const SizedBox(width: 4),
            Tooltip(
              message: clearTooltip,
              child: IconButton(
                key: ValueKey<String>('$keyBase-clear'),
                onPressed: onClear,
                icon: Icon(
                  Icons.clear_all_rounded,
                  size: 16,
                  color: foreground.withValues(alpha: .65),
                ),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 28,
                  height: 28,
                ),
              ),
            ),
          ],
          const SizedBox(width: 4),
          if (selected.length == 2)
            actionBuilder(
              ValueKey<String>('$keyBase-action'),
              selected[0],
              selected[1],
            )
          else
            Icon(
              Icons.compare_rounded,
              key: ValueKey<String>('$keyBase-disabled'),
              size: 17,
              color: foreground.withValues(alpha: .24),
            ),
        ],
      ),
    );
  }
}
