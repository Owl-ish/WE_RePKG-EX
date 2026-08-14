import 'package:flutter/material.dart';

import 'theme_extensions.dart';

/// Flutter's default thumb is a third opaque and four pixels wide, which over a
/// grid of pictures is invisible. [ink] is what the theme draws on top of.
ScrollbarThemeData _scrollbars(Color ink) => ScrollbarThemeData(
  thickness: const WidgetStatePropertyAll<double>(10),
  radius: const Radius.circular(5),
  thumbColor: WidgetStateProperty.resolveWith((Set<WidgetState> states) {
    final bool held =
        states.contains(WidgetState.hovered) ||
        states.contains(WidgetState.dragged);
    return ink.withValues(alpha: held ? .55 : .35);
  }),
);

class AppTheme {
  static final ThemeData lightTheme = ThemeData(
    brightness: Brightness.light,
    fontFamily: 'Microsoft YaHei',
    scaffoldBackgroundColor: Colors.white,
    primaryColor: Color.fromARGB(255, 91, 144, 243),
    textTheme: TextTheme(),
    inputDecorationTheme: InputDecorationTheme(
      hintStyle: TextStyle(color: Colors.grey, fontSize: 14),
      fillColor: Color(0xFFF3F3F3),
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      inputDecorationTheme: InputDecorationTheme(fillColor: Colors.white),
    ),
    dividerColor: Color(0xFFE0E0E0),
    scrollbarTheme: _scrollbars(Color(0xFF000000)),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        mouseCursor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return SystemMouseCursors.basic;
          }
          return SystemMouseCursors.click;
        }),
      ),
    ),
    iconTheme: IconThemeData(color: Color(0xFF727272)),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      barrierColor: Colors.white.withValues(alpha: .6),
    ),
    extensions: [
      StatusPalette.light,
      ActionButtonTheme.light,
      SlidingSegmentedTheme(
        backgroundColor: Color(0xFFF3F3F3),
        foregroundColor: Colors.white,
      ),
      MetaTheme.light,
    ],
  );

  static final ThemeData darkTheme = ThemeData(
    brightness: Brightness.dark,
    fontFamily: 'Microsoft YaHei',
    scaffoldBackgroundColor: Color(0xFF222222),
    primaryColor: Color(0xFF4A90E2),
    textTheme: TextTheme(),
    inputDecorationTheme: InputDecorationTheme(
      hintStyle: TextStyle(color: Colors.white60, fontSize: 14),
      fillColor: Color(0xFF333333),
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      inputDecorationTheme: InputDecorationTheme(fillColor: Color(0xFF2D2D2D)),
    ),
    dividerColor: Color(0xFF404040),
    scrollbarTheme: _scrollbars(Color(0xFFFFFFFF)),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        mouseCursor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return SystemMouseCursors.basic;
          }
          return SystemMouseCursors.click;
        }),
      ),
    ),
    iconTheme: IconThemeData(color: Colors.white),
    dialogTheme: DialogThemeData(
      backgroundColor: Color(0xFF252525),
      barrierColor: Colors.black.withValues(alpha: .6),
    ),
    extensions: [
      StatusPalette.dark,
      ActionButtonTheme.dark,
      SlidingSegmentedTheme(
        backgroundColor: Color(0xFF333333),
        foregroundColor: Color(0xFF222222),
      ),
      MetaTheme.dark,
    ],
  );
}
