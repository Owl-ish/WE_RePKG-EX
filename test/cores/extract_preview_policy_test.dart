import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final String source = File('lib/cores/extract.dart').readAsStringSync();

  String functionBody(String start, String next) {
    final int startIndex = source.indexOf(start);
    final int endIndex = source.indexOf(next, startIndex);
    expect(startIndex, isNonNegative, reason: '$start was not found');
    expect(endIndex, greaterThan(startIndex), reason: '$next was not found');
    return source.substring(startIndex, endIndex);
  }

  test('wallpaper extraction never copies the project preview', () {
    final String branch = functionBody(
      'Future<(String?, bool)> extractBranch',
      'Future<String?> copyWallpaperFolderTo',
    );

    expect(branch, isNot(contains('copyProjectPreviewImage(')));
  });

  test('project extraction keeps its preview copy', () {
    final String projectWorker = functionBody(
      'Future<ErrorInfo?> _extractProjectOne',
      'Future<void> exportCurrentProject',
    );

    expect(projectWorker, contains('copyProjectPreviewImage('));
  });
}
