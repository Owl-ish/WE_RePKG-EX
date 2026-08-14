import 'package:flutter/material.dart';

class StatusPalette extends ThemeExtension<StatusPalette> {
  const StatusPalette({
    required this.bad,
    required this.hollow,
    required this.warn,
    required this.note,
    required this.muted,
    required this.good,
  });

  final Color bad;
  final Color hollow;
  final Color warn;
  final Color note;
  final Color muted;
  final Color good;

  static const StatusPalette light = StatusPalette(
    bad: Color(0xFFC62828),
    hollow: Color(0xFFAD1457),
    warn: Color(0xFFC24E00),
    note: Color(0xFF1565C0),
    muted: Color(0xFF546E7A),
    good: Color(0xFF2E7D32),
  );

  static const StatusPalette dark = StatusPalette(
    bad: Color(0xFFE57373),
    hollow: Color(0xFFF06292),
    warn: Color(0xFFFFB74D),
    note: Color(0xFF64B5F6),
    muted: Color(0xFF90A4AE),
    good: Color(0xFF81C784),
  );

  @override
  StatusPalette copyWith({
    Color? bad,
    Color? hollow,
    Color? warn,
    Color? note,
    Color? muted,
    Color? good,
  }) => StatusPalette(
    bad: bad ?? this.bad,
    hollow: hollow ?? this.hollow,
    warn: warn ?? this.warn,
    note: note ?? this.note,
    muted: muted ?? this.muted,
    good: good ?? this.good,
  );

  @override
  StatusPalette lerp(covariant StatusPalette? other, double t) {
    if (other == null) return this;
    return StatusPalette(
      bad: Color.lerp(bad, other.bad, t)!,
      hollow: Color.lerp(hollow, other.hollow, t)!,
      warn: Color.lerp(warn, other.warn, t)!,
      note: Color.lerp(note, other.note, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      good: Color.lerp(good, other.good, t)!,
    );
  }
}

extension StatusThemeData on ThemeData {
  StatusPalette get status =>
      extension<StatusPalette>() ??
      (brightness == Brightness.dark
          ? StatusPalette.dark
          : StatusPalette.light);
}

class ActionButtonTheme extends ThemeExtension<ActionButtonTheme> {
  const ActionButtonTheme({
    required this.primaryBackground,
    required this.primaryForeground,
    required this.primaryBorder,
    required this.destructiveBackground,
    required this.destructiveForeground,
    required this.destructiveBorder,
  });

  final Color primaryBackground;
  final Color primaryForeground;
  final Color primaryBorder;
  final Color destructiveBackground;
  final Color destructiveForeground;
  final Color destructiveBorder;

  static const ActionButtonTheme light = ActionButtonTheme(
    primaryBackground: Color(0xFFDCE5F0),
    primaryForeground: Color(0xFF315478),
    primaryBorder: Color(0xFFB9C9D9),
    destructiveBackground: Color(0xFFF1DEDE),
    destructiveForeground: Color(0xFF8B3A3A),
    destructiveBorder: Color(0xFFD8BABA),
  );

  static const ActionButtonTheme dark = ActionButtonTheme(
    primaryBackground: Color(0xFF344353),
    primaryForeground: Color(0xFFD5E4F2),
    primaryBorder: Color(0xFF4B6074),
    destructiveBackground: Color(0xFF503A3D),
    destructiveForeground: Color(0xFFF4D8DA),
    destructiveBorder: Color(0xFF704B50),
  );

  @override
  ActionButtonTheme copyWith({
    Color? primaryBackground,
    Color? primaryForeground,
    Color? primaryBorder,
    Color? destructiveBackground,
    Color? destructiveForeground,
    Color? destructiveBorder,
  }) {
    return ActionButtonTheme(
      primaryBackground: primaryBackground ?? this.primaryBackground,
      primaryForeground: primaryForeground ?? this.primaryForeground,
      primaryBorder: primaryBorder ?? this.primaryBorder,
      destructiveBackground:
          destructiveBackground ?? this.destructiveBackground,
      destructiveForeground:
          destructiveForeground ?? this.destructiveForeground,
      destructiveBorder: destructiveBorder ?? this.destructiveBorder,
    );
  }

