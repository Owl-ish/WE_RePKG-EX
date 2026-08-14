import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:we_repkg/provider/setting.dart';
import 'package:we_repkg/provider/system.dart';
import 'package:we_repkg/views/top/filter_dropdown.dart';
import 'package:we_repkg/views/top/library_dropdown.dart';
import 'package:we_repkg/views/top/refresh.dart';
import 'package:we_repkg/widgets/search_field.dart';
import 'package:we_repkg/widgets/top_bar.dart';
import 'package:we_repkg/views/top/sort_dropdown.dart';
import 'package:we_repkg/views/top/sort_toggle.dart';
import 'package:we_repkg/views/top/title.dart';

class TopView extends StatelessWidget {
  const TopView({super.key});

  /// Capped rather than flexible, so the search field stays the row's only
  /// flexible child and the view controls stay flush right.
  static const double _titleMaxWidth = 260;

  @override
  Widget build(BuildContext context) {
    return TopBar(
      leading: [
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: _titleMaxWidth),
          child: TopTitle(),
        ),
        SizedBox(width: 4),
        Refresh(),
        // Wider than the gap it had, to sit off the refresh button rather
        // than beside it. Not true centring between refresh and the search
        // field: that field is centred in the window, so the space to its
        // left changes with every resize.
        SizedBox(width: 32),
        LibraryDropdown(),
        SizedBox(width: 24),
      ],
      centre: Consumer(
        builder: (context, ref, _) => SearchField(
          initialText: ref.read(searchContentProvider),
          onChanged: (String text) =>
              ref.read(searchContentProvider.notifier).update(text),
        ),
      ),
      trailing: [
        // Wider gap here than between the controls, so they read as a group.
        SizedBox(width: 16),
        FilterDropdown(),
        SizedBox(width: 8),
        Consumer(
          builder: (context, ref, _) => SortToggle(
            ascending: ref.watch(sortAscendingProvider),
            onPressed: ref.read(sortAscendingProvider.notifier).update,
          ),
        ),
        SizedBox(width: 8),
        SortDropdown(),
      ],
    );
  }
}
