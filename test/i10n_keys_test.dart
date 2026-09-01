import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/generate_i10n_keys.dart';

Object? loadLocale(String language) =>
    jsonDecode(File('assets/translations/$language.json').readAsStringSync());

void main() {
  final Object? en = loadLocale('en-US');
  final Object? zh = loadLocale('zh-CN');

  test('the generated catalog matches both locale files', () {
    final String generated = generateI10nSource(
      primaryLocale: en,
      comparisonLocale: zh,
    );
    final String committed = File(
      'lib/constants/i10n.dart',
    ).readAsStringSync().replaceAll('\r\n', '\n');

    expect(committed, generated);
  });

  test('generation rejects locale key differences', () {
    expect(
      () => generateI10nSource(
        primaryLocale: <String, Object?>{
          'home': <String, Object?>{'title': 'Title'},
        },
        comparisonLocale: <String, Object?>{
          'home': <String, Object?>{'other': '其他'},
        },
      ),
      throwsA(
        isA<FormatException>().having(
          (FormatException error) => error.message,
          'message',
          contains('Locale keys do not match'),
        ),
      ),
    );
  });

  test('generation rejects values that are not translated strings', () {
    expect(
      () => generateI10nSource(
        primaryLocale: <String, Object?>{
          'home': <String, Object?>{'title': 42},
        },
        comparisonLocale: <String, Object?>{
          'home': <String, Object?>{'title': '标题'},
        },
      ),
      throwsA(
        isA<FormatException>().having(
          (FormatException error) => error.message,
          'message',
          contains('must be a string'),
        ),
      ),
    );
  });

  test('generation rejects translated placeholders that do not match', () {
    expect(
      () => generateI10nSource(
        primaryLocale: <String, Object?>{
          'backup': <String, Object?>{'count': 'Found {count}'},
        },
        comparisonLocale: <String, Object?>{
          'backup': <String, Object?>{'count': '找到 {total} 个'},
        },
      ),
      throwsA(
        isA<FormatException>().having(
          (FormatException error) => error.message,
          'message',
          contains('Translation placeholders do not match'),
        ),
      ),
    );
  });

  test('generation rejects keys that would create the same Dart name', () {
    final Map<String, Object?> locale = <String, Object?>{
      'a': <String, Object?>{'bC': 'One'},
      'aB': <String, Object?>{'c': 'Two'},
    };

    expect(
      () => generateI10nSource(primaryLocale: locale, comparisonLocale: locale),
      throwsA(
        isA<FormatException>().having(
          (FormatException error) => error.message,
          'message',
          contains('both generate "aBC"'),
        ),
      ),
    );
  });

  test('every generated key is used by production code', () {
    final Set<String> declared = buildI10nKeyBindings(
      primaryLocale: en,
      comparisonLocale: zh,
    ).map((I10nKeyBinding binding) => binding.memberName).toSet();
    final Set<String> used = <String>{};

    for (final File file in Directory(
      'lib',
    ).listSync(recursive: true).whereType<File>()) {
      final String path = file.path.replaceAll('\\', '/');
      if (!path.endsWith('.dart') || path == 'lib/constants/i10n.dart') {
        continue;
      }
      final parsed = parseString(content: file.readAsStringSync(), path: path);
      expect(parsed.errors, isEmpty, reason: 'Could not parse $path');
      parsed.unit.accept(_AppI10nUseVisitor(used));
    }

    expect(
      declared.difference(used),
      isEmpty,
      reason: 'Remove unused entries from both locale files.',
    );
  });
}

final class _AppI10nUseVisitor extends RecursiveAstVisitor<void> {
  _AppI10nUseVisitor(this.used);

  final Set<String> used;

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    if (node.prefix.name == 'AppI10n') {
      used.add(node.identifier.name);
    }
    super.visitPrefixedIdentifier(node);
  }

  @override
  void visitPropertyAccess(PropertyAccess node) {
    final Expression? target = node.target;
    if (target is SimpleIdentifier && target.name == 'AppI10n') {
      used.add(node.propertyName.name);
    }
    super.visitPropertyAccess(node);
  }
}
