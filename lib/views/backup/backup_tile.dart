import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:we_repkg/config/theme_extensions.dart';
import 'package:we_repkg/constants/i10n.dart';
import 'package:we_repkg/constants/nums.dart';
import 'package:we_repkg/cores/context_menu.dart';
import 'package:we_repkg/cores/base.dart';
import 'package:we_repkg/cores/wallpaper.dart';
import 'package:we_repkg/models/wallpaper.dart';
import 'package:we_repkg/provider/backup.dart';
import 'package:we_repkg/utils/backup_diff.dart';
import 'package:we_repkg/utils/backup_tiles.dart';
import 'package:we_repkg/utils/double_click.dart';
import 'package:we_repkg/utils/modifier_keys.dart';
import 'package:we_repkg/utils/wallpaper_junk.dart';
import 'package:we_repkg/views/content/detail_dialog.dart';
import 'package:we_repkg/views/content/title.dart';
import 'package:we_repkg/widgets/image_view.dart';
import 'package:we_repkg/widgets/tile_overlays.dart';
import 'package:we_repkg/widgets/app_icon_button.dart';
import 'package:we_repkg/widgets/input_controls.dart';
import 'package:we_repkg/widgets/file_tree_panel.dart';
import 'package:we_repkg/views/backup/backup_action.dart';

/// The two folders a tile stands for, either of which may not be there. The
/// details open on whichever exists; the menu offers each one it has.
typedef TileFolders = ({String? live, String? backup});

/// One wallpaper in the backup grid, with the badge saying where it stands.
class BackupTileView extends StatelessWidget {
  const BackupTileView({
    super.key,
    required this.width,
    required this.tile,
    required this.folders,
    required this.onTap,
    this.onAction,
    this.junkKind,
    this.updatePlan,
  });

  final double width;
  final BackupTile tile;
  final TileFolders folders;

  /// Clicking is handled by the grid, which is where the ordered list a shift
  /// range needs actually lives.
  final VoidCallback onTap;
  final VoidCallback? onAction;
  final WallpaperJunkKind? junkKind;
  final BackupUpdatePlan? updatePlan;

  @override
  Widget build(BuildContext context) {
    final ({Color colour, String label}) look = backupStateLook(
      context,
      tile.state,
    );
    final BackupUpdatePlan? plan = tile.state == BackupState.updateAvailable
        ? updatePlan ?? const BackupUpdatePlan(updateContent: true)
        : null;
    final List<TileBadgeData> stateBadges = plan == null
        ? <TileBadgeData>[
            TileBadgeData(text: tr(look.label), colour: look.colour),
          ]
        : <TileBadgeData>[
            if (plan.updateContent)
              TileBadgeData(
                text: tr(AppI10n.backupTileUpdate),
                colour: look.colour,
              ),
            if (plan.needsSync)
              TileBadgeData(
                text: tr(AppI10n.backupTileSync),
                colour: look.colour,
              ),
          ];
    final String? actionLabel = plan == null
        ? null
        : plan.updateContent && plan.needsSync
        ? tr(AppI10n.backupStateUpdateAvailable)
        : plan.needsSync
        ? tr(AppI10n.backupTileSync)
        : tr(AppI10n.backupTileUpdate);
    return _TileFrame(
      width: width,
      id: tile.card.id,
      face: tile.face,
      name: tile.card.name,
      folders: folders,
      onTap: onTap,
      action: actionForBackupState(tile.state),
      actionLabelOverride: actionLabel,
      onAction: onAction,
      junkKind: junkKind,
      updatePlan: plan,
      backupCard: tile.card,
      detailText: _stateDetailText(tile.state),
      badges: <TileBadgeData>[
        ...stateBadges,
        TileBadgeData(
          colour: Colors.black.withValues(alpha: .55),
          text: tr(switch (tile.card.library) {
            WallpaperLibrary.workshop => AppI10n.homeLibraryWorkshop,
            WallpaperLibrary.myProjects => AppI10n.homeLibraryMyProjects,
          }),
        ),
      ],
    );
  }
}

/// One name waiting to be reconciled, in the same grid behind its own pill.
class ReconcileTileView extends StatelessWidget {
  const ReconcileTileView({
    super.key,
    required this.width,
    required this.tile,
    required this.folders,
    required this.onTap,
  });

