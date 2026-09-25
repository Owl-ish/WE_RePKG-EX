import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'
    show Notifier, NotifierProvider, Provider;
import 'package:path/path.dart' as path;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:we_repkg/constants/keys.dart';
import 'package:we_repkg/cores/backup.dart';
import 'package:we_repkg/cores/scene_pkg_inspection.dart';
import 'package:we_repkg/models/enums.dart';
import 'package:we_repkg/provider/filter.dart';
import 'package:we_repkg/provider/system.dart';
import 'package:we_repkg/utils/backup_diff.dart';
import 'package:we_repkg/utils/backup_tiles.dart';
import 'package:we_repkg/utils/cancel_token.dart';
import 'package:we_repkg/utils/storage.dart';

part 'backup.g.dart';

typedef _VerificationJob = ({
  String key,
  CancelToken? token,
  Future<BackupCopyVerification> Function() run,
  Completer<BackupCopyVerification> result,
});

/// Deduplicates explicit checks and bounds concurrent RePKG extractions.
class BackupVerificationCoordinator {
  static const int _workerCount = 2;

  final Queue<_VerificationJob> _jobs = Queue<_VerificationJob>();
  final Map<String, Future<BackupCopyVerification>> _pending =
      <String, Future<BackupCopyVerification>>{};
  int _running = 0;

  Future<BackupCopyVerification> verify({
    required String backupRoot,
    required String name,
    required String tool,
    required Directory packedFolder,
    required Directory unpackedFolder,
    required String signature,
    CancelToken? cancelToken,
  }) async {
    if (cancelToken?.isCancelled == true) {
      return const BackupCopyVerification(
        status: BackupCopyVerificationStatus.unavailable,
        signature: '',
      );
    }
    final FileStat toolStat;
    try {
      toolStat = await File(tool).stat();
    } on FileSystemException {
      return const BackupCopyVerification(
        status: BackupCopyVerificationStatus.unavailable,
        signature: '',
      );
    }
    if (toolStat.type != FileSystemEntityType.file) {
      return const BackupCopyVerification(
        status: BackupCopyVerificationStatus.unavailable,
        signature: '',
      );
    }
    if (cancelToken?.isCancelled == true ||
        await backupCopyVerificationSignature(
              packedFolder: packedFolder,
              unpackedFolder: unpackedFolder,
            ) !=
            signature) {
      return const BackupCopyVerification(
        status: BackupCopyVerificationStatus.unavailable,
        signature: '',
      );
    }
    final String nameKey = name.toLowerCase();
    final String jobKey =
        '$backupRoot\n$nameKey\n$signature\n${path.normalize(tool).toLowerCase()}';
    return _pending.putIfAbsent(jobKey, () {
      final Completer<BackupCopyVerification> result =
          Completer<BackupCopyVerification>();
      _jobs.add((
        key: jobKey,
        token: cancelToken,
        result: result,
        run: () async {
          final BackupCopyVerification verified = await verifyPackedBackupCopy(
            tool: tool,
            packedFolder: packedFolder,
            unpackedFolder: unpackedFolder,
            cancelToken: cancelToken,
          );
          return verified.signature == signature
              ? BackupCopyVerification(
                  status: verified.status,
                  signature: verified.signature,
                  changes: verified.changes,
                )
              : BackupCopyVerification(
                  status: BackupCopyVerificationStatus.unavailable,
                  signature: verified.signature,
                );
        },
      ));
      _pump();
      return result.future;
    });
  }

  void _pump() {
    while (_running < _workerCount && _jobs.isNotEmpty) {
      final _VerificationJob job = _jobs.removeFirst();
      if (job.token?.isCancelled == true) {
        job.result.complete(
          const BackupCopyVerification(
            status: BackupCopyVerificationStatus.unavailable,
            signature: '',
          ),
        );
        _pending.remove(job.key);
        continue;
      }
      _running++;
      unawaited(() async {
        try {
          final BackupCopyVerification value = await job.run();
          job.result.complete(value);
        } catch (error, stackTrace) {
          job.result.completeError(error, stackTrace);
        } finally {
          final _ = _pending.remove(job.key);
          _running--;
          _pump();
        }
      }());
    }
  }
}

final Provider<BackupVerificationCoordinator>
backupVerificationCoordinatorProvider = Provider<BackupVerificationCoordinator>(
  (ref) => BackupVerificationCoordinator(),
);

typedef BackupDirectBatchState = ({
  BackupScan? scan,
  String? backupRoot,
  bool running,
  bool cancelled,
  int done,
  int total,
  Map<String, DirectBackupProbe> results,
});

typedef DirectBackupProbeRunner =
    Future<DirectBackupProbe> Function({
      required Directory packedFolder,
      required Directory unpackedFolder,
      String? expectedSignature,
      CancelToken? cancelToken,
    });

/// Read-only, explicitly started content checks for current Reconcile conflicts.
/// Results are diagnostic; a future removal action must verify its target again.
class BackupDirectBatch extends ValueNotifier<BackupDirectBatchState> {
  BackupDirectBatch({DirectBackupProbeRunner? probe})
    : _diagnosticsEnabled = kDebugMode && probe == null,
      super((
        scan: null,
        backupRoot: null,
        running: false,
        cancelled: false,
        done: 0,
        total: 0,
        results: const <String, DirectBackupProbe>{},
      )) {
    _probe =
        probe ??
        ({
          required packedFolder,
          required unpackedFolder,
          expectedSignature,
          cancelToken,
        }) => probePackedBackupCopyDirect(
          packedFolder: packedFolder,
          unpackedFolder: unpackedFolder,
          expectedSignature: expectedSignature,
          cancelToken: cancelToken,
          onTiming: _diagnosticsEnabled ? _recordTiming : null,
        );
  }

