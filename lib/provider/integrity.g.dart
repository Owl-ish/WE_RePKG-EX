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
