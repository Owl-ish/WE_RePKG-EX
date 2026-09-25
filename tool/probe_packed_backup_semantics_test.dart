// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:path/path.dart' as path;
import 'package:we_repkg/cores/backup.dart';
import 'package:we_repkg/cores/extract.dart';
import 'package:we_repkg/cores/scene_pkg_inspection.dart';
import 'package:we_repkg/src/rust/api/simple.dart';
import 'package:we_repkg/src/rust/frb_generated.dart';
import 'package:we_repkg/utils/backup_diff.dart';
import 'package:we_repkg/utils/cancel_token.dart';
import 'package:we_repkg/utils/repkg_output.dart';

// Run explicitly with the probe environment variables; never part of app scans.
void main() {
  final String? workshopRoot = Platform.environment['BATCH_WORKSHOP_ROOT'];
  final String? myProjectsRoot = Platform.environment['BATCH_MYPROJECTS_ROOT'];
  final String? tool = Platform.environment['BATCH_REPKG_TOOL'];
  final String? idsText = Platform.environment['BATCH_IDS'];
  final String? nativeLibrary = Platform.environment['BATCH_RUST_DLL'];
  final bool profile = Platform.environment['BATCH_PROFILE'] == '1';
  final int concurrency =
      int.tryParse(Platform.environment['BATCH_CONCURRENCY'] ?? '') ?? 1;
  test(
    'read-only semantic batch probe',
    () async {
      if (nativeLibrary != null) {
        await RustLib.init(
          externalLibrary: ExternalLibrary.open(nativeLibrary),
        );
      }
      if (concurrency < 1 || concurrency > 4) {
        throw ArgumentError.value(concurrency, 'BATCH_CONCURRENCY');
      }
      final List<String> ids = idsText!.split(',');
      final Stopwatch total = Stopwatch()..start();
      int nativeEqual = 0;
      int nativeDifferent = 0;
      int nativeFallback = 0;
      int nativeErrors = 0;
      final Map<BackupCopyVerificationStatus, List<String>> results =
          <BackupCopyVerificationStatus, List<String>>{
            for (final BackupCopyVerificationStatus status
                in BackupCopyVerificationStatus.values)
              status: <String>[],
          };
      Future<void> verifyId(String id) async {
        final Directory first = Directory(path.join(workshopRoot!, id));
        final Directory second = Directory(path.join(myProjectsRoot!, id));
        final bool firstPacked =
            await inspectBackupCopyFormat(first) == BackupCopyFormat.packed;
        final Stopwatch timer = Stopwatch()..start();
        int extractMilliseconds = 0;
        int conversionMilliseconds = 0;
        int conversions = 0;
        int nativeImageMilliseconds = 0;
        int nativeImageCalls = 0;
        Future<bool> runMeasured(
          List<String> args,
          CancelToken token, {
          required bool extraction,
        }) async {
          final Stopwatch stage = Stopwatch()..start();
          final result = await runRePKG(tool!, args, token);
          stage.stop();
          if (extraction) {
            extractMilliseconds += stage.elapsedMilliseconds;
          } else {
            conversionMilliseconds += stage.elapsedMilliseconds;
            conversions++;
          }
          final RePKGOutputSummary summary = summarizeRePKGOutput(
            result.stdout,
            result.stderr,
          );
          return result.exitCode == 0 && !summary.claimedSuccessWithoutWriting;
        }

        final BackupCopyVerification result = await verifyPackedBackupCopy(
          tool: tool!,
          packedFolder: firstPacked ? first : second,
          unpackedFolder: firstPacked ? second : first,
          // Injection skips the verifier's quick TEX precheck; profile only
          // these already-unresolved pairs' deeper comparison stages.
          extract: profile
              ? (String _, File package, Directory output, CancelToken token) =>
                    runMeasured(
                      <String>[
                        'extract',
                        '-c',
                        '-o',
                        output.path,
                        package.path,
                      ],
                      token,
                      extraction: true,
                    )
              : null,
          convertTexture: profile
              ? (String _, File texture, Directory output, CancelToken token) =>
                    runMeasured(
                      <String>['extract', '-o', output.path, texture.path],
                      token,
                      extraction: false,
                    )
              : null,
          comparePngPixels: nativeLibrary == null
              ? null
              : (File first, File second) async {
                  final Stopwatch nativeTimer = Stopwatch()..start();
                  try {
                    final bool? same = await comparePngPixelsRust(
                      firstPath: first.path,
                      secondPath: second.path,
                    );
                    if (same == true) {
                      nativeEqual++;
                    } else if (same == false) {
                      nativeDifferent++;
                    } else {
                      nativeFallback++;
                    }
                    return same;
                  } catch (_) {
                    nativeErrors++;
                    rethrow;
                  } finally {
                    nativeImageMilliseconds += nativeTimer.elapsedMilliseconds;
                    nativeImageCalls++;
                  }
                },
        );
        timer.stop();
        results[result.status]!.add(id);
        print('$id ${result.status.name} ${timer.elapsedMilliseconds} ms');
        if (profile) {
          print(
            'PROFILE $id extract=$extractMilliseconds convert=$conversionMilliseconds '
            'calls=$conversions native=$nativeImageMilliseconds nativeCalls=$nativeImageCalls '
            'remainder=${timer.elapsedMilliseconds - extractMilliseconds - conversionMilliseconds - nativeImageMilliseconds}',
          );
        }
        if (result.status == BackupCopyVerificationStatus.different) {
          print(
            'DIFF $id ${jsonEncode(<String, Object>{'modified': result.changes.modified, 'onlyPacked': result.changes.onlyPacked, 'onlyUnpacked': result.changes.onlyUnpacked})}',
          );
        }
      }

      int next = 0;
      Future<void> worker() async {
        while (next < ids.length) {
          final String id = ids[next++];
          await verifyId(id);
        }
      }

      int peakSampledRss = ProcessInfo.currentRss;
      final Timer memorySampler = Timer.periodic(
        const Duration(milliseconds: 250),
        (_) {
          final int rss = ProcessInfo.currentRss;
          if (rss > peakSampledRss) peakSampledRss = rss;
        },
      );
      try {
        await Future.wait(
          List<Future<void>>.generate(concurrency, (_) => worker()),
        );
      } finally {
        memorySampler.cancel();
      }
      total.stop();
      for (final MapEntry<BackupCopyVerificationStatus, List<String>> result
          in results.entries) {
        print('${result.key.name}: ${result.value.length}');
        if (result.key != BackupCopyVerificationStatus.different) {
          print('${result.key.name} IDs: ${result.value.join(', ')}');
        }
      }
      print('Semantic batch elapsed: ${total.elapsedMilliseconds} ms');
      print('Peak sampled test-process RSS: $peakSampledRss bytes');
      if (nativeLibrary != null) {
        print(
          'Native PNG: equal=$nativeEqual different=$nativeDifferent fallback=$nativeFallback errors=$nativeErrors',
        );
      }
    },
    skip:
        workshopRoot == null ||
        myProjectsRoot == null ||
        tool == null ||
        idsText == null,
    timeout: const Timeout(Duration(hours: 1)),
  );
}