  static const int _workers = 4;
  late final DirectBackupProbeRunner _probe;
  final bool _diagnosticsEnabled;
  CancelToken? _token;
  bool _disposed = false;
  Duration _inventoryTime = Duration.zero;
  Duration _initialSignatureTime = Duration.zero;
  Duration _formatCheckTime = Duration.zero;
  Duration _packageIndexTime = Duration.zero;
  Duration _unpackedListTime = Duration.zero;
  Duration _byteTime = Duration.zero;
  Duration _nativeImageTime = Duration.zero;
  Duration _dartPixelTime = Duration.zero;
  Duration _rawTime = Duration.zero;
  Duration _nativeRawTime = Duration.zero;
  Duration _otherAssetTime = Duration.zero;
  Duration _exactEntryTime = Duration.zero;
  Duration _wrapperTime = Duration.zero;
  Duration _signatureTime = Duration.zero;
  Duration _notificationTime = Duration.zero;
  int _maxTimerDelayMs = 0;
  int _delayedTicks = 0;
  int _nativeImageCalls = 0;
  int _nativeRawCalls = 0;
  int _nativeExactCalls = 0;
  int _nativeDeclines = 0;
  int _timedPairs = 0;
  int _slowestPairMs = 0;
  String _slowestPairId = '';

  void _recordTiming(DirectBackupProbeTiming timing) {
    _timedPairs++;
    _inventoryTime += timing.inventory;
    _initialSignatureTime += timing.initialSignature;
    _formatCheckTime += timing.formatCheck;
    _packageIndexTime += timing.packageIndex;
    _unpackedListTime += timing.unpackedList;
    _byteTime += timing.imageByteChecks;
    _nativeImageTime += timing.nativeImageChecks;
    _dartPixelTime += timing.dartPixelFallbacks;
    _rawTime += timing.rawTextureChecks;
    _nativeRawTime += timing.nativeRawChecks;
    _otherAssetTime += timing.otherAssets;
    _exactEntryTime += timing.exactEntryChecks;
    _wrapperTime += timing.wrapperChecks;
    _signatureTime += timing.finalSignature;
    _nativeImageCalls +=
        timing.nativePngCalls + timing.nativeJpegCalls + timing.nativeGifCalls;
    _nativeRawCalls += timing.nativeRawCalls;
    _nativeExactCalls += timing.nativeExactCalls;
    _nativeDeclines += timing.nativeDeclines;
  }

  void _logTiming(Stopwatch clock, int checked, int total) {
    debugPrint(
      '[reconcile-timing] checked=$checked/$total timed=$_timedPairs '
      'wall=${clock.elapsedMilliseconds}ms '
      'summed_ms(inventory=${_inventoryTime.inMilliseconds}, '
      'initialSig=${_initialSignatureTime.inMilliseconds}, '
      'format=${_formatCheckTime.inMilliseconds}, '
      'index=${_packageIndexTime.inMilliseconds}, '
      'unpackedList=${_unpackedListTime.inMilliseconds}, '
      'bytes=${_byteTime.inMilliseconds}, nativeImage=${_nativeImageTime.inMilliseconds}, '
      'dartPixels=${_dartPixelTime.inMilliseconds}, '
      'rawTotal=${_rawTime.inMilliseconds}, rawNative=${_nativeRawTime.inMilliseconds}, '
      'other=${_otherAssetTime.inMilliseconds}, '
      'exact=${_exactEntryTime.inMilliseconds}, wrapper=${_wrapperTime.inMilliseconds}, '
      'signature=${_signatureTime.inMilliseconds}) '
      'ui(notify=${_notificationTime.inMilliseconds}, '
      'maxDelay=$_maxTimerDelayMs, delayedTicks=$_delayedTicks) '
      'native(image=$_nativeImageCalls, raw=$_nativeRawCalls, exact=$_nativeExactCalls, '
      'declined=$_nativeDeclines) '
      'slowest=$_slowestPairId:${_slowestPairMs}ms',
    );
  }

  static bool eligible(ReconcileEntry entry) {
    final BackupCopyDifference? difference = entry.backupDifference;
    return entry.activeReasons.contains(
          BackupReconcileReason.conflictingBackupCopies,
        ) &&
        difference?.verificationSignature != null &&
        <BackupCopyFormat>{
          difference!.workshopFormat,
          difference.myProjectsFormat,
        }.containsAll(<BackupCopyFormat>{
          BackupCopyFormat.packed,
          BackupCopyFormat.unpacked,
        });
  }

  BackupDirectBatchState forScan(BackupScan scan, String? root) =>
      identical(value.scan, scan) && value.backupRoot == root
      ? value
      : (
          scan: scan,
          backupRoot: root,
          running: false,
          cancelled: false,
          done: 0,
          total: 0,
          results: const <String, DirectBackupProbe>{},
        );

  List<ReconcileEntry> matchedEntries({
    required BackupScan scan,
    required String? backupRoot,
    required Iterable<ReconcileEntry> entries,
  }) {
    final BackupDirectBatchState check = forScan(scan, backupRoot);
    if (check.running ||
        check.cancelled ||
        check.total == 0 ||
        check.done != check.total) {
      return const <ReconcileEntry>[];
    }
    return <ReconcileEntry>[
      for (final ReconcileEntry entry in entries)
        if (eligible(entry) &&
            check.results[entry.name.toLowerCase()]?.status ==
                DirectBackupProbeStatus.candidateMatch)
          entry,
    ];
  }

