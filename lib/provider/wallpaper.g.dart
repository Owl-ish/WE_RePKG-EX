// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'wallpaper.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(WallpaperList)
final wallpaperListProvider = WallpaperListProvider._();

final class WallpaperListProvider
    extends $NotifierProvider<WallpaperList, List<WallpaperInfo>> {
  WallpaperListProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'wallpaperListProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$wallpaperListHash();

  @$internal
  @override
  WallpaperList create() => WallpaperList();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<WallpaperInfo> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<WallpaperInfo>>(value),
    );
  }
}

String _$wallpaperListHash() => r'55c0e42d8ef1632c96e2eb95e0b1db044f59e22b';

abstract class _$WallpaperList extends $Notifier<List<WallpaperInfo>> {
  List<WallpaperInfo> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<List<WallpaperInfo>, List<WallpaperInfo>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<List<WallpaperInfo>, List<WallpaperInfo>>,
              List<WallpaperInfo>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

@ProviderFor(SelectedWallpaper)
final selectedWallpaperProvider = SelectedWallpaperProvider._();

final class SelectedWallpaperProvider
    extends $NotifierProvider<SelectedWallpaper, WallpaperInfo?> {
  SelectedWallpaperProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'selectedWallpaperProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$selectedWallpaperHash();

  @$internal
  @override
  SelectedWallpaper create() => SelectedWallpaper();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(WallpaperInfo? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<WallpaperInfo?>(value),
    );
  }
}

String _$selectedWallpaperHash() => r'1d4f473402bccbf66b0537ef7f1bc2b2859991cb';

abstract class _$SelectedWallpaper extends $Notifier<WallpaperInfo?> {
  WallpaperInfo? build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<WallpaperInfo?, WallpaperInfo?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<WallpaperInfo?, WallpaperInfo?>,
              WallpaperInfo?,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

@ProviderFor(checkedWallpaperList)
final checkedWallpaperListProvider = CheckedWallpaperListProvider._();

final class CheckedWallpaperListProvider
    extends
        $FunctionalProvider<
          List<WallpaperInfo>,
          List<WallpaperInfo>,
          List<WallpaperInfo>
        >
    with $Provider<List<WallpaperInfo>> {
  CheckedWallpaperListProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'checkedWallpaperListProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$checkedWallpaperListHash();

  @$internal
  @override
  $ProviderElement<List<WallpaperInfo>> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  List<WallpaperInfo> create(Ref ref) {
    return checkedWallpaperList(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<WallpaperInfo> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<WallpaperInfo>>(value),
    );
  }
}

String _$checkedWallpaperListHash() =>
    r'4c7bf098f7f0aed51024ef02b829de1f0f3bcfbd';

@ProviderFor(filterWallpaperList)
final filterWallpaperListProvider = FilterWallpaperListProvider._();

final class FilterWallpaperListProvider
    extends
        $FunctionalProvider<
          List<WallpaperInfo>,
          List<WallpaperInfo>,
          List<WallpaperInfo>
        >
    with $Provider<List<WallpaperInfo>> {
  FilterWallpaperListProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'filterWallpaperListProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$filterWallpaperListHash();

  @$internal
  @override
  $ProviderElement<List<WallpaperInfo>> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  List<WallpaperInfo> create(Ref ref) {
    return filterWallpaperList(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<WallpaperInfo> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<WallpaperInfo>>(value),
    );
  }
}

String _$filterWallpaperListHash() =>
    r'1b632826f82345f6d0bd53ef171570d185a65669';

/// How many wallpapers in the batch have finished, 0..total. A count, not a
/// cursor: with several in flight, completions arrive out of order.

@ProviderFor(CurrentIndex)
final currentIndexProvider = CurrentIndexProvider._();

/// How many wallpapers in the batch have finished, 0..total. A count, not a
/// cursor: with several in flight, completions arrive out of order.
final class CurrentIndexProvider extends $NotifierProvider<CurrentIndex, int> {
  /// How many wallpapers in the batch have finished, 0..total. A count, not a
  /// cursor: with several in flight, completions arrive out of order.
  CurrentIndexProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'currentIndexProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$currentIndexHash();

  @$internal
  @override
  CurrentIndex create() => CurrentIndex();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(int value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<int>(value),
    );
  }
}

String _$currentIndexHash() => r'67cf7267bd4b3f62e23625c6b2a7f56de369077c';

/// How many wallpapers in the batch have finished, 0..total. A count, not a
/// cursor: with several in flight, completions arrive out of order.

abstract class _$CurrentIndex extends $Notifier<int> {
  int build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<int, int>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<int, int>,
              int,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

/// The wallpaper a worker most recently picked up, for the loading preview.
/// Separate from [CurrentIndex], which would index past the end of the list as
/// the last item completes.

@ProviderFor(ProcessingWallpaper)
final processingWallpaperProvider = ProcessingWallpaperProvider._();

/// The wallpaper a worker most recently picked up, for the loading preview.
/// Separate from [CurrentIndex], which would index past the end of the list as
/// the last item completes.
final class ProcessingWallpaperProvider
    extends $NotifierProvider<ProcessingWallpaper, WallpaperInfo?> {
  /// The wallpaper a worker most recently picked up, for the loading preview.
  /// Separate from [CurrentIndex], which would index past the end of the list as
  /// the last item completes.
  ProcessingWallpaperProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'processingWallpaperProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$processingWallpaperHash();

  @$internal
  @override
  ProcessingWallpaper create() => ProcessingWallpaper();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(WallpaperInfo? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<WallpaperInfo?>(value),
    );
  }
}

String _$processingWallpaperHash() =>
    r'709a2a363e6790849947435fe8ddf3260b6d52e5';

/// The wallpaper a worker most recently picked up, for the loading preview.
/// Separate from [CurrentIndex], which would index past the end of the list as
/// the last item completes.

abstract class _$ProcessingWallpaper extends $Notifier<WallpaperInfo?> {
  WallpaperInfo? build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<WallpaperInfo?, WallpaperInfo?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<WallpaperInfo?, WallpaperInfo?>,
              WallpaperInfo?,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
