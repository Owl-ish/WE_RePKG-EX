// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'integrity.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The integrity check over all four roots.
///
/// Kept alive so switching tabs does not re-walk 7000 folders, and watched
/// rather than read once so repointing a library re-checks it.

@ProviderFor(integrityScan)
final integrityScanProvider = IntegrityScanProvider._();

/// The integrity check over all four roots.
///
/// Kept alive so switching tabs does not re-walk 7000 folders, and watched
/// rather than read once so repointing a library re-checks it.

final class IntegrityScanProvider
    extends
        $FunctionalProvider<
          AsyncValue<IntegrityReport>,
          IntegrityReport,
          FutureOr<IntegrityReport>
        >
    with $FutureModifier<IntegrityReport>, $FutureProvider<IntegrityReport> {
  /// The integrity check over all four roots.
  ///
  /// Kept alive so switching tabs does not re-walk 7000 folders, and watched
  /// rather than read once so repointing a library re-checks it.
  IntegrityScanProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'integrityScanProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$integrityScanHash();

  @$internal
  @override
  $FutureProviderElement<IntegrityReport> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<IntegrityReport> create(Ref ref) {
    return integrityScan(ref);
  }
}

String _$integrityScanHash() => r'debb7fe4553f5054d38ba876201e0d9c9ea326d1';

/// Which concern the list is showing, or null for the worst one the check
/// found.

@ProviderFor(IntegrityShown)
final integrityShownProvider = IntegrityShownProvider._();

/// Which concern the list is showing, or null for the worst one the check
/// found.
final class IntegrityShownProvider
    extends $NotifierProvider<IntegrityShown, IntegrityVerdict?> {
  /// Which concern the list is showing, or null for the worst one the check
  /// found.
  IntegrityShownProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'integrityShownProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$integrityShownHash();

  @$internal
  @override
  IntegrityShown create() => IntegrityShown();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(IntegrityVerdict? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<IntegrityVerdict?>(value),
    );
  }
}

String _$integrityShownHash() => r'792a98fbc3cd40e07905493aa2c50f690624cd68';

/// Which concern the list is showing, or null for the worst one the check
/// found.

abstract class _$IntegrityShown extends $Notifier<IntegrityVerdict?> {
  IntegrityVerdict? build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<IntegrityVerdict?, IntegrityVerdict?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<IntegrityVerdict?, IntegrityVerdict?>,
              IntegrityVerdict?,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

/// Repairs completed during this app run. Nothing is persisted to disk.

@ProviderFor(IntegrityResolved)
final integrityResolvedProvider = IntegrityResolvedProvider._();

/// Repairs completed during this app run. Nothing is persisted to disk.
final class IntegrityResolvedProvider
    extends $NotifierProvider<IntegrityResolved, IntegrityResolvedState> {
  /// Repairs completed during this app run. Nothing is persisted to disk.
  IntegrityResolvedProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'integrityResolvedProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$integrityResolvedHash();

  @$internal
  @override
  IntegrityResolved create() => IntegrityResolved();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(IntegrityResolvedState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<IntegrityResolvedState>(value),
    );
  }
}

String _$integrityResolvedHash() => r'be5b1843716b6c499ecc324a70128a8539ab5f7b';

/// Repairs completed during this app run. Nothing is persisted to disk.

abstract class _$IntegrityResolved extends $Notifier<IntegrityResolvedState> {
  IntegrityResolvedState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref =
        this.ref as $Ref<IntegrityResolvedState, IntegrityResolvedState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<IntegrityResolvedState, IntegrityResolvedState>,
              IntegrityResolvedState,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