  Future<void> start({
    required BackupScan scan,
    required String backupRoot,
    required Iterable<ReconcileEntry> entries,
  }) async {
    if (value.running || _disposed) return;
    final List<ReconcileEntry> targets = entries.where(eligible).toList();
    if (targets.isEmpty) return;
    // A cancelled run keeps completed results for this same scan. A fresh run
    // after completion checks everything again, so Check can refresh results.
    final bool resume =
        value.cancelled &&
        value.done < targets.length &&
        identical(value.scan, scan) &&
        value.backupRoot == backupRoot;
    final Map<String, DirectBackupProbe> completed = resume
        ? <String, DirectBackupProbe>{
            for (final ReconcileEntry entry in targets)
              if (value.results.containsKey(entry.name.toLowerCase()))
                entry.name.toLowerCase():
                    value.results[entry.name.toLowerCase()]!,
          }
        : <String, DirectBackupProbe>{};
    final List<ReconcileEntry> remaining = targets
        .where((entry) => !completed.containsKey(entry.name.toLowerCase()))
        .toList();
    if (remaining.isEmpty) return;
    final Stopwatch clock = Stopwatch()..start();
    if (_diagnosticsEnabled) {
      _inventoryTime = Duration.zero;
      _initialSignatureTime = Duration.zero;
      _formatCheckTime = Duration.zero;
      _packageIndexTime = Duration.zero;
      _unpackedListTime = Duration.zero;
      _byteTime = Duration.zero;
      _nativeImageTime = Duration.zero;
      _dartPixelTime = Duration.zero;
      _rawTime = Duration.zero;
      _nativeRawTime = Duration.zero;
      _otherAssetTime = Duration.zero;
      _exactEntryTime = Duration.zero;
      _wrapperTime = Duration.zero;
      _signatureTime = Duration.zero;
      _notificationTime = Duration.zero;
      _maxTimerDelayMs = 0;
      _delayedTicks = 0;
      _nativeImageCalls = 0;
      _nativeRawCalls = 0;
      _nativeExactCalls = 0;
      _nativeDeclines = 0;
      _timedPairs = 0;
      _slowestPairMs = 0;
      _slowestPairId = '';
    }
    final CancelToken token = CancelToken();
    const Duration heartbeat = Duration(milliseconds: 50);
    final Stopwatch heartbeatClock = Stopwatch()..start();
    int lastHeartbeatMs = 0;
    final Timer? monitor = _diagnosticsEnabled
        ? Timer.periodic(heartbeat, (_) {
            final int nowMs = heartbeatClock.elapsedMilliseconds;
            final int delay =
                nowMs - lastHeartbeatMs - heartbeat.inMilliseconds;
            if (delay > _maxTimerDelayMs) _maxTimerDelayMs = delay;
            if (delay > 20) _delayedTicks++;
            lastHeartbeatMs = nowMs;
          })
        : null;
    _token = token;
    value = (
      scan: scan,
      backupRoot: backupRoot,
      running: true,
      cancelled: false,
      done: completed.length,
      total: targets.length,
      results: completed,
    );
    int next = 0;
    Future<void> worker() async {
      while (!token.isCancelled && next < remaining.length) {
        final ReconcileEntry entry = remaining[next++];
        final BackupCopyDifference difference = entry.backupDifference!;
        final String workshop = path.join(
          backupWorkshopPath(backupRoot)!,
          entry.name,
        );
        final String myProjects = path.join(
          backupMyProjectsPath(backupRoot)!,
          entry.name,
        );
        final bool workshopPacked =
            difference.workshopFormat == BackupCopyFormat.packed;
        final Stopwatch pairClock = Stopwatch()..start();
        DirectBackupProbe result;
        try {
          result = await _probe(
            packedFolder: Directory(workshopPacked ? workshop : myProjects),
            unpackedFolder: Directory(workshopPacked ? myProjects : workshop),
            expectedSignature: difference.verificationSignature,
            cancelToken: token,
          );
        } catch (_) {
          result = (
            status: DirectBackupProbeStatus.unavailable,
            changes: (
              modified: <String>[],
              onlyPacked: <String>[],
              onlyUnpacked: <String>[],
            ),
            reasons: <DirectBackupProbeReason>{
              DirectBackupProbeReason.fileComparisonUnavailable,
            },
          );
        }
        if (token.isCancelled || _disposed) break;
        if (_diagnosticsEnabled &&
            pairClock.elapsedMilliseconds > _slowestPairMs) {
          _slowestPairMs = pairClock.elapsedMilliseconds;
          _slowestPairId = entry.name;
        }
        final Stopwatch? notificationWatch = _diagnosticsEnabled
            ? (Stopwatch()..start())
            : null;
        value = (
          scan: scan,
          backupRoot: backupRoot,
          running: true,
          cancelled: false,
          done: value.done + 1,
          total: targets.length,
          results: <String, DirectBackupProbe>{
            ...value.results,
            entry.name.toLowerCase(): result,
          },
        );
        if (notificationWatch != null) {
          _notificationTime += notificationWatch.elapsed;
        }
        final int checked = value.done - completed.length;
        if (_diagnosticsEnabled && checked % 20 == 0) {
          _logTiming(clock, checked, remaining.length);
        }
      }
    }

    try {
      await Future.wait(<Future<void>>[
        for (int i = 0; i < _workers && i < remaining.length; i++) worker(),
      ]);
    } finally {
      monitor?.cancel();
      if (!_disposed && identical(_token, token)) {
        final int checked = value.done - completed.length;
        if (_diagnosticsEnabled && (checked == 0 || checked % 20 != 0)) {
          _logTiming(clock, checked, remaining.length);
        }
        value = (
          scan: scan,
          backupRoot: backupRoot,
          running: false,
          cancelled: token.isCancelled,
          done: value.done,
          total: targets.length,
          results: value.results,
        );
        _token = null;
      }
    }
  }

