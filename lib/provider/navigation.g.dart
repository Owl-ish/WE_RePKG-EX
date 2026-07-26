// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'navigation.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Which top level area the window is showing.
///
/// Deliberately not persisted: a launch should land on the wallpaper grid,
/// which is what the app is for, rather than reopening on whatever page the
/// last session happened to close on.

@ProviderFor(CurrentSection)
final currentSectionProvider = CurrentSectionProvider._();

/// Which top level area the window is showing.
///
/// Deliberately not persisted: a launch should land on the wallpaper grid,
/// which is what the app is for, rather than reopening on whatever page the
/// last session happened to close on.
final class CurrentSectionProvider
    extends $NotifierProvider<CurrentSection, NavSection> {
  /// Which top level area the window is showing.
  ///
  /// Deliberately not persisted: a launch should land on the wallpaper grid,
  /// which is what the app is for, rather than reopening on whatever page the
  /// last session happened to close on.
  CurrentSectionProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'currentSectionProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$currentSectionHash();

  @$internal
  @override
  CurrentSection create() => CurrentSection();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(NavSection value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<NavSection>(value),
    );
  }
}

String _$currentSectionHash() => r'5f03bc1287e204b092079d5607dd50545838806c';

/// Which top level area the window is showing.
///
/// Deliberately not persisted: a launch should land on the wallpaper grid,
/// which is what the app is for, rather than reopening on whatever page the
/// last session happened to close on.

abstract class _$CurrentSection extends $Notifier<NavSection> {
  NavSection build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<NavSection, NavSection>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<NavSection, NavSection>,
              NavSection,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
