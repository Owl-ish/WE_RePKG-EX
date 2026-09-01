import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/ast/token.dart';

const String _primaryLocalePath = 'assets/translations/en-US.json';
const String _comparisonLocalePath = 'assets/translations/zh-CN.json';
const String _outputPath = 'lib/constants/i10n.dart';

final RegExp _validKeySegment = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

final class I10nKeyBinding {
  const I10nKeyBinding({required this.memberName, required this.key});

  final String memberName;
  final String key;
}

List<I10nKeyBinding> buildI10nKeyBindings({
  required Object? primaryLocale,
  required Object? comparisonLocale,
  String primaryName = 'en-US',
  String comparisonName = 'zh-CN',
}) {
  final Map<String, String> primary = _flattenLocale(
    primaryLocale,
    localeName: primaryName,
  );
  final Map<String, String> comparison = _flattenLocale(
    comparisonLocale,
    localeName: comparisonName,
  );

  final Set<String> missingFromComparison = primary.keys.toSet().difference(
    comparison.keys.toSet(),
  );
  final Set<String> missingFromPrimary = comparison.keys.toSet().difference(
    primary.keys.toSet(),
  );
  if (missingFromComparison.isNotEmpty || missingFromPrimary.isNotEmpty) {
    throw FormatException(
      <String>[
        'Locale keys do not match.',
        if (missingFromComparison.isNotEmpty)
          'Missing from $comparisonName: ${missingFromComparison.join(', ')}',
        if (missingFromPrimary.isNotEmpty)
          'Missing from $primaryName: ${missingFromPrimary.join(', ')}',
      ].join('\n'),
    );
  }

  for (final String key in primary.keys) {
    final List<String> primaryPlaceholders = _placeholders(primary[key]!);
    final List<String> comparisonPlaceholders = _placeholders(comparison[key]!);
    if (!_sameStrings(primaryPlaceholders, comparisonPlaceholders)) {
      throw FormatException(
        'Translation placeholders do not match for "$key". '
        '$primaryName: ${primaryPlaceholders.join(', ')}; '
        '$comparisonName: ${comparisonPlaceholders.join(', ')}',
      );
    }
  }

  final Map<String, String> keyByMemberName = <String, String>{};
  return primary.keys
      .map((String key) {
        final String memberName = _memberNameForKey(key);
        final String? existingKey = keyByMemberName[memberName];
        if (existingKey != null) {
          throw FormatException(
            'Keys "$existingKey" and "$key" both generate "$memberName".',
          );
        }
        keyByMemberName[memberName] = key;
        return I10nKeyBinding(memberName: memberName, key: key);
      })
      .toList(growable: false);
}

String generateI10nSource({
  required Object? primaryLocale,
  required Object? comparisonLocale,
  String primaryName = 'en-US',
  String comparisonName = 'zh-CN',
}) {
  final List<I10nKeyBinding> bindings = buildI10nKeyBindings(
    primaryLocale: primaryLocale,
    comparisonLocale: comparisonLocale,
    primaryName: primaryName,
    comparisonName: comparisonName,
  );
  final StringBuffer output = StringBuffer()
    ..writeln('// GENERATED CODE - DO NOT MODIFY BY HAND.')
    ..writeln('//')
    ..writeln(
      '// Run `dart run tool/generate_i10n_keys.dart` after editing locale JSON files.',
    )
    ..writeln()
    ..writeln('class AppI10n {');

  for (final I10nKeyBinding binding in bindings) {
    final String declaration =
        "  static const String ${binding.memberName} = '${binding.key}';";
    if (declaration.length <= 80) {
      output.writeln(declaration);
    } else {
      output
        ..writeln('  static const String ${binding.memberName} =')
        ..writeln("      '${binding.key}';");
    }
  }

  output.writeln('}');
  return output.toString();
}

void main(List<String> arguments) {
  if (arguments.length > 1 ||
      (arguments.isNotEmpty && arguments.single != '--check')) {
    stderr.writeln('Usage: dart run tool/generate_i10n_keys.dart [--check]');
    exitCode = 64;
    return;
  }

  final Directory repositoryRoot = File.fromUri(Platform.script).parent.parent;
  final File primaryFile = File(
    '${repositoryRoot.path}${Platform.pathSeparator}$_primaryLocalePath',
  );
  final File comparisonFile = File(
    '${repositoryRoot.path}${Platform.pathSeparator}$_comparisonLocalePath',
  );
  final File outputFile = File(
    '${repositoryRoot.path}${Platform.pathSeparator}$_outputPath',
  );

  try {
    final String generated = generateI10nSource(
      primaryLocale: jsonDecode(primaryFile.readAsStringSync()),
      comparisonLocale: jsonDecode(comparisonFile.readAsStringSync()),
    );
    final String current = outputFile.existsSync()
        ? _normalizeLineEndings(outputFile.readAsStringSync())
        : '';

    if (arguments.singleOrNull == '--check') {
      if (current != generated) {
        stderr.writeln(
          '$_outputPath is out of date. Run the localization key generator.',
        );
        exitCode = 1;
      } else {
        stdout.writeln('$_outputPath is up to date.');
      }
      return;
    }

    if (current == generated) {
      stdout.writeln('$_outputPath is already up to date.');
      return;
    }
    outputFile.writeAsStringSync(generated, flush: true);
    stdout.writeln('Generated $_outputPath (${generated.length} bytes).');
  } on FormatException catch (error) {
    stderr.writeln('Localization generation failed: ${error.message}');
    exitCode = 65;
  } on FileSystemException catch (error) {
    stderr.writeln('Localization generation failed: ${error.message}');
    exitCode = 74;
  }
}

Map<String, String> _flattenLocale(Object? root, {required String localeName}) {
  if (root is! Map<String, dynamic>) {
    throw FormatException('$localeName must contain one JSON object.');
  }

  final Map<String, String> leaves = <String, String>{};

  void visit(Map<String, dynamic> object, String prefix) {
    if (object.isEmpty && prefix.isNotEmpty) {
      throw FormatException(
        '$localeName contains an empty group at "$prefix".',
      );
    }
    for (final MapEntry<String, dynamic> entry in object.entries) {
      if (!_validKeySegment.hasMatch(entry.key)) {
        throw FormatException(
          '$localeName contains an unsupported key segment "${entry.key}".',
        );
      }
      final String path = prefix.isEmpty ? entry.key : '$prefix.${entry.key}';
      final Object? value = entry.value;
      if (value is Map<String, dynamic>) {
        visit(value, path);
      } else if (value is String) {
        leaves[path] = value;
      } else {
        throw FormatException(
          '$localeName translation "$path" must be a string.',
        );
      }
    }
  }

  visit(root, '');
  return leaves;
}

String _memberNameForKey(String key) {
  final List<String> segments = key.split('.');
  final StringBuffer name = StringBuffer(segments.first);
  for (final String segment in segments.skip(1)) {
    name
      ..write(segment[0].toUpperCase())
      ..write(segment.substring(1));
  }
  final String memberName = name.toString();
  if (Keyword.keywords.containsKey(memberName)) {
    throw FormatException(
      'Translation key "$key" generates reserved Dart word "$memberName".',
    );
  }
  return memberName;
}

List<String> _placeholders(String value) => (RegExp(
  r'\{[^{}]*\}',
).allMatches(value).map((match) => match.group(0)!)).toList()..sort();

bool _sameStrings(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

String _normalizeLineEndings(String value) => value.replaceAll('\r\n', '\n');