  void cancel() {
    _token?.cancel();
    if (!_disposed && value.running) {
      value = (
        scan: value.scan,
        backupRoot: value.backupRoot,
        running: true,
        cancelled: true,
        done: value.done,
        total: value.total,
        results: value.results,
      );
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _token?.cancel();
    super.dispose();
  }
}

final Provider<BackupDirectBatch> backupDirectBatchProvider =
    Provider<BackupDirectBatch>((ref) {
      final BackupDirectBatch batch = BackupDirectBatch();
      ref.onDispose(batch.dispose);
      return batch;
    });

/// How far the running scan has got, for the tab to show while it waits.
///
/// A notifier rather than provider state because the count moves every few
/// folders; only the progress line needs those rebuilds.
@Riverpod(keepAlive: true)
ValueNotifier<BackupScanProgress?> backupScanProgress(Ref ref) {
  final ValueNotifier<BackupScanProgress?> progress =
      ValueNotifier<BackupScanProgress?>(null);
  ref.onDispose(progress.dispose);
  return progress;
}

/// The whole comparison, run when the backup tab first asks for it.
///
/// Kept alive so remounting the tab does not repeat the filesystem scan. The
/// four watched paths refresh it when configuration changes; backup mutations
/// invalidate it explicitly.
@Riverpod(keepAlive: true)
Future<BackupScan> backupScan(Ref ref) async {
  final String? backupRoot = ref.watch(backupRootProvider);
  final ValueNotifier<BackupScanProgress?> progress = ref.watch(
    backupScanProgressProvider,
  );
  final BackupScan scan;
  try {
    scan = await scanBackup(
      backupRoot: backupRoot,
      liveWorkshopPath: ref.watch(wallpaperPathProvider),
      liveMyProjectsPath: ref.watch(myProjectsLibraryProvider),
      acfPath: ref.watch(acfPathProvider),
      onProgress: (BackupScanProgress value) => progress.value = value,
    );
  } catch (_) {
    progress.value = null;
    rethrow;
  }
  return scan;
}

typedef BackupResolvedIssuesState = ({
  BackupScan? scan,
  Map<String, Set<BackupAction>> cardActions,
  Map<String, bool> ignoredCards,
  Map<String, Set<BackupReconcileReason>> resolvedReconcileReasons,
  Map<String, Set<BackupReconcileReason>> ignoredReconcileReasons,
  Map<String, Set<BackupReconcileReason>> shownReconcileReasons,
});

/// Action results applied to the current cached scan without rescanning disk.
///
/// The scan object scopes these names to one result. A later explicit scan uses
/// a new object and automatically restores whatever that scan still detects.
class BackupResolvedIssues extends Notifier<BackupResolvedIssuesState> {
  @override
  BackupResolvedIssuesState build() => (
    scan: null,
    cardActions: const <String, Set<BackupAction>>{},
    ignoredCards: const <String, bool>{},
    resolvedReconcileReasons: const <String, Set<BackupReconcileReason>>{},
    ignoredReconcileReasons: const <String, Set<BackupReconcileReason>>{},
    shownReconcileReasons: const <String, Set<BackupReconcileReason>>{},
  );

  void completeCards(
    BackupScan scan,
    BackupAction action,
    Iterable<BackupCard> cards,
  ) {
    final bool sameScan = identical(state.scan, scan);
    final Map<String, Set<BackupAction>> actions = <String, Set<BackupAction>>{
      if (sameScan)
        for (final MapEntry<String, Set<BackupAction>> entry
            in state.cardActions.entries)
          entry.key: <BackupAction>{...entry.value},
    };
    final Map<String, bool> ignored = <String, bool>{
      if (sameScan) ...state.ignoredCards,
    };
    for (final BackupCard card in cards) {
      final String id = card.id.toLowerCase();
      final Set<BackupAction> completed = actions.putIfAbsent(
        id,
        () => <BackupAction>{},
      );
      if (action == BackupAction.showUpdateAgain) {
        completed.remove(BackupAction.ignoreUpdate);
        ignored[id] = false;
      } else {
        completed.add(action);
        if (action == BackupAction.ignoreUpdate) ignored[id] = true;
      }
    }
    state = (
      scan: scan,
      cardActions: actions,
      ignoredCards: ignored,
      resolvedReconcileReasons: sameScan
          ? state.resolvedReconcileReasons
          : const <String, Set<BackupReconcileReason>>{},
      ignoredReconcileReasons: sameScan
          ? state.ignoredReconcileReasons
          : const <String, Set<BackupReconcileReason>>{},
      shownReconcileReasons: sameScan
          ? state.shownReconcileReasons
          : const <String, Set<BackupReconcileReason>>{},
    );
  }

  void resolveReconcile(
    BackupScan scan,
    String name,
    Iterable<BackupReconcileReason> reasons,
  ) => _changeReconcile(scan, name, resolved: reasons);

  void ignoreReconcile(
    BackupScan scan,
    String name,
    Iterable<BackupReconcileReason> reasons,
  ) => _changeReconcile(scan, name, ignored: reasons);

  void showReconcile(
    BackupScan scan,
    String name,
    Iterable<BackupReconcileReason> reasons,
  ) => _changeReconcile(scan, name, shown: reasons);

