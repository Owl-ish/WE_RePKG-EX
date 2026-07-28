import 'dart:io';

import 'package:bot_toast/bot_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:we_repkg/cores/extract.dart';

void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('ensure_output_dir'));
  tearDown(() => temp.deleteSync(recursive: true));

  testWidgets('creates the directory and any missing parents', (tester) async {
    final String target = '${temp.path}\\gone\\deeper\\out';

    await tester.runAsync(() async {
      expect(await ensureOutputDir(target), isTrue);
      expect(await Directory(target).exists(), isTrue);
    });
  });

  testWidgets('succeeds when the directory is already there', (tester) async {
    await tester.runAsync(() async {
      expect(await ensureOutputDir(temp.path), isTrue);
      expect(await ensureOutputDir(temp.path), isTrue);
    });
  });

  testWidgets('reports rather than throwing when it cannot create', (
    tester,
  ) async {
    // BotToast needs a host for the failure toast it shows.
    await tester.pumpWidget(
      MaterialApp(builder: BotToastInit(), home: const SizedBox()),
    );
    final File blocker = File('${temp.path}\\blocker');
    blocker.writeAsStringSync('not a directory');

    await tester.runAsync(() async {
      expect(await ensureOutputDir(blocker.path), isFalse);
    });

    expect(tester.takeException(), isNull);
    BotToast.cleanAll();
    await tester.pump(const Duration(milliseconds: 400));
  });
}
