import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:we_repkg/constants/i10n.dart';
import 'package:we_repkg/utils/backup_diff.dart';

/// Backup records are stored in the backup root.
const String backupRecordsName = 'werepkg-ex-backup.json';
const String backupVerificationCacheName =
    'werepkg-ex-backup-verification.json';

/// Temporary file used before replacing the saved records.
const String backupRecordsPartSuffix = '.werepkg-ex-part';

const JsonEncoder _records = JsonEncoder.withIndent('  ');

/// Reads completed semantic backup comparisons. Invalid cache data is ignored;
/// it never changes the authoritative backup records.
Future<Map<String, BackupCopyVerification>> readBackupVerificationCache(
  String? backupRoot,
) async {
  if (backupRoot == null) return <String, BackupCopyVerification>{};
  final File file = File(path.join(backupRoot, backupVerificationCacheName));
  if (!await file.exists()) return <String, BackupCopyVerification>{};
  try {
    final Map<String, dynamic> document =
        jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    if (document['version'] != 1 || document['entries'] is! Map) {
      return <String, BackupCopyVerification>{};
    }
    final Map<String, dynamic> entries = Map<String, dynamic>.from(
      document['entries'] as Map,
    );
    return <String, BackupCopyVerification>{
      for (final MapEntry<String, dynamic> entry in entries.entries)
        if (entry.value is Map<String, dynamic>)
          if (_decodeVerification(entry.value as Map<String, dynamic>)
              case final BackupCopyVerification result)
            entry.key.toLowerCase(): result,
    };
  } catch (_) {
    return <String, BackupCopyVerification>{};
  }
}

BackupCopyVerification? _decodeVerification(Map<String, dynamic> json) {
  final String? signature = json['signature'] as String?;
  BackupCopyVerificationStatus? status;
  for (final BackupCopyVerificationStatus value
      in BackupCopyVerificationStatus.values) {
    if (value.name == json['status']) status = value;
  }
  if (signature == null ||
      status == null ||
      status == BackupCopyVerificationStatus.unavailable) {
    return null;
  }
  List<String> paths(String key) => (json[key] as List<dynamic>? ?? const [])
      .whereType<String>()
      .toList(growable: false);
  return BackupCopyVerification(
    status: status,
    signature: signature,
    changes: (
      modified: paths('modified'),
      onlyPacked: paths('onlyPacked'),
      onlyUnpacked: paths('onlyUnpacked'),
    ),
  );
}

Future<void> writeBackupVerificationCache(
  String? backupRoot,
  Map<String, BackupCopyVerification> values,
) async {
  if (backupRoot == null) return;
  final List<String> names = values.keys.toList()..sort();
  final Map<String, dynamic> document = <String, dynamic>{
    'version': 1,
    'entries': <String, dynamic>{
      for (final String name in names)
        if (values[name] case final BackupCopyVerification value)
          if (value.status != BackupCopyVerificationStatus.unavailable)
            name: <String, dynamic>{
              'signature': value.signature,
              'status': value.status.name,
              'modified': value.changes.modified,
              'onlyPacked': value.changes.onlyPacked,
              'onlyUnpacked': value.changes.onlyUnpacked,
            },
    },
  };
  final File file = File(path.join(backupRoot, backupVerificationCacheName));
  final File part = File('${file.path}$backupRecordsPartSuffix');
  await part.writeAsString(_records.convert(document), flush: true);
  await part.rename(file.path);
}

/// Reads saved backup versions and ignored issues.
/// Missing or invalid records return an empty map.
Future<Map<String, BackupRecord>> readBackupRecords(String? backupRoot) async {
  if (backupRoot == null) return <String, BackupRecord>{};
  final File file = File(path.join(backupRoot, backupRecordsName));
  if (!await file.exists()) return <String, BackupRecord>{};
  try {
    final Map<String, dynamic> parsed =
        json.decode(await file.readAsString()) as Map<String, dynamic>;
    return <String, BackupRecord>{
      for (final MapEntry<String, dynamic> entry in parsed.entries)
        if (entry.value is Map<String, dynamic>)
          entry.key: BackupRecord(
            backedUpVersion: entry.value['backedUpVersion'] as String?,
            dismissedVersion: entry.value['dismissedVersion'] as String?,
            ignoredReconcileIssues:
                entry.value['ignoredReconcileIssues'] is Map<String, dynamic>
                ? <BackupReconcileReason, String>{
                    for (final MapEntry<String, dynamic> issue
                        in (entry.value['ignoredReconcileIssues']
                                as Map<String, dynamic>)
                            .entries)
                      for (final BackupReconcileReason reason
                          in BackupReconcileReason.values)
                        if (reason.name == issue.key && issue.value is String)
                          reason: issue.value as String,
                  }
                : const <BackupReconcileReason, String>{},
          ),
    };
  } catch (e) {
    debugPrint('${tr(AppI10n.errorReadBackupRecordsFailed)} $e');
    return <String, BackupRecord>{};
  }
}

Future<void> writeBackupRecords(
  String? backupRoot,
  Map<String, BackupRecord> records,
) async {
  if (backupRoot == null) return;
  final Map<String, Map<String, dynamic>> encoded =
      <String, Map<String, dynamic>>{};
  // Keep saved entries in a consistent order.
  final List<String> ids = records.keys.toList()..sort();
  for (final String id in ids) {
    final BackupRecord record = records[id]!;
    final Map<String, dynamic> fields = <String, dynamic>{
      if (record.backedUpVersion != null)
        'backedUpVersion': record.backedUpVersion!,
      if (record.dismissedVersion != null)
        'dismissedVersion': record.dismissedVersion!,
      if (record.ignoredReconcileIssues.isNotEmpty)
        'ignoredReconcileIssues': <String, String>{
          for (final MapEntry<BackupReconcileReason, String> issue
              in (record.ignoredReconcileIssues.entries.toList()..sort(
                (
                  MapEntry<BackupReconcileReason, String> a,
                  MapEntry<BackupReconcileReason, String> b,
                ) => a.key.index.compareTo(b.key.index),
              )))
            issue.key.name: issue.value,
        },
    };
    if (fields.isNotEmpty) encoded[id] = fields;
  }
  // Finish writing before replacing the existing records to avoid a partial JSON file.
  final File file = File(path.join(backupRoot, backupRecordsName));
  final File part = File('${file.path}$backupRecordsPartSuffix');
  await part.writeAsString(_records.convert(encoded), flush: true);
  await part.rename(file.path);
}