  void _changeReconcile(
    BackupScan scan,
    String name, {
    Iterable<BackupReconcileReason> resolved = const <BackupReconcileReason>[],
    Iterable<BackupReconcileReason> ignored = const <BackupReconcileReason>[],
    Iterable<BackupReconcileReason> shown = const <BackupReconcileReason>[],
  }) {
    final bool sameScan = identical(state.scan, scan);
    Map<String, Set<BackupReconcileReason>> copy(
      Map<String, Set<BackupReconcileReason>> source,
    ) => <String, Set<BackupReconcileReason>>{
      if (sameScan)
        for (final MapEntry<String, Set<BackupReconcileReason>> entry
            in source.entries)
          entry.key: <BackupReconcileReason>{...entry.value},
    };
    final Map<String, Set<BackupReconcileReason>> resolvedReasons = copy(
      state.resolvedReconcileReasons,
    );
    final Map<String, Set<BackupReconcileReason>> ignoredReasons = copy(
      state.ignoredReconcileReasons,
    );
    final Map<String, Set<BackupReconcileReason>> shownReasons = copy(
      state.shownReconcileReasons,
    );
    final String key = name.toLowerCase();
    resolvedReasons
        .putIfAbsent(key, () => <BackupReconcileReason>{})
        .addAll(resolved);
    ignoredReasons.putIfAbsent(key, () => <BackupReconcileReason>{})
      ..addAll(ignored)
      ..removeAll(shown);
    shownReasons.putIfAbsent(key, () => <BackupReconcileReason>{})
      ..addAll(shown)
      ..removeAll(ignored);
    state = (
      scan: scan,
      cardActions: sameScan
          ? state.cardActions
          : const <String, Set<BackupAction>>{},
      ignoredCards: sameScan ? state.ignoredCards : const <String, bool>{},
      resolvedReconcileReasons: resolvedReasons,
      ignoredReconcileReasons: ignoredReasons,
      shownReconcileReasons: shownReasons,
    );
  }
}

final NotifierProvider<BackupResolvedIssues, BackupResolvedIssuesState>
backupResolvedIssuesProvider =
    NotifierProvider<BackupResolvedIssues, BackupResolvedIssuesState>(
      BackupResolvedIssues.new,
    );

List<ReconcileEntry> visibleBackupReconcileEntries(
  BackupScan scan,
  BackupResolvedIssuesState resolved,
) {
  if (!identical(resolved.scan, scan)) {
    return scan.reconcile;
  }
  final List<ReconcileEntry> entries = <ReconcileEntry>[];
  for (final ReconcileEntry entry in scan.reconcile) {
    final String key = entry.name.toLowerCase();
    final Set<BackupReconcileReason> reasons = entry.reasons.difference(
      resolved.resolvedReconcileReasons[key] ?? const <BackupReconcileReason>{},
    );
    if (reasons.isEmpty) continue;
    final Set<BackupReconcileReason> ignored =
        <BackupReconcileReason>{
            ...entry.ignoredReasons,
            ...?resolved.ignoredReconcileReasons[key],
          }
          ..removeAll(
            resolved.shownReconcileReasons[key] ??
                const <BackupReconcileReason>{},
          )
          ..retainAll(reasons);
    final BackupReconcileReason primary = reasons.contains(entry.reason)
        ? entry.reason
        : reasons.first;
    entries.add(
      ReconcileEntry(
        name: entry.name,
        reason: primary,
        additionalReasons: reasons.difference(<BackupReconcileReason>{primary}),
        ignoredReasons: ignored,
        issueFingerprints: entry.issueFingerprints,
        states: entry.states,
        backupWorkshop: entry.backupWorkshop,
        backupMyProjects: entry.backupMyProjects,
        backupDifference: entry.backupDifference,
      ),
    );
  }
  return entries;
}

Set<BackupAction> _completedCardActions(
  BackupScan scan,
  BackupResolvedIssuesState resolved,
  BackupCard card,
) => identical(resolved.scan, scan)
    ? resolved.cardActions[card.id.toLowerCase()] ?? const <BackupAction>{}
    : const <BackupAction>{};

BackupUpdatePlan? visibleBackupUpdatePlan(
  BackupScan scan,
  BackupResolvedIssuesState resolved,
  BackupCard card,
) {
  final BackupState? original = scan.cards[card];
  final bool wasUpdate =
      original == BackupState.updateAvailable ||
      scan.ignoredUpdates.contains(card);
  if (!wasUpdate) return null;
  final BackupUpdatePlan plan =
      scan.updates[card] ?? const BackupUpdatePlan(updateContent: true);
  final Set<BackupAction> completed = _completedCardActions(
    scan,
    resolved,
    card,
  );
  final bool updateContent =
      plan.updateContent &&
      !backupCardIsIgnored(scan, resolved, card) &&
      !completed.contains(BackupAction.update) &&
      !completed.contains(BackupAction.ignoreUpdate);
  final BackupSyncPlan? sync =
      plan.needsSync && !completed.contains(BackupAction.sync)
      ? plan.sync
      : null;
  return updateContent || sync != null
      ? BackupUpdatePlan(updateContent: updateContent, sync: sync)
      : null;
}

bool backupCardIsIgnored(
  BackupScan scan,
  BackupResolvedIssuesState resolved,
  BackupCard card,
) {
  final bool? override = identical(resolved.scan, scan)
      ? resolved.ignoredCards[card.id.toLowerCase()]
      : null;
  if (override != null) {
    return override;
  }
  return scan.ignoredUpdates.contains(card);
}

BackupState? visibleBackupCardState(
  BackupScan scan,
  BackupResolvedIssuesState resolved,
  BackupCard card,
  BackupState original,
) {
  if (original == BackupState.updateAvailable ||
      original == BackupState.updateDismissed) {
    return visibleBackupUpdatePlan(scan, resolved, card) == null
        ? null
        : BackupState.updateAvailable;
  }
  final BackupAction? action = actionForBackupState(original);
  return action != null &&
          _completedCardActions(scan, resolved, card).contains(action)
      ? null
      : original;
}

Map<BackupCard, BackupState> visibleBackupCardStates(
  BackupScan scan,
  BackupResolvedIssuesState resolved,
) {
  final Map<BackupCard, BackupState> states = <BackupCard, BackupState>{};
  for (final MapEntry<BackupCard, BackupState> entry in scan.cards.entries) {
    final BackupState? visible = visibleBackupCardState(
      scan,
      resolved,
      entry.key,
      entry.value,
    );
    if (visible != null) states[entry.key] = visible;
  }
  for (final BackupCard card in scan.ignoredUpdates) {
    if (states.containsKey(card) || backupCardIsIgnored(scan, resolved, card)) {
      continue;
    }
    if (visibleBackupUpdatePlan(scan, resolved, card) != null) {
      states[card] = BackupState.updateAvailable;
    }
  }
  return states;
}

Set<BackupCard> visibleBackupIgnoredUpdates(
  BackupScan scan,
  BackupResolvedIssuesState resolved,
) => <BackupCard>{
  for (final BackupCard card in <BackupCard>{
    ...scan.cards.keys,
    ...scan.ignoredUpdates,
  })
    if (backupCardIsIgnored(scan, resolved, card) &&
        (scan.updates[card]?.updateContent ?? true) &&
        !_completedCardActions(
          scan,
          resolved,
          card,
        ).contains(BackupAction.update))
      card,
};

/// The scan's cards in grid order, each with the title and preview to draw.
///
/// Kept apart from the scan so face reads cannot delay the counts, and so an
/// unreadable `project.json` costs a picture rather than a card.
@Riverpod(keepAlive: true)
Future<List<BackupTile>> backupTiles(Ref ref) async {
  final BackupScan scan = await ref.watch(backupScanProvider.future);
  // An ignored content update can belong to a wallpaper that Reconcile owns.
  // Read its face too so Ignored never loses a detection to pill precedence.
  final Map<BackupCard, BackupState> faceCards = <BackupCard, BackupState>{
    ...scan.cards,
    for (final BackupCard card in scan.ignoredUpdates)
      if (!scan.cards.containsKey(card)) card: BackupState.updateDismissed,
  };
  // Keep the scan's final preparing state while the short title/preview read
  // finishes, so the tab has one continuous loading phase instead of a second
  // progress bar.
  final ValueNotifier<BackupScanProgress?> progress = ref.watch(
    backupScanProgressProvider,
  );
  final Map<BackupCard, CardFace> faces;
  try {
    faces = await readCardFaces(
      backupRoot: ref.watch(backupRootProvider),
      liveWorkshopPath: ref.watch(wallpaperPathProvider),
      liveMyProjectsPath: ref.watch(myProjectsLibraryProvider),
      cards: faceCards,
      presence: scan.presence,
    );
  } catch (_) {
    // A read that threw must not leave its last count sitting on the line for
    // the next thing that waits to inherit.
    progress.value = null;
    rethrow;
  }
  // Keep the final preparing state until the completed tiles replace the
  // progress view. Clearing it here can win the frame and hide that state.
  final List<BackupTile> tiles = <BackupTile>[
    for (final BackupCard card in sortedCards(faceCards))
      (card: card, state: faceCards[card]!, face: faces[card]),
  ];
  return tiles;
}

/// The names waiting to be reconciled, each with the title and preview to draw.
///
/// Apart from [backupTiles] because Reconcile has its own names and only renders
/// behind its own pill.
@Riverpod(keepAlive: true)
Future<List<ReconcileTile>> backupReconcileTiles(Ref ref) async {
  final BackupScan scan = await ref.watch(backupScanProvider.future);
  final Map<String, CardFace> faces = await readReconcileFaces(
    backupRoot: ref.watch(backupRootProvider),
    liveWorkshopPath: ref.watch(wallpaperPathProvider),
    liveMyProjectsPath: ref.watch(myProjectsLibraryProvider),
    entries: scan.reconcile,
  );
  return <ReconcileTile>[
    for (final ReconcileEntry entry in scan.reconcile)
      (entry: entry, face: faces[entry.name]),
  ];
}

/// What is typed in the backup tab's search box.
///
/// Its own, not the wallpaper tab's. That grid shows one library at a time and
/// this one shows both plus what has vanished, so a term left behind on one tab
/// would quietly empty the other.
@Riverpod(keepAlive: true)
class BackupSearch extends _$BackupSearch {
  @override
  String build() => '';

