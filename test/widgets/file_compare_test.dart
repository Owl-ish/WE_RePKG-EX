import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:we_repkg/config/theme.dart';
import 'package:we_repkg/widgets/file_compare.dart';

import '../support/backup_test_harness.dart';

void main() {
  group('shared explicit file comparison', () {
    test(
      'comparison availability falls back to metadata for concrete files',
      () {
        expect(canCompareFilePaths('before.png', 'after.jpg'), isTrue);
        expect(canCompareFilePaths('before.json', 'after.txt'), isTrue);
        expect(canCompareFilePaths('before.pkg', 'after.pkg'), isTrue);
        expect(canCompareFilePaths('before.png', 'after.txt'), isTrue);
        expect(canCompareFilePaths('', 'after.pkg'), isFalse);
        expect(canCompareFilePaths('before.pkg', '   '), isFalse);
      },
    );

    test('JSON field locators are presented as readable breadcrumbs', () {
      expect(
        formatJsonFieldPath(r'$.objects[2].anchor'),
        'objects  ›  [2]  ›  anchor',
      );
      expect(formatJsonFieldPath(r'$.title'), 'title');
    });

    testWidgets('valid text JSON uses structured field comparison', (
      tester,
    ) async {
      final Directory root = Directory.systemTemp.createTempSync(
        'we_repkg_manual_json_compare',
      );
      addTearDown(() {
        if (root.existsSync()) root.deleteSync(recursive: true);
      });
      final File before = File(
        '${root.path}${Platform.pathSeparator}before.json',
      )..writeAsStringSync('{"title":"Old","nested":{"strength":1}}');
      final File after = File('${root.path}${Platform.pathSeparator}after.json')
        ..writeAsStringSync('{"title":"New","nested":{"strength":2}}');

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: Center(
              child: FileTreeCompareAction(
                key: const ValueKey<String>('manual-json-compare-action'),
                first: FileComparisonSide(label: 'Before', path: before.path),
                second: FileComparisonSide(label: 'After', path: after.path),
                title: 'Compare files',
                tooltip: 'Compare files',
                unavailableText: 'Unavailable',
                jsonModeLabel: 'Structured JSON',
                textModeLabel: 'Text comparison',
                jsonNoDifferencesText: 'No value differences',
                missingValueText: 'Missing',
                truncatedText: 'Truncated',
                binaryModeLabel: 'File metadata + SHA-256',
                fileTypeLabel: 'Type',
                fileSizeLabel: 'Size',
                fileModifiedLabel: 'Modified',
                hashLabel: 'SHA-256',
                sameText: 'Same',
                differentText: 'Different',
                noExtensionText: 'No extension',
                foreground: Colors.black,
              ),
            ),
          ),
        ),
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('manual-json-compare-action')),
      );
      await tester.pump();
      final Finder jsonContent = find.byKey(
        const ValueKey<String>('file-json-compare-content'),
      );
      for (
        int attempt = 0;
        attempt < 40 && jsonContent.evaluate().isEmpty;
        attempt++
      ) {
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 25));
        });
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(
        find.byKey(const ValueKey<String>('file-text-compare-dialog')),
        findsOneWidget,
      );
      expect(jsonContent, findsOneWidget);
      expect(find.text('title'), findsOneWidget);
      expect(find.text('nested  ›  strength'), findsOneWidget);
      expect(find.byTooltip(r'$.title'), findsNothing);
      expect(find.byTooltip(r'$.nested.strength'), findsNothing);
      expect(
        tester
            .widget<SelectableText>(
              find.byKey(const ValueKey<String>(r'file-json-before-$.title')),
            )
            .data,
        '"Old"',
      );
      expect(
        tester
            .widget<SelectableText>(
              find.byKey(const ValueKey<String>(r'file-json-after-$.title')),
            )
            .data,
        '"New"',
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('file-text-dialog-close')),
      );
      await settle(tester);
    });

    testWidgets('invalid JSON falls back to side-by-side text', (tester) async {
      final Directory root = Directory.systemTemp.createTempSync(
        'we_repkg_manual_text_compare',
      );
      addTearDown(() {
        if (root.existsSync()) root.deleteSync(recursive: true);
      });
      final File before = File(
        '${root.path}${Platform.pathSeparator}before.json',
      )..writeAsStringSync('old text that is not json');
      final File after = File('${root.path}${Platform.pathSeparator}after.json')
        ..writeAsStringSync('{"valid":"json"}');

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: Center(
              child: FileTreeCompareAction(
                key: const ValueKey<String>('manual-text-compare-action'),
                first: FileComparisonSide(label: 'Before', path: before.path),
                second: FileComparisonSide(label: 'After', path: after.path),
                title: 'Compare files',
                tooltip: 'Compare files',
                unavailableText: 'Unavailable',
                jsonModeLabel: 'Structured JSON',
                textModeLabel: 'Text comparison',
                jsonNoDifferencesText: 'No value differences',
                missingValueText: 'Missing',
                truncatedText: 'Truncated',
                binaryModeLabel: 'File metadata + SHA-256',
                fileTypeLabel: 'Type',
                fileSizeLabel: 'Size',
                fileModifiedLabel: 'Modified',
                hashLabel: 'SHA-256',
                sameText: 'Same',
                differentText: 'Different',
                noExtensionText: 'No extension',
                foreground: Colors.black,
              ),
            ),
          ),
        ),
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('manual-text-compare-action')),
      );
      await tester.pump();
      final Finder textContent = find.byKey(
        const ValueKey<String>('file-plain-text-compare-content'),
      );
      for (
        int attempt = 0;
        attempt < 40 && textContent.evaluate().isEmpty;
        attempt++
      ) {
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 25));
        });
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(textContent, findsOneWidget);
      expect(
        find.byKey(ValueKey<String>('file-text-${before.path}')),
        findsOneWidget,
      );
      expect(find.text('Text comparison'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('file-json-compare-content')),
        findsNothing,
      );
    });

    testWidgets('binary files show metadata and streamed SHA-256 differences', (
      tester,
    ) async {
      final Directory root = Directory.systemTemp.createTempSync(
        'we_repkg_manual_binary_compare',
      );
      addTearDown(() {
        if (root.existsSync()) root.deleteSync(recursive: true);
      });
      final File before = File(
        '${root.path}${Platform.pathSeparator}before.pkg',
      )..writeAsBytesSync(utf8.encode('abc'));
      final File after = File('${root.path}${Platform.pathSeparator}after.pkg')
        ..writeAsBytesSync(utf8.encode('abd'));

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: Center(
              child: FileTreeCompareAction(
                key: const ValueKey<String>('manual-binary-compare-action'),
                first: FileComparisonSide(label: 'Before', path: before.path),
                second: FileComparisonSide(label: 'After', path: after.path),
                title: 'Compare files',
                tooltip: 'Compare files',
                unavailableText: 'Unavailable',
                jsonModeLabel: 'Structured JSON',
                textModeLabel: 'Text comparison',
                jsonNoDifferencesText: 'No value differences',
                missingValueText: 'Missing',
                truncatedText: 'Truncated',
                binaryModeLabel: 'File metadata + SHA-256',
                fileTypeLabel: 'Type',
                fileSizeLabel: 'Size',
                fileModifiedLabel: 'Modified',
                hashLabel: 'SHA-256',
                sameText: 'Same',
                differentText: 'Different',
                noExtensionText: 'No extension',
                foreground: Colors.black,
              ),
            ),
          ),
        ),
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('manual-binary-compare-action')),
      );
      await tester.pump();
      final Finder binaryContent = find.byKey(
        const ValueKey<String>('file-binary-compare-content'),
      );
      for (
        int attempt = 0;
        attempt < 40 && binaryContent.evaluate().isEmpty;
        attempt++
      ) {
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 25));
        });
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(
        find.byKey(const ValueKey<String>('file-binary-compare-dialog')),
        findsOneWidget,
      );
      expect(binaryContent, findsOneWidget);
      expect(find.text('File metadata + SHA-256'), findsOneWidget);
      expect(
        tester
            .widget<SelectableText>(
              find.byKey(const ValueKey<String>('file-binary-before-sha256')),
            )
            .data,
        'ba7816bf8f01cfea414140de5dae2223'
        'b00361a396177a9cb410ff61f20015ad',
      );
      expect(
        tester
            .widget<SelectableText>(
              find.byKey(const ValueKey<String>('file-binary-before-type')),
            )
            .data,
        'PKG',
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('file-binary-status-size')),
          matching: find.text('Same'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('file-binary-status-sha256')),
          matching: find.text('Different'),
        ),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('file-binary-dialog-close')),
      );
      await settle(tester);
    });
  });
}
