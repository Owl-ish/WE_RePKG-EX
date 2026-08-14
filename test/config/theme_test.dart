import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:we_repkg/config/theme.dart';
import 'package:we_repkg/config/theme_extensions.dart';

void main() {
  test('semantic status colours remain readable in both themes', () {
    for (final ThemeData theme in <ThemeData>[
      AppTheme.lightTheme,
      AppTheme.darkTheme,
    ]) {
      final StatusPalette status = theme.status;
      for (final Color colour in <Color>[
        status.bad,
        status.hollow,
        status.warn,
        status.note,
        status.muted,
        status.good,
      ]) {
        expect(
          _contrast(colour, theme.scaffoldBackgroundColor),
          greaterThanOrEqualTo(4.5),
        );
      }
    }
  });

  testWidgets('the active theme supplies its own semantic palette', (
    WidgetTester tester,
  ) async {
    Future<Color> shown(ThemeMode mode) async {
      late Color colour;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: mode,
          themeAnimationDuration: Duration.zero,
          home: Builder(
            builder: (BuildContext context) {
              colour = Theme.of(context).status.warn;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      return colour;
    }

    expect(await shown(ThemeMode.light), StatusPalette.light.warn);
    expect(await shown(ThemeMode.dark), StatusPalette.dark.warn);
  });
}

double _contrast(Color foreground, Color background) {
  final double light = foreground.computeLuminance();
  final double dark = background.computeLuminance();
  final double higher = light > dark ? light : dark;
  final double lower = light > dark ? dark : light;
  return (higher + 0.05) / (lower + 0.05);
}