  void update(String text) => state = text;
}

/// Which top-level Backup pill owns the grid right now.
typedef BackupShown = ({BackupState state, bool reconcile, bool ignored});

/// Session state rather than a setting: the pills are how the tab is being
/// looked at now, and returning to a grid narrowed by a pill switched off days
/// ago is how a wallpaper goes missing quietly.
///
/// Opens on the worst state that holds something, which on a library with work
/// waiting is the one with an obvious next step. Every other pill holding
/// anything glows for itself, so nothing is hidden by starting narrow.
@Riverpod(keepAlive: true)
class BackupStateFilter extends _$BackupStateFilter {
  static const BackupShown _opening = (
    state: BackupState.notBackedUp,
    reconcile: false,
    ignored: false,
  );
  BackupShown _shown = _opening;

  @override
  BackupShown build() {
    // Returning the scan-adjusted selection lets Riverpod publish it after the
    // dependency rebuild. A listener that assigned state here could fire while
    // Flutter was building the Backup toolbar.
    final BackupResolvedIssuesState resolved = ref.watch(
      backupResolvedIssuesProvider,
    );
    _shown = switch (ref.watch(backupScanProvider)) {
      AsyncData<BackupScan>(:final BackupScan value) => _holding(
        _shown,
        visibleBackupCardStates(value, resolved),
        visibleBackupIgnoredUpdates(value, resolved),
        visibleBackupReconcileEntries(value, resolved),
      ),
      _ => _shown,
    };
    return _shown;
  }

