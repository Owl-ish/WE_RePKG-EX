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

String _$wallpaperListHash() => r'56442ba8dea795b612487b4deaeb19ea84d68cc9';

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

/// Which wallpapers are selected, by id.
///
/// Held apart from the library so ticking one does not rewrite two thousand
/// elements and send filterWallpaperList through a fresh filter and sort. Ids
/// rather than objects, so nothing here can hold a stale copy of a wallpaper.

@ProviderFor(CheckedIds)
final checkedIdsProvider = CheckedIdsProvider._();

/// Which wallpapers are selected, by id.
///
/// Held apart from the library so ticking one does not rewrite two thousand
/// elements and send filterWallpaperList through a fresh filter and sort. Ids
/// rather than objects, so nothing here can hold a stale copy of a wallpaper.
final class CheckedIdsProvider
    extends $NotifierProvider<CheckedIds, Set<String>> {
  /// Which wallpapers are selected, by id.
  ///
  /// Held apart from the library so ticking one does not rewrite two thousand
  /// elements and send filterWallpaperList through a fresh filter and sort. Ids
  /// rather than objects, so nothing here can hold a stale copy of a wallpaper.
  CheckedIdsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'checkedIdsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$checkedIdsHash();

  @$internal
  @override
  CheckedIds create() => CheckedIds();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Set<String> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Set<String>>(value),
    );
  }
}

String _$checkedIdsHash() => r'3a62cdd25c2b97a01a80352aad3e8a560f25b394';

/// Which wallpapers are selected, by id.
///
/// Held apart from the library so ticking one does not rewrite two thousand
/// elements and send filterWallpaperList through a fresh filter and sort. Ids
/// rather than objects, so nothing here can hold a stale copy of a wallpaper.

abstract class _$CheckedIds extends $Notifier<Set<String>> {
  Set<String> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<Set<String>, Set<String>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<Set<String>, Set<String>>,
              Set<String>,
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
    r'3458e30140cff65c5520778bfff201100ea6029f';

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

String _$currentIndexHash() => r'ca6669ca239f0ac46f386125140680c52ffacf3c';

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
