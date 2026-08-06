// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'backup.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The whole comparison, run when the backup tab first asks for it.
///
/// Kept alive because leaving the tab unmounts the view and rescanning both
/// libraries is seconds of disk work. Watching the four paths is what refreshes
/// it when one of them changes; anything that writes to the backup invalidates
/// it by hand.

@ProviderFor(backupScan)
final backupScanProvider = BackupScanProvider._();

/// The whole comparison, run when the backup tab first asks for it.
///
/// Kept alive because leaving the tab unmounts the view and rescanning both
/// libraries is seconds of disk work. Watching the four paths is what refreshes
/// it when one of them changes; anything that writes to the backup invalidates
/// it by hand.

final class BackupScanProvider
    extends
        $FunctionalProvider<
          AsyncValue<BackupScan>,
          BackupScan,
          FutureOr<BackupScan>
        >
    with $FutureModifier<BackupScan>, $FutureProvider<BackupScan> {
  /// The whole comparison, run when the backup tab first asks for it.
  ///
  /// Kept alive because leaving the tab unmounts the view and rescanning both
  /// libraries is seconds of disk work. Watching the four paths is what refreshes
  /// it when one of them changes; anything that writes to the backup invalidates
  /// it by hand.
  BackupScanProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'backupScanProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$backupScanHash();

  @$internal
  @override
  $FutureProviderElement<BackupScan> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<BackupScan> create(Ref ref) {
    return backupScan(ref);
  }
}

String _$backupScanHash() => r'68d1bf8a8ee579304a8974b914bf346a0abe6061';