  final double width;
  final ReconcileTile tile;
  final TileFolders folders;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _TileFrame(
      width: width,
      id: reconcileTileId(tile.entry.name),
      face: tile.face,
      name: tile.entry.name,
      folders: folders,
      onTap: onTap,
      reconcileEntry: tile.entry,
      badges: <TileBadgeData>[
        TileBadgeData(
          colour: Theme.of(context).status.bad,
          text: _reconcileBadgeText(tile.entry),
        ),
        if (tile.entry.needsBackup.isNotEmpty)
          TileBadgeData(
            colour: backupStateLook(context, BackupState.notBackedUp).colour,
            text: tr(AppI10n.backupStateNotBackedUp),
          ),
      ],
    );
  }
}

/// The picture, the title strip, the badges and the selection tint, plus the
/// three things a click can mean. Shared, so the two tiles cannot drift apart.
class _TileFrame extends ConsumerStatefulWidget {
  const _TileFrame({
    required this.width,
    required this.id,
    required this.face,
    required this.name,
    required this.folders,
    required this.badges,
    required this.onTap,
    this.action,
    this.actionLabelOverride,
    this.onAction,
    this.junkKind,
    this.updatePlan,
    this.backupCard,
    this.detailText,
    this.reconcileEntry,
  });

  final double width;
  final String id;
  final CardFace? face;

  /// Folder name, which is what a tile with no readable `project.json` is
  /// titled by.
  final String name;

  final TileFolders folders;
  final List<TileBadgeData> badges;
  final VoidCallback onTap;
  final BackupAction? action;
  final String? actionLabelOverride;
  final VoidCallback? onAction;
  final WallpaperJunkKind? junkKind;
  final BackupUpdatePlan? updatePlan;
  final BackupCard? backupCard;
  final String? detailText;
  final ReconcileEntry? reconcileEntry;

  @override
  ConsumerState<_TileFrame> createState() => _TileFrameState();
}

class _TileFrameState extends ConsumerState<_TileFrame> {
  static const Duration _actionFadeIn = Duration(milliseconds: 180);
  static const Duration _actionFadeOut = Duration(milliseconds: 140);

  final DoubleClickGuard _clicks = DoubleClickGuard();
  late final FocusNode _tileFocusNode;
  ScrollPosition? _actionScrollPosition;
  bool _hovered = false;
  bool _focused = false;
  bool _scrolling = false;

  @override
  void initState() {
    super.initState();
    _tileFocusNode = FocusNode(debugLabel: 'backup-tile-${widget.id}');
  }

  bool get _actionInterested =>
      widget.action != null &&
      widget.onAction != null &&
      (_hovered || _focused);

  bool get _actionVisible => _actionInterested && !_scrolling;

  void _setHovered(bool hovered) {
    if (_hovered == hovered) return;
    _updateActionInterest(() => _hovered = hovered);
  }

  void _setFocused(bool focused) {
    if (_focused == focused) return;
    _updateActionInterest(() => _focused = focused);
  }

  void _updateActionInterest(VoidCallback update) {
    final bool wasVisible = _actionVisible;
    update();
    _syncActionScroll();
    if (wasVisible != _actionVisible && mounted) setState(() {});
  }

  void _syncActionScroll() {
    final ScrollPosition? next = _actionInterested
        ? Scrollable.maybeOf(context)?.position
        : null;
    if (!identical(next, _actionScrollPosition)) {
      _actionScrollPosition?.isScrollingNotifier.removeListener(
        _onActionScrollChanged,
      );
      _actionScrollPosition = next;
      _actionScrollPosition?.isScrollingNotifier.addListener(
        _onActionScrollChanged,
      );
    }
    _scrolling = _actionScrollPosition?.isScrollingNotifier.value ?? false;
  }

  void _onActionScrollChanged() {
    final bool scrolling =
        _actionScrollPosition?.isScrollingNotifier.value ?? false;
    if (_scrolling == scrolling || !mounted) return;
    final bool wasVisible = _actionVisible;
    _scrolling = scrolling;
    if (wasVisible != _actionVisible) setState(() {});
  }

