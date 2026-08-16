import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:we_repkg/config/theme_extensions.dart';
import 'package:we_repkg/constants/i10n.dart';
import 'package:we_repkg/constants/nums.dart';
import 'package:we_repkg/cores/context_menu.dart';
import 'package:we_repkg/cores/base.dart';
import 'package:we_repkg/cores/wallpaper.dart';
import 'package:we_repkg/cores/backup_action.dart';
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
import 'package:we_repkg/widgets/selection_tint.dart';
import 'package:we_repkg/widgets/app_icon_button.dart';
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
  });

  final double width;
  final BackupTile tile;
  final TileFolders folders;

  /// Clicking is handled by the grid, which is where the ordered list a shift
  /// range needs actually lives.
  final VoidCallback onTap;
  final VoidCallback? onAction;
  final WallpaperJunkKind? junkKind;

  @override
  Widget build(BuildContext context) {
    return _TileFrame(
      width: width,
      id: tile.card.id,
      face: tile.face,
      name: tile.card.name,
      folders: folders,
      onTap: onTap,
      action: actionForBackupState(tile.state),
      onAction: onAction,
      junkKind: junkKind,
      badges: <Widget>[
        Positioned(left: 4, top: 4, child: _StateBadge(state: tile.state)),
        Positioned(
          right: 4,
          top: 4,
          child: _Pill(
            colour: Colors.black.withValues(alpha: .55),
            // A wallpaper in both libraries is two tiles side by side, and this
            // is the only thing telling them apart.
            text: tr(switch (tile.card.library) {
              WallpaperLibrary.workshop => AppI10n.homeLibraryWorkshop,
              WallpaperLibrary.myProjects => AppI10n.homeLibraryMyProjects,
            }),
          ),
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
      badges: <Widget>[
        Positioned(
          left: 4,
          top: 4,
          child: _Pill(
            colour: _reconcileColour,
            text: tr(AppI10n.backupReconcile),
          ),
        ),
        Positioned(right: 4, top: 4, child: _PresenceMatrix(entry: tile.entry)),
        if (tile.entry.needsBackup.isNotEmpty)
          Positioned(
            left: 4,
            bottom: 28,
            child: _Pill(
              colour: backupStateLook(context, BackupState.notBackedUp).colour,
              text: tr(AppI10n.backupStateNotBackedUp),
            ),
          ),
      ],
    );
  }
}

/// Grey rather than a state colour: a name here is a question, not a verdict.
const Color _reconcileColour = Color(0xFF455A64);

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
    this.onAction,
    this.junkKind,
  });

  final double width;
  final String id;
  final CardFace? face;

  /// Folder name, which is what a tile with no readable `project.json` is
  /// titled by.
  final String name;

  final TileFolders folders;
  final List<Widget> badges;
  final VoidCallback onTap;
  final BackupAction? action;
  final VoidCallback? onAction;
  final WallpaperJunkKind? junkKind;

  @override
  ConsumerState<_TileFrame> createState() => _TileFrameState();
}

class _TileFrameState extends ConsumerState<_TileFrame> {
  final DoubleClickGuard _clicks = DoubleClickGuard();

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
          label: backupActionLabel(action),
          onPressed: onAction,
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
    await showWallpaperDetail(
      context,
      wallpaper,
      origin: origin,
      actions: _actions(),
      includePreview: widget.junkKind == null,
      extraContentBuilder: widget.junkKind == null
          ? null
          : (BuildContext context, Color foreground) => _JunkDetailContent(
              folderPath: folder,
              kind: widget.junkKind!,
              foreground: foreground,
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // select, so selecting elsewhere in the grid does not rebuild this tile.
    final bool checked = ref.watch(
      backupSelectionProvider.select((ids) => ids.contains(widget.id)),
    );
    return Listener(
      onPointerDown: _onPointerDown,
      child: InkWell(
        overlayColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
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
              : backupActionLabel(widget.action!),
          onAction: widget.onAction,
        ),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            width: widget.width,
            decoration: BoxDecoration(
              // The shadow has to know the radius too, or it keeps painting
              // square corners behind the rounded tile.
              borderRadius: BorderRadius.circular(LayoutNums.surfaceRadius),
              boxShadow: const [
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
                  ...widget.badges,
                  if (widget.action case final BackupAction action)
                    if (widget.onAction case final VoidCallback onAction)
                      Positioned(
                        right: LayoutNums.smallGap,
                        bottom: 28,
                        child: Material(
                          color: Theme.of(
                            context,
                          ).actionButtons.primaryBackground,
                          shape: const CircleBorder(),
                          child: AppIconButton(
                            icon: backupActionIcon(action),
                            tooltip: backupActionLabel(action),
                            onPressed: onAction,
                            width: 34,
                            height: 34,
                            iconSize: 18,
                            color: Theme.of(
                              context,
                            ).actionButtons.primaryForeground,
                          ),
                        ),
                      ),
                  if (checked) const SelectionTint(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _JunkDetailContent extends StatelessWidget {
  const _JunkDetailContent({
    required this.folderPath,
    required this.kind,
    required this.foreground,
  });

  final String folderPath;
  final WallpaperJunkKind kind;
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

class _StateBadge extends StatelessWidget {
  const _StateBadge({required this.state});

  final BackupState state;

  @override
  Widget build(BuildContext context) {
    final ({Color colour, String label}) look = backupStateLook(context, state);
    return _Pill(colour: look.colour, text: tr(look.label));
  }
}

/// Four dots: columns Workshop and myprojects, rows live then backup, filled
/// where the folder exists.
class _PresenceMatrix extends StatelessWidget {
  const _PresenceMatrix({required this.entry});

  final ReconcileEntry entry;

  static const double _dot = 6;
  static const double _gap = 3;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: _gap,
        children: <Widget>[
          _row(entry.liveWorkshop, entry.liveMyProjects),
          _row(entry.backupWorkshop, entry.backupMyProjects),
        ],
      ),
    );
  }

  Widget _row(bool workshop, bool myProjects) => Row(
    mainAxisSize: MainAxisSize.min,
    spacing: _gap,
    children: <Widget>[_cell(workshop), _cell(myProjects)],
  );

  Widget _cell(bool present) => Container(
    width: _dot,
    height: _dot,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: present ? Colors.white : Colors.transparent,
      border: Border.all(color: Colors.white70, width: 1),
    ),
  );
}

class _Pill extends StatelessWidget {
  const _Pill({required this.colour, required this.text});

  final Color colour;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: colour,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontFamily: 'Microsoft YaHei',
        ),
      ),
    );
  }
}
