import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the invariant that Pass 2 established.
///
/// Everything in lib/cores/ is a plain function taking a WidgetRef from an event
/// handler, never a widget build method. `WidgetRef.watch` there subscribes the
/// calling widget to a provider from inside a callback, which rebuilds it on
/// unrelated changes. `read` returns the identical value without subscribing.
///
/// The compiler cannot tell the two apart, both type-check and both return the
/// same thing, so nothing else in the suite would catch a reintroduced `watch`.
/// This reads the source instead.
void main() {
  test('lib/cores contains no ref.watch', () {
    final dir = Directory('lib/cores');
    expect(
      dir.existsSync(),
      isTrue,
      reason: 'run from the package root so the relative path resolves',
    );

    final offenders = <String>[];
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final lines = entity.readAsLinesSync();
      for (int i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.trimLeft().startsWith('//')) continue; // commented-out code
        if (line.contains('ref.watch(')) {
          offenders.add('${entity.path}:${i + 1}: ${line.trim()}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Use ref.read in lib/cores. These are event-handler functions, not '
          'build methods, so watch adds a subscription that rebuilds the '
          'calling widget for nothing:\n${offenders.join('\n')}',
    );
  });
}
