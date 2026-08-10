// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'backup.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// How far the running scan has got, for the tab to show while it waits.
///
/// A notifier rather than provider state: the count moves every few folders,
/// and rebuilding the tab that often to redraw one line of text would be worse
/// than the silence it replaces. Only the line itself listens.

@ProviderFor(backupScanProgress)
final backupScanProgressProvider = BackupScanProgressProvider._();

/// How far the running scan has got, for the tab to show while it waits.
///
/// A notifier rather than provider state: the count moves every few folders,
/// and rebuilding the tab that often to redraw one line of text would be worse
/// than the silence it replaces. Only the line itself listens.

final class BackupScanProgressProvider
    extends
        $FunctionalProvider<
          ValueNotifier<BackupScanProgress?>,
          ValueNotifier<BackupScanProgress?>,
          ValueNotifier<BackupScanProgress?>
        >
    with $Provider<ValueNotifier<BackupScanProgress?>> {
  /// How far the running scan has got, for the tab to show while it waits.
  ///
  /// A notifier rather than provider state: the count moves every few folders,
  /// and rebuilding the tab that often to redraw one line of text would be worse
  /// than the silence it replaces. Only the line itself listens.
  BackupScanProgressProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'backupScanProgressProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$backupScanProgressHash();

  @$internal
  @override
  $ProviderElement<ValueNotifier<BackupScanProgress?>> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  ValueNotifier<BackupScanProgress?> create(Ref ref) {
    return backupScanProgress(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ValueNotifier<BackupScanProgress?> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ValueNotifier<BackupScanProgress?>>(
        value,
      ),
    );
  }
}

String _$backupScanProgressHash() =>
    r'64643d428dad532280658c2c9550068e75642873';

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

String _$backupScanHash() => r'c9a83caea59bdfe53e3da3f5d2da83f54f282fcf';