  /// Keeps a non-empty pill selected, falling back in priority order.
  static BackupShown _holding(
    BackupShown shown,
    Map<BackupCard, BackupState> states,
    Set<BackupCard> ignoredUpdates,
    List<ReconcileEntry> reconcile,
  ) {
    final totals = backupPillCounts(
      states: states.values,
      ignoredUpdates: ignoredUpdates,
      reconcile: reconcile,
    );
    final int activeReconcile = totals.reconcile;
    final int ignored = totals.ignored;
    if (shown.reconcile && activeReconcile > 0) return shown;
    if (shown.ignored && ignored > 0) return shown;
    final Map<BackupState, int> counts = totals.states;
    if (!shown.reconcile &&
        !shown.ignored &&
        shown.state != BackupState.updateDismissed &&
        counts[shown.state]! > 0) {
      return shown;
    }
    for (final BackupState state in backupStateOrder) {
      if (state == BackupState.updateDismissed || state == BackupState.synced) {
        continue;
      }
      if (counts[state]! > 0) {
        return (state: state, reconcile: false, ignored: false);
      }
    }
    if (activeReconcile > 0) {
      return (state: shown.state, reconcile: true, ignored: false);
    }
    if (counts[BackupState.synced]! > 0) {
      return (state: BackupState.synced, reconcile: false, ignored: false);
    }
    if (ignored > 0) {
      return (state: shown.state, reconcile: false, ignored: true);
    }
    return _opening;
  }

  /// One at a time, the way tabs behave: the grid shows the state picked and
  /// nothing else, and is never left showing everything or nothing.
  void show(BackupState state) {
    _shown = (state: state, reconcile: false, ignored: false);
    this.state = _shown;
  }

  /// Swaps the grid over. The state pills are left as they were because picking
  /// one is what takes the grid back.
  void showReconcile() {
    _shown = (state: state.state, reconcile: true, ignored: false);
    state = _shown;
  }

  void showIgnored() {
    _shown = (state: state.state, reconcile: false, ignored: true);
    state = _shown;
  }
}

@Riverpod(keepAlive: true)
class BackupSortOrder extends _$BackupSortOrder {
  @override
  BackupSortType build() => StorageUtil.getInt(AppKeys.backupSortType) == 2
      ? BackupSortType.date
      : BackupSortType.name;

  void update(BackupSortType type) async {
    state = type;
    // Preserve persisted values 1 = name and 2 = date for compatibility; any
    // other stored value falls back to name when read above.
    await StorageUtil.setInt(
      AppKeys.backupSortType,
      type == BackupSortType.date ? 2 : 1,
    );
  }
}

@Riverpod(keepAlive: true)
class BackupSortAscending extends _$BackupSortAscending {
  @override
  bool build() => StorageUtil.getBool(AppKeys.backupSortAscending);