  KeyEventResult _onTileKeyEvent(FocusNode node, KeyEvent event) {
    if (!node.hasPrimaryFocus || event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.space) {
      widget.onTap();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void didUpdateWidget(covariant _TileFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncActionScroll();
  }

  @override
  void dispose() {
    _actionScrollPosition?.isScrollingNotifier.removeListener(
      _onActionScrollChanged,
    );
    _tileFocusNode.dispose();
    super.dispose();
  }

  /// This tile's rectangle on screen, so the detail dialog can grow out of it.
  Rect? _tileRect() {
    final RenderBox? box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  void _onPointerDown(PointerDownEvent event) {
    if (event.buttons != kPrimaryButton || event.localPosition == Offset.zero) {
      return;
    }
    // The guard keeps the second click of a double click from undoing the
    // first. Plain clicks only: ctrl and shift never open the details, and
    // ticking a tile off straight after ticking it on is ordinary.
    if (isCtrlPressed || isShiftPressed || !_clicks.isSecondClick(widget.id)) {
      widget.onTap();
    }
  }

  List<DetailAction> _actions() => <DetailAction>[
    if (widget.action case final BackupAction action)
      if (widget.onAction case final VoidCallback onAction)
        DetailAction(
          label: widget.actionLabelOverride ?? backupActionLabel(action),
          onPressed: onAction,
          destructive: backupActionIsDestructive(action),
        ),
    if (widget.folders.live case final String live)
      DetailAction(
        label: tr(AppI10n.backupOpenLiveFolder),
        onPressed: () => browserFolder(live),
      ),
    if (widget.folders.backup case final String backup)
      DetailAction(
        label: tr(AppI10n.backupOpenBackupFolder),
        onPressed: () => browserFolder(backup),
      ),
  ];

  Future<void> _openDetails() async {
    // The backup copy is the only one left for a vanished wallpaper.
    final String? folder = widget.folders.live ?? widget.folders.backup;
    if (folder == null) return;
    // Measured before the read, or the tile may have scrolled by the time the
    // folder comes back.
    final Rect? origin = _tileRect();
    final WallpaperInfo wallpaper = await readWallpaperFolder(folder);
    if (!mounted) return;
    final bool reconcileNeedsFocus = _reconcileNeedsFileFocus(
      widget.reconcileEntry,
    );
    await showWallpaperDetail(
      context,
      wallpaper,
      origin: origin,
      actions: _actions(),
      includePreview: widget.junkKind == null,
      layout: widget.reconcileEntry == null
          ? const DetailDialogLayout()
          : DetailDialogLayout(
              extraFillsPanel: true,
              extraCanFocus: reconcileNeedsFocus,
            ),
      extraContentBuilder: widget.junkKind != null
          ? (BuildContext context, Color foreground, bool _) =>
                _JunkDetailContent(
                  folderPath: folder,
                  kind: widget.junkKind!,
                  library: _fileTreeLibrary(widget.backupCard!.library),
                  foreground: foreground,
                )
          : widget.reconcileEntry != null
          ? (BuildContext context, Color foreground, bool focused) =>
                _ReconcileDetailContent(
                  entry: widget.reconcileEntry!,
                  foreground: foreground,
                  focused: focused,
                  needsFocus: reconcileNeedsFocus,
                )
          : widget.updatePlan != null && widget.backupCard != null
          ? (BuildContext context, Color foreground, bool _) =>
                _UpdatePlanDetailContent(
                  plan: widget.updatePlan!,
                  card: widget.backupCard!,
                  foreground: foreground,
                )
          : widget.detailText == null
          ? null
          : (BuildContext context, Color foreground, bool _) =>
                _BackupDetailContent(
                  text: widget.detailText!,
                  foreground: foreground,
                ),
    );
  }

  Widget _actionButton(
    BuildContext context,
    BackupAction action,
    VoidCallback onAction,
  ) {
    final bool destructive = backupActionIsDestructive(action);
    final ActionButtonTheme colors = Theme.of(context).actionButtons;
    final Color glowColour = destructive
        ? colors.destructiveForeground
        : colors.primaryForeground;
    final Widget button = destructive
        ? AppActionIconButton.destructive(
            icon: backupActionIcon(action),
            tooltip: widget.actionLabelOverride ?? backupActionLabel(action),
            onPressed: onAction,
            width: 34,
            height: 34,
            iconSize: 18,
          )
        : AppActionIconButton(
            icon: backupActionIcon(action),
            tooltip: widget.actionLabelOverride ?? backupActionLabel(action),
            onPressed: onAction,
            width: 34,
            height: 34,
            iconSize: 18,
          );
    return RepaintBoundary(
      child: BackupActionGlow(
        colour: glowColour,
        enabled: true,
        borderRadius: BorderRadius.circular(999),
        glowKey: const ValueKey<String>('backup-tile-action-glow'),
        scale: .7,
        child: button,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool checked = ref.watch(
      backupSelectionProvider.select((ids) => ids.contains(widget.id)),
    );
    final bool revealAction = _actionVisible;
    Map<CustomSemanticsAction, VoidCallback>? semanticActions;
    if (!revealAction && widget.action != null && widget.onAction != null) {
      semanticActions = <CustomSemanticsAction, VoidCallback>{
        CustomSemanticsAction(
          label:
              widget.actionLabelOverride ?? backupActionLabel(widget.action!),
        ): widget.onAction!,
      };
    }
    return Semantics(
      button: true,
      onTap: widget.onTap,
      customSemanticsActions: semanticActions,
      child: Focus(
        focusNode: _tileFocusNode,
        onKeyEvent: _onTileKeyEvent,
        onFocusChange: _setFocused,
        child: Listener(
          onPointerDown: _onPointerDown,
          child: InkWell(
            canRequestFocus: false,
            overlayColor: const WidgetStatePropertyAll<Color>(
              Colors.transparent,
            ),
            splashFactory: NoSplash.splashFactory,
            onDoubleTap: _openDetails,
            onSecondaryTapDown: (TapDownDetails details) => showBackupMenu(
              context,
              details,
              onDetails: _openDetails,
              liveFolder: widget.folders.live,
              backupFolder: widget.folders.backup,
              actionLabel: widget.action == null
                  ? null
                  : widget.actionLabelOverride ??
                        backupActionLabel(widget.action!),
              onAction: widget.onAction,
            ),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              onEnter: (_) => _setHovered(true),
              onExit: (_) => _setHovered(false),
              child: Container(
                width: widget.width,
                decoration: BoxDecoration(
                  // The shadow has to know the radius too, or it keeps painting
                  // square corners behind the rounded tile.
                  borderRadius: BorderRadius.circular(LayoutNums.surfaceRadius),
                  boxShadow: const <BoxShadow>[
                    BoxShadow(
                      color: Colors.black54,
                      blurRadius: 4,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(LayoutNums.surfaceRadius),
                  clipBehavior: Clip.hardEdge,
                  child: Stack(
                    children: [
                      ImageView(
                        size: widget.width,
                        previews: widget.face?.preview ?? '',
                      ),
                      // The folder name when there is no readable project.json,
                      // which is the case the integrity tab exists to point at.
                      ImageTitle(title: widget.face?.title ?? widget.name),
                      Positioned(
                        left: 4,
                        right: 4,
                        top: 4,
                        child: TileBadgeStrip(badges: widget.badges),
                      ),
                      if (widget.action case final BackupAction action)
                        if (widget.onAction case final VoidCallback onAction)
                          Positioned(
                            right: LayoutNums.smallGap,
                            bottom: 28,
                            width: 34,
                            height: 34,
                            child: AnimatedSwitcher(
                              duration: _scrolling
                                  ? Duration.zero
                                  : _actionFadeIn,
                              reverseDuration: _scrolling
                                  ? Duration.zero
                                  : _actionFadeOut,
                              switchInCurve: Curves.easeOutCubic,
                              switchOutCurve: Curves.easeInCubic,
                              transitionBuilder:
                                  (Widget child, Animation<double> animation) =>
                                      FadeTransition(
                                        opacity: animation,
                                        child: child,
                                      ),
                              child: revealAction
                                  ? _actionButton(context, action, onAction)
                                  : const SizedBox.shrink(),
                            ),
                          ),
                      if (checked) const SelectionTint(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _stateDetailText(BackupState state) => switch (state) {
  BackupState.synced => AppI10n.backupAboutSynced,
  BackupState.notBackedUp => AppI10n.backupAboutNotBackedUp,
  BackupState.vanished => AppI10n.backupAboutVanished,
  BackupState.updateAvailable => AppI10n.backupAboutUpdateAvailable,
  BackupState.updateDismissed => AppI10n.backupAboutUpdateDismissed,
  BackupState.emptyBackup => AppI10n.backupEmptyJunkAbout,
};

String _reconcileBadgeText(ReconcileEntry entry) => switch (entry.reason) {
  BackupReconcileReason.duplicateLiveCopies => tr(
    AppI10n.backupTileDuplicateLive,
  ),
  BackupReconcileReason.conflictingBackupCopies => tr(
    AppI10n.backupTileBackupsConflict,
  ),
  BackupReconcileReason.comparisonUnavailable => tr(
    AppI10n.backupTileComparisonUnavailable,
  ),
};

class _UpdatePlanDetailContent extends StatelessWidget {
  const _UpdatePlanDetailContent({
    required this.plan,
    required this.card,
    required this.foreground,
  });

  final BackupUpdatePlan plan;
  final BackupCard card;
  final Color foreground;

  String _backupPath(WallpaperLibrary library) {
    final String root = tr(switch (library) {
      WallpaperLibrary.workshop => AppI10n.backupFolderBackupWorkshop,
      WallpaperLibrary.myProjects => AppI10n.backupFolderBackupMyProjects,
    });
    return '$root\\${card.name}';
  }

  @override
  Widget build(BuildContext context) {
    final BackupSyncPlan? sync = plan.sync;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (plan.updateContent)
          _DetailGroup(
            title: tr(AppI10n.backupTileUpdate),
            items: <String>[tr(AppI10n.backupDetailUpdateToLive)],
            foreground: foreground,
          ),
        if (sync != null && sync.kind == BackupSyncKind.relocate)
          _SyncMoveDetail(
            fromPath: _backupPath(sync.from),
            toPath: _backupPath(sync.to),
            foreground: foreground,
          ),
        if (sync != null && sync.kind == BackupSyncKind.removeDuplicate)
          _SyncDuplicateDetail(
            keepPath: _backupPath(sync.to),
            removePath: _backupPath(sync.from),
            foreground: foreground,
          ),
      ],
    );
  }
}

class _SyncMoveHeading extends StatelessWidget {
  const _SyncMoveHeading({required this.foreground});

  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final String heading = tr(AppI10n.backupDetailSyncWillMove);
    final int separator = heading.indexOf(' - ');
    if (separator < 0) {
      return Text(heading, style: TextStyle(color: foreground));
    }
    return Text.rich(
      TextSpan(
        style: TextStyle(color: foreground),
        children: <InlineSpan>[
          TextSpan(
            text: heading.substring(0, separator),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          TextSpan(text: heading.substring(separator)),
        ],
      ),
    );
  }
}

class _SyncMoveDetail extends StatelessWidget {
  const _SyncMoveDetail({
    required this.fromPath,
    required this.toPath,
    required this.foreground,
  });

  final String fromPath;
  final String toPath;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _SyncMoveHeading(foreground: foreground),
          const SizedBox(height: 2),
          ReadOnlyPathBox(path: fromPath),
          const SizedBox(height: 1),
          Center(
            child: Icon(
              Icons.keyboard_arrow_down_rounded,
              color: foreground.withValues(alpha: .72),
              size: 18,
            ),
          ),
          const SizedBox(height: 1),
          ReadOnlyPathBox(path: toPath),
        ],
      ),
    );
  }
}

class _SyncDuplicateDetail extends StatelessWidget {
  const _SyncDuplicateDetail({
    required this.keepPath,
    required this.removePath,
    required this.foreground,
  });

  final String keepPath;
  final String removePath;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            tr(AppI10n.backupTileSync),
            style: TextStyle(color: foreground, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            tr(AppI10n.backupDetailSyncWillKeep),
            style: TextStyle(color: foreground),
          ),
          const SizedBox(height: 4),
          ReadOnlyPathBox(path: keepPath),
          const SizedBox(height: 6),
          Text(
            tr(AppI10n.backupDetailSyncWillRemove),
            style: TextStyle(color: foreground),
          ),
          const SizedBox(height: 4),
          ReadOnlyPathBox(path: removePath),
        ],
      ),
    );
  }
}

class _BackupDetailContent extends StatelessWidget {
  const _BackupDetailContent({required this.text, required this.foreground});

  final String text;
  final Color foreground;

  @override
  Widget build(BuildContext context) =>
      Text(tr(text), style: TextStyle(color: foreground, height: 1.35));
}

FileTreeLibrary _fileTreeLibrary(WallpaperLibrary library) => switch (library) {
  WallpaperLibrary.workshop => FileTreeLibrary.workshop,
  WallpaperLibrary.myProjects => FileTreeLibrary.myProjects,
};

class _JunkDetailContent extends StatelessWidget {
  const _JunkDetailContent({
    required this.folderPath,
    required this.kind,
    required this.library,
    required this.foreground,
  });

  final String folderPath;
  final WallpaperJunkKind kind;
  final FileTreeLibrary library;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final String explanation = switch (kind) {
      WallpaperJunkKind.empty => AppI10n.backupJunkDetailsEmpty,
      WallpaperJunkKind.shaderCacheOnly => AppI10n.backupJunkDetailsShader,
      WallpaperJunkKind.mixed => AppI10n.backupJunkDetailsMixed,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          tr(explanation),
          style: TextStyle(color: foreground, height: 1.35),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: FileTreePanel(
            key: const ValueKey<String>('backup-junk-file-tree'),
            folderPath: folderPath,
            foreground: foreground,
            library: library,
          ),
        ),
      ],
    );
  }
}

/// Presentation for one backup state, using the active semantic palette.
({Color colour, String label}) backupStateLook(
  BuildContext context,
  BackupState state,
) {
  final StatusPalette colours = Theme.of(context).status;
  return switch (state) {
    BackupState.vanished => (
      colour: colours.bad,
      label: AppI10n.backupStateVanished,
    ),
    BackupState.emptyBackup => (
      colour: colours.hollow,
      label: AppI10n.backupStateEmptyBackup,
    ),
    BackupState.notBackedUp => (
      colour: colours.warn,
      label: AppI10n.backupStateNotBackedUp,
    ),
    BackupState.updateAvailable => (
      colour: colours.note,
      label: AppI10n.backupStateUpdateAvailable,
    ),
    BackupState.updateDismissed => (
      colour: colours.muted,
      label: AppI10n.backupStateUpdateDismissed,
    ),
    BackupState.synced => (
      colour: colours.good,
      label: AppI10n.backupStateSynced,
    ),
  };
}

bool _reconcileNeedsFileFocus(ReconcileEntry? entry) {
  if (entry == null ||
      entry.reason != BackupReconcileReason.conflictingBackupCopies) {
    return false;
  }
  final BackupCopyDifference? difference = entry.backupDifference;
  if (difference == null || difference.total == 0) return false;
  final int groups = <List<String>>[
    difference.differentSize,
    difference.onlyWorkshop,
    difference.onlyMyProjects,
  ].where((List<String> paths) => paths.isNotEmpty).length;
  final Iterable<String> paths = <String>[
    ...difference.differentSize,
    ...difference.onlyWorkshop,
    ...difference.onlyMyProjects,
  ];
  final int longest = paths.fold<int>(
    0,
    (int length, String path) => path.length > length ? path.length : length,
  );
  return difference.total + groups > 4 || longest > 58;
}

class _ReconcileDetailContent extends StatelessWidget {
  const _ReconcileDetailContent({
    required this.entry,
    required this.foreground,
    required this.focused,
    required this.needsFocus,
  });

  final ReconcileEntry entry;
  final Color foreground;
  final bool focused;
  final bool needsFocus;

  @override
  Widget build(BuildContext context) {
    final String explanation = switch (entry.reason) {
      BackupReconcileReason.duplicateLiveCopies =>
        AppI10n.backupReconcileDuplicateLiveAbout,
      BackupReconcileReason.conflictingBackupCopies =>
        AppI10n.backupReconcileConflictingBackupsAbout,
      BackupReconcileReason.comparisonUnavailable =>
        AppI10n.backupReconcileComparisonUnavailableAbout,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          tr(explanation),
          style: TextStyle(color: foreground, height: 1.35),
        ),
        const SizedBox(height: 12),
        Expanded(child: _details(context)),
      ],
    );
  }

  Widget _details(BuildContext context) => switch (entry.reason) {
    BackupReconcileReason.duplicateLiveCopies => SingleChildScrollView(
      child: _DetailGroup(
        title: tr(AppI10n.backupDetailDetectedCopies),
        items: <String>[
          tr(AppI10n.backupDetailWorkshopLive),
          tr(AppI10n.backupDetailMyProjectsLive),
        ],
        foreground: foreground,
      ),
    ),
    BackupReconcileReason.comparisonUnavailable => SingleChildScrollView(
      child: _DetailGroup(
        title: tr(AppI10n.backupDetailComparisonFailed),
        items: <String>[tr(AppI10n.backupDetailRescanAdvice)],
        foreground: foreground,
      ),
    ),
    BackupReconcileReason.conflictingBackupCopies when needsFocus && !focused =>
      FileTreeSurface(
        key: const ValueKey<String>('backup-reconcile-expand-differences'),
        foreground: foreground,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            child: Row(
              children: <Widget>[
                Icon(
                  Icons.unfold_more_rounded,
                  size: 18,
                  color: foreground.withValues(alpha: .75),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tr(AppI10n.backupDetailExpandDifferences),
                    textAlign: TextAlign.center,
                    softWrap: true,
                    style: TextStyle(
                      color: foreground,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    BackupReconcileReason.conflictingBackupCopies => _DifferenceFileTree(
      difference: entry.backupDifference,
      foreground: foreground,
    ),
  };
}

class _DifferenceFileTree extends StatelessWidget {
  const _DifferenceFileTree({
    required this.difference,
    required this.foreground,
  });

  final BackupCopyDifference? difference;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final BackupCopyDifference? value = difference;
    if (value == null || value.total == 0) {
      return FileTreeSurface(
        foreground: foreground,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Text(
            tr(AppI10n.backupDetailDifferenceUnavailable),
            style: TextStyle(color: foreground, height: 1.3),
          ),
        ),
      );
    }
    final StatusPalette colours = Theme.of(context).status;
    return FileTreeScrollView(
      key: const ValueKey<String>('backup-reconcile-detail-scroll'),
      foreground: foreground,
      semanticLabel:
          '${tr(AppI10n.backupDetailDetectedDifferences)}: ${value.total}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (value.differentSize.isNotEmpty)
            _differenceGroup(
              title: tr(AppI10n.backupDetailDifferentSize),
              paths: value.differentSize,
              colour: colours.warn,
            ),
          if (value.onlyWorkshop.isNotEmpty)
            _differenceGroup(
              title: tr(AppI10n.backupDetailOnlyWorkshop),
              paths: value.onlyWorkshop,
              colour: fileTreeLibraryColour(context, FileTreeLibrary.workshop),
            ),
          if (value.onlyMyProjects.isNotEmpty)
            _differenceGroup(
              title: tr(AppI10n.backupDetailOnlyMyProjects),
              paths: value.onlyMyProjects,
              colour: fileTreeLibraryColour(
                context,
                FileTreeLibrary.myProjects,
              ),
            ),
        ],
      ),
    );
  }

  Widget _differenceGroup({
    required String title,
    required List<String> paths,
    required Color colour,
  }) {
    final List<String> ordered = List<String>.from(
      paths,
    )..sort((String a, String b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return FileTreeGroup(
      title: title,
      count: ordered.length,
      accent: colour,
      foreground: foreground,
      children: <Widget>[
        for (final String filePath in ordered)
          FileTreeRow(
            depth: 1,
            icon: Icons.insert_drive_file_outlined,
            iconColor: colour,
            label: filePath.replaceAll('\\', '  ›  ').replaceAll('/', '  ›  '),
            foreground: foreground,
          ),
      ],
    );
  }
}

class _DetailGroup extends StatelessWidget {
  const _DetailGroup({
    required this.title,
    required this.items,
    required this.foreground,
  });

  final String title;
  final List<String> items;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: TextStyle(color: foreground, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          for (final String item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                '• $item',
                style: TextStyle(color: foreground, height: 1.3),
              ),
            ),
        ],
      ),
    );
  }
}
