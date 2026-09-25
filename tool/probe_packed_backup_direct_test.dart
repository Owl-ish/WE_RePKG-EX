// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:path/path.dart' as path;
import 'package:we_repkg/cores/backup.dart';
import 'package:we_repkg/cores/scene_pkg_inspection.dart';
import 'package:we_repkg/src/rust/frb_generated.dart';
import 'package:we_repkg/utils/backup_diff.dart';

// Explicit read-only diagnostic. Never part of a normal app scan or test suite.
void main() {
  final String? workshopRoot = Platform.environment['DIRECT_WORKSHOP_ROOT'];
  final String? myProjectsRoot = Platform.environment['DIRECT_MYPROJECTS_ROOT'];
  final String? baselinePath = Platform.environment['DIRECT_BASELINE_CSV'];
  final String? selectedIds = Platform.environment['DIRECT_IDS'];
  final String? nativeLibrary = Platform.environment['DIRECT_RUST_DLL'];
  final bool useNativeEntryBatch =
      Platform.environment['DIRECT_NATIVE_ENTRY_BATCH'] != '0';
  final bool showPaths = Platform.environment['DIRECT_SHOW_PATHS'] == '1';
  final bool showUnavailable =
      Platform.environment['DIRECT_SHOW_UNAVAILABLE'] == '1';
  final bool allPairs = Platform.environment['DIRECT_ALL_PAIRS'] == '1';
  final int workers =
      int.tryParse(Platform.environment['DIRECT_WORKERS'] ?? '') ?? 4;
  test(
    'compare direct whole-pair verdicts with the prior 84-pair baseline',
    () async {
      if (nativeLibrary != null) {
        await RustLib.init(
          externalLibrary: ExternalLibrary.open(nativeLibrary),
        );
      }
      final List<String> lines = await File(baselinePath!).readAsLines();
      final RegExp rowPattern = RegExp(
        r'^"([^"]+)","([^"]+)","[^"]+","([^"]+)","([^"]+)","([^"]+)"$',
      );
      final List<
        ({
          String id,
          String baseline,
          int modified,
          int onlyPacked,
          int onlyUnpacked,
        })
      >
      rows = [];
      for (final String line in lines.skip(1)) {
        final RegExpMatch? match = rowPattern.firstMatch(line);
        if (match == null) throw FormatException('Invalid baseline row');
        if (selectedIds != null &&
            !selectedIds.split(',').contains(match.group(1))) {
          continue;
        }
        rows.add((
          id: match.group(1)!,
          baseline: match.group(2)!,
          modified: int.parse(match.group(3)!),
          onlyPacked: int.parse(match.group(4)!),
          onlyUnpacked: int.parse(match.group(5)!),
        ));
      }
      if (allPairs) {
        final Set<String> known = rows.map((row) => row.id).toSet();
        await for (final FileSystemEntity entity in Directory(
          workshopRoot!,
        ).list(followLinks: false)) {
          if (entity is! Directory) continue;
          final String id = path.basename(entity.path);
          if (selectedIds != null && !selectedIds.split(',').contains(id)) {
            continue;
          }
          if (known.contains(id)) continue;
          final Directory other = Directory(path.join(myProjectsRoot!, id));
          if (!await other.exists()) continue;
          final BackupCopyFormat? first = await inspectBackupCopyFormat(entity);
          final BackupCopyFormat? second = await inspectBackupCopyFormat(other);
          if (!((first == BackupCopyFormat.packed &&
                  second == BackupCopyFormat.unpacked) ||
              (first == BackupCopyFormat.unpacked &&
                  second == BackupCopyFormat.packed))) {
            continue;
          }
          rows.add((
            id: id,
            baseline: 'unknown',
            modified: 0,
            onlyPacked: 0,
            onlyUnpacked: 0,
          ));
        }
      }
      final Stopwatch total = Stopwatch()..start();
      Duration inventoryTime = Duration.zero;
      Duration initialSignatureTime = Duration.zero;
      Duration formatCheckTime = Duration.zero;
      Duration packageIndexTime = Duration.zero;
      Duration unpackedListTime = Duration.zero;
      Duration imageCheckTime = Duration.zero;
      Duration imageByteTime = Duration.zero;
      Duration imagePixelTime = Duration.zero;
      Duration nativeImageTime = Duration.zero;
      Duration dartPixelTime = Duration.zero;
      Duration rawTextureTime = Duration.zero;
      Duration nativeRawTime = Duration.zero;
      int nativePngCalls = 0;
      int nativeJpegCalls = 0;
      int nativeGifCalls = 0;
      int nativeRawCalls = 0;
      int nativeExactCalls = 0;
      int nativeDeclines = 0;
      Duration otherAssetTime = Duration.zero;
      Duration exactEntryTime = Duration.zero;
      Duration wrapperTime = Duration.zero;
      Duration finalSignatureTime = Duration.zero;
      // Timer delay is a headless main-isolate proxy, not a UI frame measure.
      const Duration heartbeat = Duration(milliseconds: 50);
      final Stopwatch heartbeatClock = Stopwatch()..start();
      int lastHeartbeatMs = 0;
      int maxDelayMs = 0;
      int peakRss = ProcessInfo.currentRss;
      final Timer monitor = Timer.periodic(heartbeat, (_) {
        final int nowMs = heartbeatClock.elapsedMilliseconds;
        final int delay = nowMs - lastHeartbeatMs - heartbeat.inMilliseconds;
        if (delay > maxDelayMs) maxDelayMs = delay;
        lastHeartbeatMs = nowMs;
        final int rss = ProcessInfo.currentRss;
        if (rss > peakRss) peakRss = rss;
      });
      final Map<DirectBackupProbeStatus, int> counts =
          <DirectBackupProbeStatus, int>{
            for (final DirectBackupProbeStatus status
                in DirectBackupProbeStatus.values)
              status: 0,
          };
      final List<String> falseMatches = <String>[];
      final List<String> unexpectedDifferences = <String>[];
      final List<String> differenceCountMismatches = <String>[];
      final List<String> unavailable = <String>[];
      final List<String> incompleteDifferences = <String>[];
      final Map<DirectBackupProbeReason, List<String>> unavailableReasons =
          <DirectBackupProbeReason, List<String>>{};
      final List<String> differentIds = <String>[];
      final Map<DirectBackupProbeStatus, int> newCounts =
          <DirectBackupProbeStatus, int>{
            for (final DirectBackupProbeStatus status
                in DirectBackupProbeStatus.values)
              status: 0,
          };
      int next = 0;
      int slowestMilliseconds = 0;
      String slowestId = '';
      Future<void> worker() async {
        while (next < rows.length) {
          final row = rows[next++];
          final Directory workshop = Directory(
            path.join(workshopRoot!, row.id),
          );
          final Directory myProjects = Directory(
            path.join(myProjectsRoot!, row.id),
          );
          final bool workshopPacked =
              await inspectBackupCopyFormat(workshop) ==
              BackupCopyFormat.packed;
          final Stopwatch pair = Stopwatch()..start();
          final DirectBackupProbe result = await probePackedBackupCopyDirect(
            packedFolder: workshopPacked ? workshop : myProjects,
            unpackedFolder: workshopPacked ? myProjects : workshop,
            useNativeImages: nativeLibrary != null,
            useNativeEntryBatch: useNativeEntryBatch,
            onTiming: (timing) {
              inventoryTime += timing.inventory;
              initialSignatureTime += timing.initialSignature;
              formatCheckTime += timing.formatCheck;
              packageIndexTime += timing.packageIndex;
              unpackedListTime += timing.unpackedList;
              imageCheckTime += timing.imageChecks;
              imageByteTime += timing.imageByteChecks;
              imagePixelTime += timing.imagePixelFallbacks;
              nativeImageTime += timing.nativeImageChecks;
              dartPixelTime += timing.dartPixelFallbacks;
              rawTextureTime += timing.rawTextureChecks;
              nativeRawTime += timing.nativeRawChecks;
              nativePngCalls += timing.nativePngCalls;
              nativeJpegCalls += timing.nativeJpegCalls;
              nativeGifCalls += timing.nativeGifCalls;
              nativeRawCalls += timing.nativeRawCalls;
              nativeExactCalls += timing.nativeExactCalls;
              nativeDeclines += timing.nativeDeclines;
              otherAssetTime += timing.otherAssets;
              exactEntryTime += timing.exactEntryChecks;
              wrapperTime += timing.wrapperChecks;
              finalSignatureTime += timing.finalSignature;
            },
          );
          pair.stop();
          counts[result.status] = counts[result.status]! + 1;
          if (row.baseline == 'unknown') {
            newCounts[result.status] = newCounts[result.status]! + 1;
          }
          if (pair.elapsedMilliseconds > slowestMilliseconds) {
            slowestMilliseconds = pair.elapsedMilliseconds;
            slowestId = row.id;
          }
          if (row.baseline != 'unknown' &&
              result.status == DirectBackupProbeStatus.candidateMatch &&
              row.baseline != 'equivalent') {
            falseMatches.add(row.id);
          } else if ((result.status == DirectBackupProbeStatus.different ||
                  result.status ==
                      DirectBackupProbeStatus.differentIncomplete) &&
              row.baseline == 'equivalent') {
            unexpectedDifferences.add(row.id);
            if (unexpectedDifferences.length <= 3) {
              print(
                'DIFF ${row.id} modified=${result.changes.modified.take(8).toList()} '
                'packed=${result.changes.onlyPacked.take(8).toList()} '
                'unpacked=${result.changes.onlyUnpacked.take(8).toList()}',
              );
            }
          }
          if (result.status == DirectBackupProbeStatus.unavailable ||
              result.status == DirectBackupProbeStatus.differentIncomplete) {
            if (result.status == DirectBackupProbeStatus.unavailable) {
              unavailable.add(row.id);
            } else {
              incompleteDifferences.add(row.id);
            }
            if (showUnavailable) {
              print(
                '${result.status.name.toUpperCase()} ${row.id} baseline=${row.baseline} '
                'reasons=${result.reasons.map((reason) => reason.name).toList()} '
                'changes=${result.changes.modified.length}/'
                '${result.changes.onlyPacked.length}/'
                '${result.changes.onlyUnpacked.length}',
              );
            }
            for (final DirectBackupProbeReason reason in result.reasons) {
              unavailableReasons
                  .putIfAbsent(reason, () => <String>[])
                  .add(row.id);
            }
          }
          if (result.status == DirectBackupProbeStatus.different ||
              result.status == DirectBackupProbeStatus.differentIncomplete) {
            differentIds.add(row.id);
            if (showPaths) {
              print(
                'DIFF ${row.id} ${jsonEncode(<String, Object>{'modified': result.changes.modified, 'onlyPacked': result.changes.onlyPacked, 'onlyUnpacked': result.changes.onlyUnpacked})}',
              );
            }
          }
          if (result.status == DirectBackupProbeStatus.different &&
              row.baseline == 'different' &&
              (result.changes.modified.length != row.modified ||
                  result.changes.onlyPacked.length != row.onlyPacked ||
                  result.changes.onlyUnpacked.length != row.onlyUnpacked)) {
            differenceCountMismatches.add(
              '${row.id}: baseline ${row.modified}/${row.onlyPacked}/${row.onlyUnpacked}, '
              'direct ${result.changes.modified.length}/'
              '${result.changes.onlyPacked.length}/'
              '${result.changes.onlyUnpacked.length}',
            );
            if (differenceCountMismatches.length <= 4) {
              print(
                'COUNT ${row.id} modified=${result.changes.modified} '
                'packed=${result.changes.onlyPacked.take(12).toList()}',
              );
            }
          }
        }
      }

      expect(workers, greaterThan(0));
      try {
        await Future.wait(<Future<void>>[
          for (int i = 0; i < workers; i++) worker(),
        ]);
      } finally {
        monitor.cancel();
      }
      total.stop();
      print(
        'Peak RSS ${peakRss ~/ (1024 * 1024)} MiB; max timer delay $maxDelayMs ms',
      );
      print(
        'Summed pair stages: inventory ${inventoryTime.inMilliseconds} ms; '
        'initial signature ${initialSignatureTime.inMilliseconds} ms; '
        'format ${formatCheckTime.inMilliseconds} ms; '
        'index ${packageIndexTime.inMilliseconds} ms; '
        'unpacked list ${unpackedListTime.inMilliseconds} ms; '
        'image checks ${imageCheckTime.inMilliseconds} ms; '
        'other assets ${otherAssetTime.inMilliseconds} ms; '
        'exact entries ${exactEntryTime.inMilliseconds} ms; '
        'wrapper ${wrapperTime.inMilliseconds} ms; '
        'final signature ${finalSignatureTime.inMilliseconds} ms',
      );
      print(
        'Image detail: byte comparisons ${imageByteTime.inMilliseconds} ms; '
        'pixel checks ${imagePixelTime.inMilliseconds} ms '
        '(native ${nativeImageTime.inMilliseconds}, Dart ${dartPixelTime.inMilliseconds}); '
        'raw texture checks ${rawTextureTime.inMilliseconds} ms '
        '(native ${nativeRawTime.inMilliseconds}); '
        'other image overhead ${(imageCheckTime - imageByteTime - imagePixelTime - rawTextureTime).inMilliseconds} ms',
      );
      print(
        'Native image calls: PNG $nativePngCalls; JPEG $nativeJpegCalls; '
        'GIF $nativeGifCalls; raw $nativeRawCalls; exact $nativeExactCalls; declined $nativeDeclines',
      );
      print(
        'Direct verdicts across ${rows.length} pairs with $workers workers: $counts',
      );
      if (allPairs) print('Previously set-aside pair verdicts: $newCounts');
      print(
        'Elapsed ${total.elapsedMilliseconds} ms; slowest '
        '$slowestId $slowestMilliseconds ms',
      );
      print('Candidate matches against baseline differences: $falseMatches');
      print(
        'Direct differences against baseline equivalents: '
        '$unexpectedDifferences',
      );
      print('Changed-file count mismatches: $differenceCountMismatches');
      print('Different IDs: $differentIds');
      print(
        'Unavailable IDs (${unavailable.length}): '
        '${unavailable.take(10).toList()}',
      );
      print(
        'Proven differences with incomplete paths '
        '(${incompleteDifferences.length}): '
        '${incompleteDifferences.take(10).toList()}',
      );
      for (final MapEntry<DirectBackupProbeReason, List<String>> entry
          in unavailableReasons.entries) {
        print(
          '${entry.key.name}: ${entry.value.length} '
          '${entry.value.take(5).toList()}',
        );
      }
      expect(unavailableReasons.values.expand((ids) => ids).toSet(), <String>{
        ...unavailable,
        ...incompleteDifferences,
      });
      expect(falseMatches, isEmpty);
      expect(unexpectedDifferences, isEmpty);
    },
    skip:
        workshopRoot == null || myProjectsRoot == null || baselinePath == null,
    timeout: Timeout(Duration(minutes: allPairs ? 5 : 2)),
  );
}
