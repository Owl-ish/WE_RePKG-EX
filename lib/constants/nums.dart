import 'dart:ui';

/// Shared so the refresh, filter and sort buttons stay the same size as each
/// other.
class TopBarNums {
  static const double buttonSize = 40;
  static const double iconSize = 24;
}

class LayoutNums {
  /// Left and right inset shared by the top bar, the grid and the bottom bar,
  /// so the three line up down each side.
  static const double edgeInset = 24;

  /// Gap between the grid and the bars above and below it.
  static const double contentGap = 14;

  /// Corners of anything that reads as a surface of its own.
  static const double surfaceRadius = 8;

  /// Corners of the smaller controls sitting on those surfaces.
  static const double controlRadius = 4;
}

class WindowNums {
  /// 16:9, used on first launch before a size has been saved.
  static const Size defaultSize = Size(1380, 800);

  /// The settings form's two columns stop fitting below this width.
  static const Size minimumSize = Size(1060, 720);
}