  void update() async {
    state = !state;
    await StorageUtil.setBool(AppKeys.backupSortAscending, state);
  }
}

/// The cards the grid draws. Apart from [backupTiles] so typing only re-filters
/// the in-memory list instead of repeating face reads.
@Riverpod(keepAlive: true)
AsyncValue<List<BackupTile>> backupVisibleTiles(Ref ref) {
  return ref.watch(backupTilesProvider).whenData((List<BackupTile> tiles) {
    final BackupShown shown = ref.watch(backupStateFilterProvider);
    final BackupScan scan = ref.watch(backupScanProvider).requireValue;
    final BackupResolvedIssuesState resolved = ref.watch(
      backupResolvedIssuesProvider,
    );
    if (shown.ignored) {
      final Set<String> ignoredIds = <String>{
        for (final BackupCard card in visibleBackupIgnoredUpdates(
          scan,
          resolved,
        ))
          card.id,
      };
      return visibleBackupTilesMatching(
        tiles: <BackupTile>[
          for (final BackupTile tile in tiles)
            if (ignoredIds.contains(tile.card.id))
              (
                card: tile.card,
                state: BackupState.updateDismissed,
                face: tile.face,
              ),
        ],
        include: (BackupTile _) => true,
        needle: ref.watch(backupSearchProvider).trim().toLowerCase(),
        filter: ref.watch(filterStateProvider),
        sort: ref.watch(backupSortOrderProvider),
        ascending: ref.watch(backupSortAscendingProvider),
      );
    }
    return visibleBackupTiles(
      tiles: <BackupTile>[
        for (final BackupTile tile in tiles)
          if (visibleBackupCardState(scan, resolved, tile.card, tile.state)
              case final BackupState state)
            (card: tile.card, state: state, face: tile.face),
      ],
      state: shown.state,
      needle: ref.watch(backupSearchProvider).trim().toLowerCase(),
      filter: ref.watch(filterStateProvider),
      sort: ref.watch(backupSortOrderProvider),
      ascending: ref.watch(backupSortAscendingProvider),
    );
  });
}

/// The reconcile tiles the grid draws, under the same search, filter and order.
@Riverpod(keepAlive: true)
AsyncValue<List<ReconcileTile>> backupVisibleReconcileTiles(Ref ref) {
  return ref.watch(backupReconcileTilesProvider).whenData((
    List<ReconcileTile> tiles,
  ) {
    final BackupShown shown = ref.watch(backupStateFilterProvider);
    final BackupScan scan = ref.watch(backupScanProvider).requireValue;
    final Map<String, ReconcileEntry> visibleEntries = <String, ReconcileEntry>{
      for (final ReconcileEntry entry in visibleBackupReconcileEntries(
        scan,
        ref.watch(backupResolvedIssuesProvider),
      ))
        entry.name.toLowerCase(): entry,
    };
    return visibleReconcileTiles(
      tiles: <ReconcileTile>[
        for (final ReconcileTile tile in tiles)
          if (visibleEntries[tile.entry.name.toLowerCase()]
              case final ReconcileEntry entry)
            if ((shown.ignored
                ? entry.ignoredReasons.isNotEmpty
                : entry.activeReasons.isNotEmpty))
              (entry: entry, face: tile.face),
      ],
      needle: ref.watch(backupSearchProvider).trim().toLowerCase(),
      filter: ref.watch(filterStateProvider),
      sort: ref.watch(backupSortOrderProvider),
      ascending: ref.watch(backupSortAscendingProvider),
    );
  });
}

/// Ids of whatever the grid is drawing, which is what the selection is pruned
/// against: a tile out of view is out of the selection.
@Riverpod(keepAlive: true)
AsyncValue<Set<String>> backupVisibleIds(Ref ref) {
  final BackupShown shown = ref.watch(backupStateFilterProvider);
  if (shown.ignored) {
    final AsyncValue<List<BackupTile>> updates = ref.watch(
      backupVisibleTilesProvider,
    );
    final AsyncValue<List<ReconcileTile>> reconcile = ref.watch(
      backupVisibleReconcileTilesProvider,
    );
    return switch ((updates, reconcile)) {
      (
        AsyncData<List<BackupTile>>(value: final List<BackupTile> updateTiles),
        AsyncData<List<ReconcileTile>>(
          value: final List<ReconcileTile> reconcileTiles,
        ),
      ) =>
        AsyncData<Set<String>>(<String>{
          for (final BackupTile tile in updateTiles) tile.card.id,
          for (final ReconcileTile tile in reconcileTiles)
            for (final BackupReconcileReason reason
                in tile.entry.ignoredReasons)
              ignoredReconcileTileId(tile.entry.name, reason),
        }),
      (
        AsyncError<List<BackupTile>>(
          :final Object error,
          :final StackTrace stackTrace,
        ),
        _,
      ) =>
        AsyncError<Set<String>>(error, stackTrace),
      (
        _,
        AsyncError<List<ReconcileTile>>(
          :final Object error,
          :final StackTrace stackTrace,
        ),
      ) =>
        AsyncError<Set<String>>(error, stackTrace),
      _ => const AsyncLoading<Set<String>>(),
    };
  }
  if (shown.reconcile) {
    return ref
        .watch(backupVisibleReconcileTilesProvider)
        .whenData(
          (List<ReconcileTile> tiles) => <String>{
            for (final ReconcileTile tile in tiles)
              reconcileTileId(tile.entry.name),
          },
        );
  }
  return ref
      .watch(backupVisibleTilesProvider)
      .whenData(
        (List<BackupTile> tiles) => <String>{
          for (final BackupTile tile in tiles) tile.card.id,
        },
      );
}

/// Which backup cards are selected, by [BackupCard.id].
///
/// Its own selection rather than the extract tab's: the two grids show
/// different things, and a wallpaper live in both libraries is two cards here
/// and one there.
@Riverpod(keepAlive: true)
class BackupSelection extends _$BackupSelection {
  @override
  Set<String> build() {
    // Here rather than in the grid: the whole chain is kept alive, so filtering
    // from the other tab or changing a path in settings moves what is on screen
    // while the backup tab is not even mounted.
    ref.listen(backupVisibleIdsProvider, (
      AsyncValue<Set<String>>? previous,
      AsyncValue<Set<String>> next,
    ) {
      if (next case AsyncData<Set<String>>(:final Set<String> value)) {
        _queueRetain(value);
      }
    });
    ref.onDispose(() {
      _pendingVisibleIds = null;
      _retainScheduled = false;
    });
    return const <String>{};
  }

  Set<String>? _pendingVisibleIds;
  bool _retainScheduled = false;

  void _queueRetain(Set<String> ids) {
    _pendingVisibleIds = ids;
    if (_retainScheduled) return;
    _retainScheduled = true;
    // The visible-list provider can rebuild while Flutter is building a tile.
    // Prune selection in a microtask instead of mutating it mid-build.
    Future<void>.microtask(() {
      _retainScheduled = false;
      final Set<String>? visible = _pendingVisibleIds;
      _pendingVisibleIds = null;
      if (visible != null) retain(visible);
    });
  }

  /// Which tile a shift range reaches back to. The id, not the position:
  /// re-ordering the grid moves every tile without dropping any.
  String? shiftAnchor;

  void setExactly(Set<String> ids) {
    // Nothing to reach back to from an empty selection, so a shift click after
    // one does not pick up a range from the tile last clicked.
    if (ids.isEmpty) shiftAnchor = null;
    if (setEquals(ids, state)) return;
    state = ids.toSet();
  }

  void toggle(String id) {
    shiftAnchor = id;
    state = state.contains(id)
        ? (state.toSet()..remove(id))
        : (state.toSet()..add(id));
  }

  /// What a plain left click does, matching the extract tab: selects only [id],
  /// and clears it when it was already the only one selected.
  void setExclusive(String id) {
    state = state.length == 1 && state.contains(id)
        ? const <String>{}
        : <String>{id};
    // Nothing to reach back to from an empty selection.
    shiftAnchor = state.isEmpty ? null : id;
  }

  /// Drops ids the grid is not drawing: a selected tile nobody can see can be
  /// neither cleared nor spared by the operations still to come.
  void retain(Set<String> ids) {
    if (shiftAnchor != null && !ids.contains(shiftAnchor)) shiftAnchor = null;
    final Set<String> kept = state.where(ids.contains).toSet();
    if (kept.length != state.length) state = kept;
  }
}
