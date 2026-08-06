// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'navigation.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Which area the window is showing. Not persisted: a launch should land on the
/// wallpaper grid, not wherever the last session closed.

@ProviderFor(CurrentSection)
final currentSectionProvider = CurrentSectionProvider._();

/// Which area the window is showing. Not persisted: a launch should land on the
/// wallpaper grid, not wherever the last session closed.
final class CurrentSectionProvider
    extends $NotifierProvider<CurrentSection, NavSection> {
  /// Which area the window is showing. Not persisted: a launch should land on the
  /// wallpaper grid, not wherever the last session closed.
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

/// Which area the window is showing. Not persisted: a launch should land on the
/// wallpaper grid, not wherever the last session closed.

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

/// Which tab the backup area is showing. Not persisted, for the same reason as
/// [CurrentSection].

@ProviderFor(CurrentBackupTab)
final currentBackupTabProvider = CurrentBackupTabProvider._();

/// Which tab the backup area is showing. Not persisted, for the same reason as
/// [CurrentSection].
final class CurrentBackupTabProvider
    extends $NotifierProvider<CurrentBackupTab, BackupTab> {
  /// Which tab the backup area is showing. Not persisted, for the same reason as
  /// [CurrentSection].
  CurrentBackupTabProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'currentBackupTabProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$currentBackupTabHash();

  @$internal
  @override
  CurrentBackupTab create() => CurrentBackupTab();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(BackupTab value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<BackupTab>(value),
    );
  }
}

String _$currentBackupTabHash() => r'ab1b936667836773e89c299b6e3c506aa6fef061';

/// Which tab the backup area is showing. Not persisted, for the same reason as
/// [CurrentSection].

abstract class _$CurrentBackupTab extends $Notifier<BackupTab> {
  BackupTab build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<BackupTab, BackupTab>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<BackupTab, BackupTab>,
              BackupTab,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
