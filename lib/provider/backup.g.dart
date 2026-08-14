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

String _$backupScanHash() => r'ec9bd5ae2c7796469a752b7843a2f0b47a36b62e';

/// The scan's cards in grid order, each with the title and preview to draw.
///
/// Kept apart from the scan so that reading a few thousand `project.json` files
/// cannot delay the counts, and so an unreadable one costs a picture rather
/// than a card.

@ProviderFor(backupTiles)
final backupTilesProvider = BackupTilesProvider._();

/// The scan's cards in grid order, each with the title and preview to draw.
///
/// Kept apart from the scan so that reading a few thousand `project.json` files
/// cannot delay the counts, and so an unreadable one costs a picture rather
/// than a card.

final class BackupTilesProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<BackupTile>>,
          List<BackupTile>,
          FutureOr<List<BackupTile>>
        >
    with $FutureModifier<List<BackupTile>>, $FutureProvider<List<BackupTile>> {
  /// The scan's cards in grid order, each with the title and preview to draw.
  ///
  /// Kept apart from the scan so that reading a few thousand `project.json` files
  /// cannot delay the counts, and so an unreadable one costs a picture rather
  /// than a card.
  BackupTilesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'backupTilesProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$backupTilesHash();

  @$internal
  @override
  $FutureProviderElement<List<BackupTile>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<BackupTile>> create(Ref ref) {
    return backupTiles(ref);
  }
}

String _$backupTilesHash() => r'c033ad5a5f23b0bac56a0bf32ee38b7ad0515a28';

/// The names waiting to be reconciled, each with the title and preview to draw.
///
/// Apart from [backupTiles]: a few hundred folders against several thousand,
/// and they only ever show behind their own pill.

@ProviderFor(backupReconcileTiles)
final backupReconcileTilesProvider = BackupReconcileTilesProvider._();

/// The names waiting to be reconciled, each with the title and preview to draw.
///
/// Apart from [backupTiles]: a few hundred folders against several thousand,
/// and they only ever show behind their own pill.

final class BackupReconcileTilesProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<ReconcileTile>>,
          List<ReconcileTile>,
          FutureOr<List<ReconcileTile>>
        >
    with
        $FutureModifier<List<ReconcileTile>>,
        $FutureProvider<List<ReconcileTile>> {
  /// The names waiting to be reconciled, each with the title and preview to draw.
  ///
  /// Apart from [backupTiles]: a few hundred folders against several thousand,
  /// and they only ever show behind their own pill.
  BackupReconcileTilesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'backupReconcileTilesProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$backupReconcileTilesHash();

  @$internal
  @override
  $FutureProviderElement<List<ReconcileTile>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<ReconcileTile>> create(Ref ref) {
    return backupReconcileTiles(ref);
  }
}

String _$backupReconcileTilesHash() =>
    r'32098fa1fec350a47164d79152629a7e4d591613';

/// What is typed in the backup tab's search box.
///
/// Its own, not the wallpaper tab's. That grid shows one library at a time and
/// this one shows both plus what has vanished, so a term left behind on one tab
/// would quietly empty the other.

@ProviderFor(BackupSearch)
final backupSearchProvider = BackupSearchProvider._();

/// What is typed in the backup tab's search box.
///
/// Its own, not the wallpaper tab's. That grid shows one library at a time and
/// this one shows both plus what has vanished, so a term left behind on one tab
/// would quietly empty the other.
final class BackupSearchProvider
    extends $NotifierProvider<BackupSearch, String> {
  /// What is typed in the backup tab's search box.
  ///
  /// Its own, not the wallpaper tab's. That grid shows one library at a time and
  /// this one shows both plus what has vanished, so a term left behind on one tab
  /// would quietly empty the other.
  BackupSearchProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'backupSearchProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$backupSearchHash();

  @$internal
  @override
  BackupSearch create() => BackupSearch();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String>(value),
    );
  }
}

String _$backupSearchHash() => r'5ba6572469be2d8f46a6bf8e97e4f84e8edf4d0e';

/// What is typed in the backup tab's search box.
///
/// Its own, not the wallpaper tab's. That grid shows one library at a time and
/// this one shows both plus what has vanished, so a term left behind on one tab
/// would quietly empty the other.

