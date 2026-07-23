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

String _$wallpaperListHash() => r'20948ed9ba76cea499a0fdcd58bed099f9cdb90b';

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

@ProviderFor(HoverWallpaper)
final hoverWallpaperProvider = HoverWallpaperProvider._();

final class HoverWallpaperProvider
    extends $NotifierProvider<HoverWallpaper, WallpaperInfo?> {
  HoverWallpaperProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'hoverWallpaperProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$hoverWallpaperHash();

  @$internal
  @override
  HoverWallpaper create() => HoverWallpaper();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(WallpaperInfo? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<WallpaperInfo?>(value),
    );
  }
}

String _$hoverWallpaperHash() => r'312e4fe561eeb2886af2e452c7404a5eaec41bdb';

abstract class _$HoverWallpaper extends $Notifier<WallpaperInfo?> {
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
    r'59bdc449246056d5536d7a3d08c728b009cc435c';

@ProviderFor(ExtractList)
final extractListProvider = ExtractListProvider._();

final class ExtractListProvider
    extends $NotifierProvider<ExtractList, List<WallpaperInfo>> {
  ExtractListProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'extractListProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$extractListHash();

  @$internal
  @override
  ExtractList create() => ExtractList();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<WallpaperInfo> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<WallpaperInfo>>(value),
    );
  }
}

String _$extractListHash() => r'12ecd00d629ca547d5f5c332e8f114092f175394';

abstract class _$ExtractList extends $Notifier<List<WallpaperInfo>> {
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

@ProviderFor(CurrentIndex)
final currentIndexProvider = CurrentIndexProvider._();

final class CurrentIndexProvider extends $NotifierProvider<CurrentIndex, int> {
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

String _$currentIndexHash() => r'ccbb7f2f4cab3ae7874d0120beaf604a2cf89edf';

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
