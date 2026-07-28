import 'package:flutter/material.dart';
import 'package:we_repkg/constants/nums.dart';
import 'package:we_repkg/views/top/filter_dropdown.dart';
import 'package:we_repkg/views/top/refresh.dart';
import 'package:we_repkg/views/top/search.dart';
import 'package:we_repkg/views/top/sort_dropdown.dart';
import 'package:we_repkg/views/top/sort_toggle.dart';
import 'package:we_repkg/views/top/title.dart';

class TopView extends StatelessWidget {
  const TopView({super.key});

  /// Capped rather than flexible, so the search field stays the row's only
  /// flexible child and the view controls stay flush right.
  static const double _titleMaxWidth = 260;

  /// Wider than this and the search field reads as a text editor.
  static const double _searchMaxWidth = 640;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: EdgeInsets.symmetric(horizontal: LayoutNums.edgeInset),
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
          // Expanded absorbs the slack so the row cannot overflow, and Center
          // keeps the search off the filter button.
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: _searchMaxWidth),
                child: Search(),
              ),
            ),
          ),
          // Wider gap here than between the controls, so they read as a group.
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
