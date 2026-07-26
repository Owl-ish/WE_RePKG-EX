/// Sizing shared across the top nav bar, so the refresh, filter and sort
/// buttons stay the same size as each other rather than drifting apart as one
/// of them gets tweaked.
class TopBarNums {
  static const double buttonSize = 40;
  static const double iconSize = 24;
}

/// Spacing between the app's content and the edges of the window.
class LayoutNums {
  /// Left and right inset shared by the top bar, the wallpaper grid and the
  /// bottom bar, so the three line up down each side instead of each carrying
  /// its own copy of the number and drifting apart.
  static const double edgeInset = 24;

  /// Gap between the grid and the bars above and below it. The grid used to
  /// sit 2px off both, which read as the thumbnails touching the toolbars.
  static const double contentGap = 14;

  /// Corner radius on the wallpaper tiles in the grid.
  static const double tileRadius = 8;
}
