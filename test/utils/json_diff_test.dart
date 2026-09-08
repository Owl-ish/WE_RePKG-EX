import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:we_repkg/utils/json_diff.dart';

void main() {
  test('literal dotted and indexed keys cannot collide with nested paths', () {
    final changes = compareJsonValues(
      jsonDecode('{"a.b":1,"a":{"b":2},"items[0]":3,"items":[4]}'),
      jsonDecode('{"a.b":9,"a":{"b":8},"items[0]":7,"items":[6]}'),
    );
    final byField = {for (final change in changes) change.field: change};
    expect(
      byField.keys,
      unorderedEquals([r'$["a.b"]', r'$.a.b', r'$["items[0]"]', r'$.items[0]']),
    );
    expect(byField[r'$["a.b"]']!.before, 1);
    expect(byField[r'$["a.b"]']!.after, 9);
    expect(formatJsonFieldPath(r'$["a.b"]'), '["a.b"]');
    expect(formatJsonFieldPath(r'$.a.b'), 'a  ›  b');
  });

  test('missing and null remain distinct in objects and arrays', () {
    final changes = compareJsonValues(
      {'old': null, 'list': []},
      {
        'new': null,
        'list': [null],
      },
    );
    final byField = {for (final change in changes) change.field: change};
    expect(byField[r'$.old']!.beforePresent, isTrue);
    expect(byField[r'$.old']!.afterPresent, isFalse);
    expect(byField[r'$.new']!.beforePresent, isFalse);
    expect(byField[r'$.new']!.afterPresent, isTrue);
    expect(byField[r'$.list[0]']!.beforePresent, isFalse);
    expect(byField[r'$.list[0]']!.afterPresent, isTrue);
  });

  test('container type replacement is one whole-value change', () {
    final changes = compareJsonValues(
      {
        'value': {'child': 1},
      },
      {
        'value': [1],
      },
    );
    expect(changes, hasLength(1));
    expect(changes.single.field, r'$.value');
    expect(changes.single.before, {'child': 1});
    expect(changes.single.after, [1]);
    expect(compareJsonValues({}, []).single.field, r'$');
  });

  test('equivalent numbers and reordered object keys are unchanged', () {
    expect(
      compareJsonValues(
        jsonDecode('{"a":1,"b":[]}'),
        jsonDecode('{"b":[],"a":1.0}'),
      ),
      isEmpty,
    );
    expect(compareJsonValues(null, null), isEmpty);
    expect(compareJsonValues({'a': {}}, {'a': {}}), isEmpty);
  });

  test('empty, quoted, and non-ASCII keys retain unambiguous labels', () {
    for (final key in ['', 'a"b', r'a\b', '雪', r'$', 'a[2].b']) {
      final change = compareJsonValues({key: 1}, {key: 2}).single;
      expect(change.field, '\$[${jsonEncode(key)}]');
      expect(formatJsonFieldPath(change.field), '[${jsonEncode(key)}]');
    }
  });
}
