import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:we_repkg/config/theme_extensions.dart';
import 'package:we_repkg/constants/i10n.dart';
import 'package:we_repkg/constants/nums.dart';
import 'package:we_repkg/cores/context_menu.dart';
import 'package:we_repkg/cores/base.dart';
import 'package:we_repkg/cores/backup.dart';
import 'package:we_repkg/cores/wallpaper.dart';
import 'package:we_repkg/models/wallpaper.dart';
import 'package:we_repkg/provider/backup.dart';
import 'package:we_repkg/utils/backup_diff.dart';
import 'package:we_repkg/utils/backup_tiles.dart';
import 'package:we_repkg/utils/double_click.dart';
import 'package:we_repkg/utils/modifier_keys.dart';
import 'package:we_repkg/utils/wallpaper_junk.dart';
import 'package:we_repkg/views/backup/details/content_details.dart';
import 'package:we_repkg/views/content/detail_dialog.dart';
import 'package:we_repkg/views/content/title.dart';
import 'package:we_repkg/widgets/image_view.dart';
import 'package:we_repkg/widgets/tile_overlays.dart';
import 'package:we_repkg/views/backup/backup_action_ui.dart';

/// The two folders a tile stands for, either of which may not be there. The
/// details open on whichever exists; the menu offers each one it has.
typedef TileFolders = ({String? live, String? backup});

typedef _ReconcileFolders = ({
  String? workshopLive,
  String? myProjectsLive,
  String? workshopBackup,
  String? myProjectsBackup,
});

