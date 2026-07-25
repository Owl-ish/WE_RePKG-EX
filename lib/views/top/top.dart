import 'package:flutter/material.dart';
import 'package:we_repkg/views/top/filter_dropdown.dart';
import 'package:we_repkg/views/top/refresh.dart';
import 'package:we_repkg/views/top/search.dart';
import 'package:we_repkg/views/top/sort_dropdown.dart';
import 'package:we_repkg/views/top/sort_toggle.dart';
import 'package:we_repkg/views/top/title.dart';

class TopView extends StatelessWidget {
  const TopView({super.key});

  /// Widest the wallpaper count gets before it ellipsizes. Capping it rather
  /// than making it flexible keeps the search field the row's only flexible
  /// child, so the view controls stay flush against the right edge.
  static const double _titleMaxWidth = 260;

  /// The search field grows into the empty middle of the bar, but a field
  /// wider than this reads as a text editor rather than a search box.
  static const double _searchMaxWidth = 640;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: _titleMaxWidth),
            child: TopTitle(),
          ),
          SizedBox(width: 4),
          Refresh(),
          SizedBox(width: 16),
          // Expanded absorbs every spare pixel, so the row can never overflow
          // however narrow the window gets.
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: _searchMaxWidth),
                child: Search(),
              ),
            ),
          ),
          // Wider gap after the search than between the view controls, so the
          // filter and the two sort controls read as one group.
          SizedBox(width: 16),
          FilterDropdown(),
          SizedBox(width: 8),
          SortToggle(),
          SizedBox(width: 8),
          SortDropdown(),
        ],
      ),
    );
  }
}