abstract class _$BackupSearch extends $Notifier<String> {
  String build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<String, String>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<String, String>,
              String,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

/// Session state rather than a setting: the pills are how the tab is being
/// looked at now, and returning to a grid narrowed by a pill switched off days
/// ago is how a wallpaper goes missing quietly.
///
/// Opens on the worst state that holds something, which on a library with work
/// waiting is the one with an obvious next step. Every other pill holding
/// anything glows for itself, so nothing is hidden by starting narrow.

@ProviderFor(BackupStateFilter)
final backupStateFilterProvider = BackupStateFilterProvider._();

/// Session state rather than a setting: the pills are how the tab is being
/// looked at now, and returning to a grid narrowed by a pill switched off days
/// ago is how a wallpaper goes missing quietly.
///
/// Opens on the worst state that holds something, which on a library with work
/// waiting is the one with an obvious next step. Every other pill holding
/// anything glows for itself, so nothing is hidden by starting narrow.
final class BackupStateFilterProvider
    extends $NotifierProvider<BackupStateFilter, BackupShown> {
  /// Session state rather than a setting: the pills are how the tab is being
  /// looked at now, and returning to a grid narrowed by a pill switched off days
  /// ago is how a wallpaper goes missing quietly.
  ///
  /// Opens on the worst state that holds something, which on a library with work
  /// waiting is the one with an obvious next step. Every other pill holding
  /// anything glows for itself, so nothing is hidden by starting narrow.
  BackupStateFilterProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'backupStateFilterProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$backupStateFilterHash();

  @$internal
  @override
  BackupStateFilter create() => BackupStateFilter();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(BackupShown value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<BackupShown>(value),
    );
  }
}

String _$backupStateFilterHash() => r'dfbcfc720f3a9144612e633e006136864237d1f1';

/// Session state rather than a setting: the pills are how the tab is being
/// looked at now, and returning to a grid narrowed by a pill switched off days
/// ago is how a wallpaper goes missing quietly.
///
/// Opens on the worst state that holds something, which on a library with work
/// waiting is the one with an obvious next step. Every other pill holding
/// anything glows for itself, so nothing is hidden by starting narrow.

abstract class _$BackupStateFilter extends $Notifier<BackupShown> {
  BackupShown build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<BackupShown, BackupShown>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<BackupShown, BackupShown>,
              BackupShown,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

@ProviderFor(BackupSortOrder)
final backupSortOrderProvider = BackupSortOrderProvider._();

final class BackupSortOrderProvider
    extends $NotifierProvider<BackupSortOrder, BackupSortType> {
  BackupSortOrderProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'backupSortOrderProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$backupSortOrderHash();

  @$internal
  @override
  BackupSortOrder create() => BackupSortOrder();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(BackupSortType value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<BackupSortType>(value),
    );
  }
}

String _$backupSortOrderHash() => r'1eb0bd7aa21c257682ed279a6484bef65ca69193';

