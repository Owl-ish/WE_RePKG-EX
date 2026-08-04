import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:we_repkg/constants/i10n.dart';
import 'package:we_repkg/provider/system.dart';
import 'package:we_repkg/widgets/custom_input.dart';

class Search extends ConsumerStatefulWidget {
  const Search({super.key});

  @override
  ConsumerState<Search> createState() => _SearchState();
}

class _SearchState extends ConsumerState<Search> {
  late TextEditingController controller;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    controller = TextEditingController()
      ..addListener(() {
        setState(() {}); // update the clear button / text display immediately
        // Debounce: only trigger filtering 250ms after typing stops, so each
        // keystroke doesn't re-filter the whole list.
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 250), () {
          ref.read(searchContentProvider.notifier).update(controller.text);
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
    // No width of its own: TopView stretches the field into the gap between the
    // wallpaper count and the view controls, up to a cap.
    return CustomInput(
      controller: controller,
      hintText: tr(AppI10n.homeSearchTip),
      padding: EdgeInsets.only(left: 8, right: 8),
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
