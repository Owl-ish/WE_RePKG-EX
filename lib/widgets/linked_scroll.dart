import 'package:flutter/material.dart';

/// Links two vertical viewports by absolute offset.
/// A shorter target clamps without changing the source's position.
class LinkedVerticalScroll extends ChangeNotifier {
  LinkedVerticalScroll() {
    first.addListener(_firstScrolled);
    second.addListener(_secondScrolled);
  }

  late final ScrollController first = ScrollController(onAttach: _onAttach);
  late final ScrollController second = ScrollController(onAttach: _onAttach);
  bool _linked = true;
  bool get linked => _linked;
  bool _syncing = false;
  bool _disposed = false;

  void _onAttach(ScrollPosition position) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_disposed && _linked) syncFromFirst();
    });
  }

  void _firstScrolled() {
    if (_linked) _copy(first, second);
  }

  void _secondScrolled() {
    if (_linked) _copy(second, first);
  }

  void _copy(ScrollController source, ScrollController target) {
    if (_syncing || !source.hasClients || !target.hasClients) return;
    if (!source.position.hasContentDimensions ||
        !target.position.hasContentDimensions) {
      return;
    }
    final double offset = source.offset.clamp(
      0.0,
      target.position.maxScrollExtent,
    );
    if ((target.offset - offset).abs() <= .1) return;
    _syncing = true;
    try {
      target.jumpTo(offset);
    } finally {
      _syncing = false;
    }
  }

  void syncFromFirst() => _copy(first, second);

  void toggle() {
    _linked = !_linked;
    notifyListeners();
    if (_linked) syncFromFirst();
  }

  @override
  void dispose() {
    _disposed = true;
    first.dispose();
    second.dispose();
    super.dispose();
  }
}

/// A compact link control with one accessible action and no visual tooltip.
class LinkedScrollToggle extends StatelessWidget {
  const LinkedScrollToggle({
    super.key,
    required this.linked,
    required this.onPressed,
    required this.linkLabel,
    required this.unlinkLabel,
  });

  final bool linked;
  final VoidCallback onPressed;
  final String linkLabel;
  final String unlinkLabel;

  @override
  Widget build(BuildContext context) => Semantics(
    label: linked ? unlinkLabel : linkLabel,
    button: true,
    toggled: linked,
    onTap: onPressed,
    child: ExcludeSemantics(
      child: IconButton(
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints.tightFor(width: 30, height: 30),
        icon: Icon(
          linked ? Icons.link_rounded : Icons.link_off_rounded,
          size: 18,
        ),
      ),
    ),
  );
}