abstract class _$BackupSortOrder extends $Notifier<BackupSortType> {
  BackupSortType build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<BackupSortType, BackupSortType>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<BackupSortType, BackupSortType>,
              BackupSortType,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

@ProviderFor(BackupSortAscending)
final backupSortAscendingProvider = BackupSortAscendingProvider._();

final class BackupSortAscendingProvider
    extends $NotifierProvider<BackupSortAscending, bool> {
  BackupSortAscendingProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'backupSortAscendingProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$backupSortAscendingHash();

  @$internal
  @override
  BackupSortAscending create() => BackupSortAscending();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$backupSortAscendingHash() =>
    r'c967c42e0ed0b106abd895c83146658d1e0e516e';

abstract class _$BackupSortAscending extends $Notifier<bool> {
  bool build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<bool, bool>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<bool, bool>,
              bool,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

/// The cards the grid draws. Apart from [backupTiles] so that typing re-filters
/// a list in memory rather than re-reading a few thousand folders.

@ProviderFor(backupVisibleTiles)
final backupVisibleTilesProvider = BackupVisibleTilesProvider._();

/// The cards the grid draws. Apart from [backupTiles] so that typing re-filters
/// a list in memory rather than re-reading a few thousand folders.

final class BackupVisibleTilesProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<BackupTile>>,
          AsyncValue<List<BackupTile>>,
          AsyncValue<List<BackupTile>>
        >
    with $Provider<AsyncValue<List<BackupTile>>> {
  /// The cards the grid draws. Apart from [backupTiles] so that typing re-filters
  /// a list in memory rather than re-reading a few thousand folders.
  BackupVisibleTilesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'backupVisibleTilesProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$backupVisibleTilesHash();

  @$internal
  @override
  $ProviderElement<AsyncValue<List<BackupTile>>> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  AsyncValue<List<BackupTile>> create(Ref ref) {
    return backupVisibleTiles(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AsyncValue<List<BackupTile>> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AsyncValue<List<BackupTile>>>(value),
    );
  }
}

String _$backupVisibleTilesHash() =>
    r'48e3d223d036e043679a937185c26f3ba2cdd06f';

/// The reconcile tiles the grid draws, under the same search, filter and order.

@ProviderFor(backupVisibleReconcileTiles)
final backupVisibleReconcileTilesProvider =
    BackupVisibleReconcileTilesProvider._();

/// The reconcile tiles the grid draws, under the same search, filter and order.

final class BackupVisibleReconcileTilesProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<ReconcileTile>>,
          AsyncValue<List<ReconcileTile>>,
          AsyncValue<List<ReconcileTile>>
        >
    with $Provider<AsyncValue<List<ReconcileTile>>> {
  /// The reconcile tiles the grid draws, under the same search, filter and order.
  BackupVisibleReconcileTilesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'backupVisibleReconcileTilesProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$backupVisibleReconcileTilesHash();

  @$internal
  @override
  $ProviderElement<AsyncValue<List<ReconcileTile>>> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  AsyncValue<List<ReconcileTile>> create(Ref ref) {
    return backupVisibleReconcileTiles(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AsyncValue<List<ReconcileTile>> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AsyncValue<List<ReconcileTile>>>(
        value,
      ),
    );
  }
}

String _$backupVisibleReconcileTilesHash() =>
    r'5f2e3abff6c84a74699de79ee5abb00562e559d4';

/// Ids of whatever the grid is drawing, which is what the selection is pruned
/// against: a tile out of view is out of the selection.

@ProviderFor(backupVisibleIds)
final backupVisibleIdsProvider = BackupVisibleIdsProvider._();

/// Ids of whatever the grid is drawing, which is what the selection is pruned
/// against: a tile out of view is out of the selection.

final class BackupVisibleIdsProvider
    extends
        $FunctionalProvider<
          AsyncValue<Set<String>>,
          AsyncValue<Set<String>>,
          AsyncValue<Set<String>>
        >
    with $Provider<AsyncValue<Set<String>>> {
  /// Ids of whatever the grid is drawing, which is what the selection is pruned
  /// against: a tile out of view is out of the selection.
  BackupVisibleIdsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'backupVisibleIdsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$backupVisibleIdsHash();

  @$internal
  @override
  $ProviderElement<AsyncValue<Set<String>>> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  AsyncValue<Set<String>> create(Ref ref) {
    return backupVisibleIds(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AsyncValue<Set<String>> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AsyncValue<Set<String>>>(value),
    );
  }
}

String _$backupVisibleIdsHash() => r'6b3c591c21c02f42a5240c77531ce3e2560bba4b';

/// Which backup cards are selected, by [BackupCard.id].
///
/// Its own selection rather than the extract tab's: the two grids show
/// different things, and a wallpaper live in both libraries is two cards here
/// and one there.

@ProviderFor(BackupSelection)
final backupSelectionProvider = BackupSelectionProvider._();

/// Which backup cards are selected, by [BackupCard.id].
///
/// Its own selection rather than the extract tab's: the two grids show
/// different things, and a wallpaper live in both libraries is two cards here
/// and one there.
final class BackupSelectionProvider
    extends $NotifierProvider<BackupSelection, Set<String>> {
  /// Which backup cards are selected, by [BackupCard.id].
  ///
  /// Its own selection rather than the extract tab's: the two grids show
  /// different things, and a wallpaper live in both libraries is two cards here
  /// and one there.
  BackupSelectionProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'backupSelectionProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$backupSelectionHash();

  @$internal
  @override
  BackupSelection create() => BackupSelection();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Set<String> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Set<String>>(value),
    );
  }
}

String _$backupSelectionHash() => r'451df40fdc6d3854a5d478ad2ca31f35ef228440';

/// Which backup cards are selected, by [BackupCard.id].
///
/// Its own selection rather than the extract tab's: the two grids show
/// different things, and a wallpaper live in both libraries is two cards here
/// and one there.

abstract class _$BackupSelection extends $Notifier<Set<String>> {
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
