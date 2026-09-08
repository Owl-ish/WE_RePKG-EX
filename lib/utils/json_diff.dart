import 'dart:convert';
import 'dart:math';

typedef JsonFieldChange = ({
  String field,
  Object? before,
  Object? after,
  bool beforePresent,
  bool afterPresent,
});

/// Compares decoded JSON values. Missing entries differ from explicit null;
/// object/array replacements are one change rather than unrelated leaf changes.
/// Paths quote literal keys when dot notation would be ambiguous.
List<JsonFieldChange> compareJsonValues(Object? before, Object? after) {
  final changes = <JsonFieldChange>[];
  _collectJsonChanges(
    before,
    after,
    field: r'$',
    beforePresent: true,
    afterPresent: true,
    changes: changes,
  );
  changes.sort((a, b) => _compareFields(a.field, b.field));
  return changes;
}

final _identifier = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

int _compareFields(String a, String b) {
  final order = a.toLowerCase().compareTo(b.toLowerCase());
  return order == 0 ? a.compareTo(b) : order;
}

void _collectJsonChanges(
  Object? before,
  Object? after, {
  required String field,
  required bool beforePresent,
  required bool afterPresent,
  required List<JsonFieldChange> changes,
}) {
  if (beforePresent && afterPresent && before is Map && after is Map) {
    final Set<String> keys = <String>{
      ...before.keys.map((Object? key) => '$key'),
      ...after.keys.map((Object? key) => '$key'),
    };
    final List<String> ordered = keys.toList()
      ..sort((String a, String b) => _compareFields(a, b));
    for (final String key in ordered) {
      final bool hasBefore = before.containsKey(key);
      final bool hasAfter = after.containsKey(key);
      _collectJsonChanges(
        hasBefore ? before[key] : null,
        hasAfter ? after[key] : null,
        field: _identifier.hasMatch(key)
            ? '$field.$key'
            : '$field[${jsonEncode(key)}]',
        beforePresent: hasBefore,
        afterPresent: hasAfter,
        changes: changes,
      );
    }
    return;
  }

  if (beforePresent && afterPresent && before is List && after is List) {
    final int length = max(before.length, after.length);
    for (int index = 0; index < length; index++) {
      final bool hasBefore = index < before.length;
      final bool hasAfter = index < after.length;
      _collectJsonChanges(
        hasBefore ? before[index] : null,
        hasAfter ? after[index] : null,
        field: '$field[$index]',
        beforePresent: hasBefore,
        afterPresent: hasAfter,
        changes: changes,
      );
    }
    return;
  }

  if (beforePresent == afterPresent && before == after) return;
  changes.add((
    field: field,
    before: before,
    after: after,
    beforePresent: beforePresent,
    afterPresent: afterPresent,
  ));
}

/// Displays shared JSON locators without splitting dots inside quoted keys.
String formatJsonFieldPath(String field) {
  if (field == r'$') return field;
  final tokens = RegExp(r'\.([^\.\[\]]+)|\[((?:"(?:\\.|[^"\\])*")|\d+)\]');
  final locator = field.startsWith(r'$') ? field : '\$.$field';
  return tokens
      .allMatches(locator)
      .map((match) => match.group(1) ?? '[${match.group(2)}]')
      .join('  ›  ');
}