  @override
  ActionButtonTheme lerp(
    covariant ThemeExtension<ActionButtonTheme>? other,
    double t,
  ) {
    if (other is! ActionButtonTheme) return this;
    return ActionButtonTheme(
      primaryBackground: Color.lerp(
        primaryBackground,
        other.primaryBackground,
        t,
      )!,
      primaryForeground: Color.lerp(
        primaryForeground,
        other.primaryForeground,
        t,
      )!,
      primaryBorder: Color.lerp(primaryBorder, other.primaryBorder, t)!,
      destructiveBackground: Color.lerp(
        destructiveBackground,
        other.destructiveBackground,
        t,
      )!,
      destructiveForeground: Color.lerp(
        destructiveForeground,
        other.destructiveForeground,
        t,
      )!,
      destructiveBorder: Color.lerp(
        destructiveBorder,
        other.destructiveBorder,
        t,
      )!,
    );
  }
}

extension ActionButtonThemeData on ThemeData {
  ActionButtonTheme get actionButtons =>
      extension<ActionButtonTheme>() ??
      (brightness == Brightness.dark
          ? ActionButtonTheme.dark
          : ActionButtonTheme.light);
}

class SlidingSegmentedTheme extends ThemeExtension<SlidingSegmentedTheme> {
  final Color backgroundColor;
  final Color foregroundColor;

  const SlidingSegmentedTheme({
    required this.backgroundColor,
    required this.foregroundColor,
  });

  @override
  ThemeExtension<SlidingSegmentedTheme> copyWith({
    Color? backgroundColor,
    Color? foregroundColor,
  }) {
    return SlidingSegmentedTheme(
      backgroundColor: backgroundColor ?? this.backgroundColor,
      foregroundColor: foregroundColor ?? this.foregroundColor,
    );
  }

  @override
  ThemeExtension<SlidingSegmentedTheme> lerp(
    covariant ThemeExtension<SlidingSegmentedTheme>? other,
    double t,
  ) {
    if (other is! SlidingSegmentedTheme) {
      return this;
    }
    return SlidingSegmentedTheme(
      backgroundColor: Color.lerp(backgroundColor, other.backgroundColor, t)!,
      foregroundColor: Color.lerp(foregroundColor, other.foregroundColor, t)!,
    );
  }
}

class MetaTheme extends ThemeExtension<MetaTheme> {
  final TextStyle largeStyle;
  final TextStyle mediumStyle;

  /// Group headings and the explanatory line under a setting.
  final TextStyle captionStyle;

  const MetaTheme({
    required this.largeStyle,
    required this.mediumStyle,
    required this.captionStyle,
  });

  /// Grey enough to sit behind what it explains, dark enough to read: plain
  /// `Colors.grey` on white is too faint for a paragraph.
  static const TextStyle _lightCaption = TextStyle(
    color: Color(0xFF5F6368),
    fontSize: 13,
  );
  static const TextStyle _darkCaption = TextStyle(
    color: Color(0xFFAFAFAF),
    fontSize: 13,
  );

  static const MetaTheme light = MetaTheme(
    largeStyle: TextStyle(
      color: Color(0xFF666666),
      fontSize: 16,
      fontFamily: 'Microsoft YaHei',
    ),
    mediumStyle: TextStyle(
      color: Color(0xFF666666),
      fontSize: 14,
      fontFamily: 'Microsoft YaHei',
    ),
    captionStyle: _lightCaption,
  );

  static const MetaTheme dark = MetaTheme(
    largeStyle: TextStyle(
      color: Color(0xFFDDDDDD),
      fontSize: 16,
      fontFamily: 'Microsoft YaHei',
    ),
    mediumStyle: TextStyle(
      color: Color(0xFFDDDDDD),
      fontSize: 14,
      fontFamily: 'Microsoft YaHei',
    ),
    captionStyle: _darkCaption,
  );

  @override
  ThemeExtension<MetaTheme> copyWith({
    TextStyle? largeStyle,
    TextStyle? mediumStyle,
    TextStyle? captionStyle,
  }) {
    return MetaTheme(
      largeStyle: largeStyle ?? this.largeStyle,
      mediumStyle: mediumStyle ?? this.mediumStyle,
      captionStyle: captionStyle ?? this.captionStyle,
    );
  }

  @override
  ThemeExtension<MetaTheme> lerp(
    covariant ThemeExtension<MetaTheme>? other,
    double t,
  ) {
    if (other is! MetaTheme) {
      return this;
    }
    return MetaTheme(
      largeStyle: TextStyle.lerp(largeStyle, other.largeStyle, t)!,
      mediumStyle: TextStyle.lerp(mediumStyle, other.mediumStyle, t)!,
      captionStyle: TextStyle.lerp(captionStyle, other.captionStyle, t)!,
    );
  }
}

extension MetaThemeData on ThemeData {
  MetaTheme get meta =>
      extension<MetaTheme>() ??
      (brightness == Brightness.dark ? MetaTheme.dark : MetaTheme.light);
}
