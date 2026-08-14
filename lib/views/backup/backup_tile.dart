import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
import 'package:we_repkg/views/content/detail_dialog.dart';
import 'package:we_repkg/views/content/title.dart';
import 'package:we_repkg/widgets/image_view.dart';
import 'package:we_repkg/widgets/selection_tint.dart';

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
  });

  final double width;
  final BackupTile tile;
  final TileFolders folders;

  /// Clicking is handled by the grid, which is where the ordered list a shift
  /// range needs actually lives.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _TileFrame(
      width: width,
      id: tile.card.id,
      face: tile.face,
      name: tile.card.name,
      folders: folders,
      onTap: onTap,
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
    if (widget.folders.live case final String live)
      (
        label: tr(AppI10n.backupOpenLiveFolder),
        onPressed: () => browserFolder(live),
      ),
    if (widget.folders.backup case final String backup)
      (
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

/// Colours per state, worst in red. Fixed rather than themed: these say how
/// safe a wallpaper is, and a palette that shifts with the theme would let
/// "vanished" read as decoration.
const Map<BackupState, ({Color colour, String label})> backupStateLook =
    <BackupState, ({Color colour, String label})>{
      BackupState.vanished: (
        colour: Color(0xFFC62828),
        label: AppI10n.backupStateVanished,
      ),
      BackupState.emptyBackup: (
        colour: Color(0xFFAD1457),
        label: AppI10n.backupStateEmptyBackup,
      ),
      BackupState.notBackedUp: (
        colour: Color(0xFFEF6C00),
        label: AppI10n.backupStateNotBackedUp,
      ),
      BackupState.updateAvailable: (
        colour: Color(0xFF1565C0),
        label: AppI10n.backupStateUpdateAvailable,
      ),
      BackupState.updateDismissed: (
        colour: Color(0xFF546E7A),
        label: AppI10n.backupStateUpdateDismissed,
      ),
      BackupState.synced: (
        colour: Color(0xFF2E7D32),
        label: AppI10n.backupStateSynced,
      ),
    };

class _StateBadge extends StatelessWidget {
  const _StateBadge({required this.state});

  final BackupState state;

  @override
  Widget build(BuildContext context) {
    final ({Color colour, String label}) look = backupStateLook[state]!;
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
