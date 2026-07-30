import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Dotted leaf keys, matching the strings AppI10n holds.
Set<String> leafKeys(Map<String, dynamic> json, [String prefix = '']) {
  final Set<String> out = <String>{};
  json.forEach((key, value) {
    final String path = prefix.isEmpty ? key : '$prefix.$key';
    if (value is Map<String, dynamic>) {
      out.addAll(leafKeys(value, path));
    } else {
      out.add(path);
    }
  });
  return out;
}

Set<String> load(String language) => leafKeys(
  jsonDecode(File('assets/translations/$language.json').readAsStringSync())
      as Map<String, dynamic>,
);

// Nothing else covers the translation files: every tr() in the suite returns the
// raw key, so a key added to one language and forgotten in the other, or a
// constant left behind by a cut feature, would ship unnoticed.
void main() {
  final Set<String> en = load('en-US');
  final Set<String> zh = load('zh-CN');
  // Every literal in the file, since a declaration can wrap onto its own line.
  final Set<String> declared = RegExp(r"'([a-zA-Z][\w.]*)'")
      .allMatches(File('lib/constants/i10n.dart').readAsStringSync())
      .map((m) => m.group(1)!)
      .toSet();

  test('both languages carry the same keys', () {
    expect(en.difference(zh), isEmpty, reason: 'missing from zh-CN');
    expect(zh.difference(en), isEmpty, reason: 'missing from en-US');
  });

  test('every declared key exists', () {
    expect(declared.difference(en), isEmpty);
  });

  test('every key is declared, so cut features leave nothing behind', () {
    expect(en.difference(declared), isEmpty);
  });
}