DetailDialogLayout _backupDetailLayout({
  bool extraCanFocus = false,
  bool hasSecondAction = false,
}) => DetailDialogLayout(
  // Keep Backup only modestly taller than the ordinary 500px detail card.
  // Dense sections scroll/focus inside this footprint instead of inflating
  // the whole modal.
  maxHeightFactor: .84,
  // An added Reconcile Ignore/Show Again action needs one more control row.
  // Reserve its eight pixels up front so focusing the file pane stays stable.
  maxHeight: hasSecondAction ? 568 : 560,
  extraFillsPanel: true,
  extraCanFocus: extraCanFocus,
);

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
    this.backupRoot,
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
  final String? backupRoot;

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
      backupRoot: backupRoot,
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
    this.backupRoot,
    this.liveWorkshopRoot,
    this.liveMyProjectsRoot,
    this.ignored = false,
    this.reasonOverride,
    this.selectionIdOverride,
  });

  final double width;
  final ReconcileTile tile;
  final TileFolders folders;
  final VoidCallback onTap;
  final String? backupRoot;
  final String? liveWorkshopRoot;
  final String? liveMyProjectsRoot;
  final bool ignored;
  final BackupReconcileReason? reasonOverride;
  final String? selectionIdOverride;

  @override
  Widget build(BuildContext context) {
    return _TileFrame(
      width: width,
      id: selectionIdOverride ?? reconcileTileId(tile.entry.name),
      face: tile.face,
      name: tile.entry.name,
      folders: folders,
      onTap: onTap,
      backupRoot: backupRoot,
      liveWorkshopRoot: liveWorkshopRoot,
      liveMyProjectsRoot: liveMyProjectsRoot,
      reconcileEntry: tile.entry,
      reconcileIgnored: ignored,
      reconcileReasonOverride: reasonOverride,
      action: ignored ? BackupAction.showUpdateAgain : null,
      actionLabelOverride: ignored ? tr(AppI10n.backupActionShowAgain) : null,
      onAction: ignored && reasonOverride != null
          ? () => showReconcileDetectionAgain(
              context,
              tile.entry,
              reasonOverride!,
            )
          : null,
      badges: _reconcileBadges(
        context,
        tile.entry,
        ignored: ignored,
        reasonOverride: reasonOverride,
      ),
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
    this.backupRoot,
    this.liveWorkshopRoot,
    this.liveMyProjectsRoot,
    this.backupCard,
    this.detailText,
    this.reconcileEntry,
    this.reconcileIgnored = false,
    this.reconcileReasonOverride,
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
  final String? backupRoot;
  final String? liveWorkshopRoot;
  final String? liveMyProjectsRoot;
  final BackupCard? backupCard;
  final String? detailText;
  final ReconcileEntry? reconcileEntry;
  final bool reconcileIgnored;
  final BackupReconcileReason? reconcileReasonOverride;

  @override
  ConsumerState<_TileFrame> createState() => _TileFrameState();
}

class _TileFrameState extends ConsumerState<_TileFrame> {
  final DoubleClickGuard _clicks = DoubleClickGuard();
  late final FocusNode _tileFocusNode;

  @override
  void initState() {
    super.initState();
    _tileFocusNode = FocusNode(debugLabel: 'backup-tile-${widget.id}');
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
  void dispose() {
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
    if (widget.reconcileEntry == null &&
        widget.updatePlan?.updateContent == true)
      if (widget.backupCard case final BackupCard card)
        DetailAction(
          label: backupActionLabel(BackupAction.ignoreUpdate),
          onPressed: () => applyBackupAction(
            context,
            BackupAction.ignoreUpdate,
            <BackupCard>[card],
          ),
        ),
    if (widget.reconcileEntry != null && !widget.reconcileIgnored)
      if (widget.reconcileEntry case final ReconcileEntry entry)
        if (entry.activeReasons.any(
          (BackupReconcileReason reason) =>
              reconcileReasonCanBeIgnored(reason) &&
              entry.issueFingerprints.containsKey(reason),
        ))
          DetailAction(
            label: tr(AppI10n.backupActionIgnore),
            onPressed: () => ignoreReconcileDetections(context, entry),
          ),
    if (widget.reconcileEntry == null)
      if (widget.folders.live case final String live)
        DetailAction(
          label: tr(AppI10n.backupOpenLiveFolder),
          onPressed: () => browserFolder(live),
        ),
    if (widget.reconcileEntry == null)
      if (widget.folders.backup case final String backup)
        DetailAction(
          label: tr(AppI10n.backupOpenBackupFolder),
          onPressed: () => browserFolder(backup),
        ),
  ];

  String? _backupFolderFor(WallpaperLibrary library, String name) {
    final String? libraryPath = switch (library) {
      WallpaperLibrary.workshop => backupWorkshopPath(widget.backupRoot),
      WallpaperLibrary.myProjects => backupMyProjectsPath(widget.backupRoot),
    };
    return libraryPath == null ? null : path.join(libraryPath, name);
  }

  String? _updateBackupFolder() {
    final BackupUpdatePlan? plan = widget.updatePlan;
    final BackupCard? card = widget.backupCard;
    if (plan == null || !plan.updateContent || card == null) return null;
    if (widget.folders.backup case final String existing) return existing;
    final WallpaperLibrary library = plan.sync?.from ?? card.library;
    return _backupFolderFor(library, card.name);
  }

  _ReconcileFolders _reconcileFolders(ReconcileEntry entry) {
    final BackupIssueEvidence evidence = entry.evidence;
    return (
      workshopLive: evidence.liveWorkshop && widget.liveWorkshopRoot != null
          ? path.join(widget.liveWorkshopRoot!, entry.name)
          : null,
      myProjectsLive:
          evidence.liveMyProjects && widget.liveMyProjectsRoot != null
          ? path.join(widget.liveMyProjectsRoot!, entry.name)
          : null,
      workshopBackup: evidence.backupWorkshop
          ? _backupFolderFor(WallpaperLibrary.workshop, entry.name)
          : null,
      myProjectsBackup: evidence.backupMyProjects
          ? _backupFolderFor(WallpaperLibrary.myProjects, entry.name)
          : null,
    );
  }

  List<BackupFolderMenuTarget> _menuFolders() {
    final ReconcileEntry? entry = widget.reconcileEntry;
    if (entry == null) {
      return <BackupFolderMenuTarget>[
        if (widget.folders.live case final String live)
          (label: tr(AppI10n.backupOpenLiveFolder), path: live),
        if (widget.folders.backup case final String backup)
          (label: tr(AppI10n.backupOpenBackupFolder), path: backup),
      ];
    }
    final _ReconcileFolders folders = _reconcileFolders(entry);
    return <BackupFolderMenuTarget>[
      if (folders.workshopLive case final String folder)
        (label: tr(AppI10n.backupOpenWorkshopLiveFolder), path: folder),
      if (folders.myProjectsLive case final String folder)
        (label: tr(AppI10n.backupOpenMyProjectsLiveFolder), path: folder),
      if (folders.workshopBackup case final String folder)
        (label: tr(AppI10n.backupOpenWorkshopBackupFolder), path: folder),
      if (folders.myProjectsBackup case final String folder)
        (label: tr(AppI10n.backupOpenMyProjectsBackupFolder), path: folder),
    ];
  }

  Future<void> _openDetails() async {
    // The backup copy is the only one left for a vanished wallpaper.
    final String? folder = widget.folders.live ?? widget.folders.backup;
    if (folder == null) return;
    // Measured before the read, or the tile may have scrolled by the time the
    // folder comes back.
    final Rect? origin = _tileRect();
    final WallpaperInfo wallpaper = await readWallpaperFolder(folder);
    if (!mounted) return;
    final ReconcileEntry? reconcileEntry = widget.reconcileEntry;
    final bool reconcileNeedsFocus = reconcileNeedsFileFocus(
      reconcileEntry,
      ignored: widget.reconcileIgnored,
      reasonOverride: widget.reconcileReasonOverride,
    );
    final _ReconcileFolders? reconcileFolders = reconcileEntry == null
        ? null
        : _reconcileFolders(reconcileEntry);
    final String? updateBackupFolder = _updateBackupFolder();
    final bool updateNeedsFocus =
        widget.updatePlan?.updateContent == true &&
        widget.folders.live != null &&
        updateBackupFolder != null;
    await showWallpaperDetail(
      context,
      wallpaper,
      origin: origin,
      actions: _actions(),
      includePreview: widget.junkKind == null,
      layout: widget.junkKind != null
          ? const DetailDialogLayout()
          : _backupDetailLayout(
              extraCanFocus: reconcileEntry != null
                  ? reconcileNeedsFocus
                  : updateNeedsFocus,
              hasSecondAction:
                  reconcileEntry != null &&
                  (widget.reconcileIgnored ||
                      reconcileEntry.activeReasons.any(
                        (BackupReconcileReason reason) =>
                            reconcileReasonCanBeIgnored(reason) &&
                            reconcileEntry.issueFingerprints.containsKey(
                              reason,
                            ),
                      )),
            ),
      extraContentBuilder: widget.junkKind != null
          ? (BuildContext context, Color foreground, bool _, VoidCallback _) =>
                JunkDetailContent(
                  folderPath: folder,
                  kind: widget.junkKind!,
                  library: widget.backupCard!.library,
                  foreground: foreground,
                )
          : widget.reconcileEntry != null
          ? (
              BuildContext context,
              Color foreground,
              bool _,
              VoidCallback requestFocus,
            ) => ReconcileDetailContent(
              entry: widget.reconcileEntry!,
              primaryReasonOverride: widget.reconcileReasonOverride,
              foreground: foreground,
              needsFocus: reconcileNeedsFocus,
              ignoredMode: widget.reconcileIgnored,
              workshopLiveFolder: reconcileFolders?.workshopLive,
              myProjectsLiveFolder: reconcileFolders?.myProjectsLive,
              workshopBackupFolder: reconcileFolders?.workshopBackup,
              myProjectsBackupFolder: reconcileFolders?.myProjectsBackup,
              onRequestFocus: requestFocus,
            )
          : widget.updatePlan != null && widget.backupCard != null
          ? (
              BuildContext context,
              Color foreground,
              bool focused,
              VoidCallback requestFocus,
            ) => UpdatePlanDetailContent(
              plan: widget.updatePlan!,
              card: widget.backupCard!,
              liveFolder: widget.folders.live,
              backupFolder: updateBackupFolder,
              foreground: foreground,
              focused: focused,
              needsFocus: updateNeedsFocus,
              onRequestFocus: requestFocus,
            )
          : widget.detailText == null
          ? null
          : (BuildContext context, Color foreground, bool _, VoidCallback _) =>
                BackupDetailContent(
                  text: widget.detailText!,
                  foreground: foreground,
                ),
    );
  }

  Widget _actionButton(BackupAction action, VoidCallback onAction) {
    final ActionButtonTheme colors = Theme.of(context).actionButtons;
    final bool destructive = backupActionIsDestructive(action);
    return _BackupTileActionButton(
      id: widget.id,
      icon: backupActionIcon(action),
      label: widget.actionLabelOverride ?? backupActionLabel(action),
      background: destructive
          ? colors.destructiveBackground
          : colors.primaryBackground,
      foreground: destructive
          ? colors.destructiveForeground
          : colors.primaryForeground,
      border: destructive ? colors.destructiveBorder : colors.primaryBorder,
      onPressed: onAction,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool checked = ref.watch(
      backupSelectionProvider.select((ids) => ids.contains(widget.id)),
    );
    return Semantics(
      button: true,
      onTap: widget.onTap,
      child: Focus(
        focusNode: _tileFocusNode,
        onKeyEvent: _onTileKeyEvent,
        child: Listener(
          onPointerDown: _onPointerDown,
          child: InkWell(
            canRequestFocus: false,
            mouseCursor: SystemMouseCursors.click,
            overlayColor: const WidgetStatePropertyAll<Color>(
              Colors.transparent,
            ),
            splashFactory: NoSplash.splashFactory,
            onDoubleTap: _openDetails,
            onSecondaryTapDown: (TapDownDetails details) => showBackupMenu(
              context,
              details,
              onDetails: _openDetails,
              folders: _menuFolders(),
              actionLabel: widget.action == null
                  ? null
                  : widget.actionLabelOverride ??
                        backupActionLabel(widget.action!),
              onAction: widget.onAction,
            ),
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
                          child: _actionButton(action, onAction),
                        ),
                    if (checked) const SelectionTint(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Hover feedback for the always-visible tile action is isolated from the tile
/// itself, so moving the pointer only rebuilds this 34px control rather than the
/// preview, badges, selection tint, and provider-backed tile subtree.
class _BackupTileActionButton extends StatefulWidget {
  const _BackupTileActionButton({
    required this.id,
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
    required this.border,
    required this.onPressed,
  });

  final String id;
  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;
  final Color border;
  final VoidCallback onPressed;

  @override
  State<_BackupTileActionButton> createState() =>
      _BackupTileActionButtonState();
}

class _BackupTileActionButtonState extends State<_BackupTileActionButton> {
  bool _hovered = false;

  void _setHovered(bool hovered) {
    if (_hovered == hovered) return;
    setState(() => _hovered = hovered);
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    onEnter: (_) => _setHovered(true),
    onExit: (_) => _setHovered(false),
    child: AnimatedScale(
      key: ValueKey<String>('backup-tile-action-scale-${widget.id}'),
      scale: _hovered ? 1.10 : 1,
      duration: const Duration(milliseconds: 110),
      curve: Curves.easeOutCubic,
      child: IconButton(
        key: ValueKey<String>('backup-tile-action-${widget.id}'),
        icon: Icon(
          widget.icon,
          semanticLabel: widget.label,
          color: widget.foreground,
          size: 18,
        ),
        onPressed: widget.onPressed,
        tooltip: null,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 34, height: 34),
        style: ButtonStyle(
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          animationDuration: Duration.zero,
          backgroundColor: WidgetStatePropertyAll<Color>(widget.background),
          overlayColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
          splashFactory: NoSplash.splashFactory,
          side: WidgetStatePropertyAll<BorderSide>(
            BorderSide(color: widget.border),
          ),
          shape: const WidgetStatePropertyAll<OutlinedBorder>(CircleBorder()),
        ),
      ),
    ),
  );
}

String _stateDetailText(BackupState state) => switch (state) {
  BackupState.synced => AppI10n.backupAboutSynced,
  BackupState.notBackedUp => AppI10n.backupAboutNotBackedUp,
  BackupState.vanished => AppI10n.backupAboutVanished,
  BackupState.updateAvailable => AppI10n.backupAboutUpdateAvailable,
  BackupState.updateDismissed => AppI10n.backupAboutUpdateDismissed,
  BackupState.emptyBackup => AppI10n.backupEmptyJunkAbout,
};

String _reconcileReasonBadgeText(BackupReconcileReason reason) =>
    switch (reason) {
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

List<TileBadgeData> _reconcileBadges(
  BuildContext context,
  ReconcileEntry entry, {
  bool ignored = false,
  BackupReconcileReason? reasonOverride,
}) {
  final List<BackupReconcileReason> reasons =
      (reasonOverride == null
              ? (ignored ? entry.ignoredReasons : entry.activeReasons)
              : <BackupReconcileReason>{reasonOverride})
          .toList()
        ..sort((a, b) => a.index.compareTo(b.index));
  final List<BackupState> states = entry.evidence.attentionStates.toList()
    ..sort(
      (a, b) => (backupSeverity[a] ?? 0).compareTo(backupSeverity[b] ?? 0),
    );
  return <TileBadgeData>[
    for (final BackupReconcileReason reason in reasons)
      TileBadgeData(
        colour: Theme.of(context).status.bad,
        text: _reconcileReasonBadgeText(reason),
      ),
    for (final BackupState state in states)
      TileBadgeData(
        colour: backupStateLook(context, state).colour,
        text: tr(backupStateLook(context, state).label),
      ),
  ];
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
