import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:we_repkg/constants/i10n.dart';
import 'package:we_repkg/widgets/custom_input.dart';

/// The search box both grids use. Where the text goes is the caller's business.
class SearchField extends StatefulWidget {
  const SearchField({
    super.key,
    required this.onChanged,
    this.initialText = '',
  });

  final void Function(String) onChanged;

  /// The term already narrowing the grid. The field lives with the widget while
  /// the term lives in a provider, so anything that takes the row away, a
  /// rescan or a trip to the other tab, would otherwise leave a narrowed grid
  /// above an empty box.
  final String initialText;

  @override
  State<SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<SearchField> {
  late TextEditingController controller;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    controller = TextEditingController(text: widget.initialText)
      ..addListener(() {
        setState(() {}); // update the clear button / text display immediately
        // Debounce: only trigger filtering 250ms after typing stops, so each
        // keystroke doesn't re-filter the whole list.
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 250), () {
          widget.onChanged(controller.text);
        });
      });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // No width of its own: the row it sits in decides.
    return CustomInput(
      controller: controller,
      hintText: tr(AppI10n.homeSearchTip),
      padding: EdgeInsets.only(left: 12, right: 8),
      leading: Icon(Icons.search_rounded, size: 20, color: Colors.grey),
      extraIcon: controller.text.isEmpty
          ? null
          : IconButton(
              onPressed: () => setState(() => controller.clear()),
              icon: Icon(Icons.close_rounded),
              iconSize: 16,
              color: Colors.grey,
              padding: EdgeInsets.all(4),
              constraints: BoxConstraints(maxWidth: 36, maxHeight: 36),
            ),
    );
  }
}
