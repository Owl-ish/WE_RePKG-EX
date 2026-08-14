import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:we_repkg/config/theme_extensions.dart';
import 'package:we_repkg/constants/i10n.dart';
import 'package:we_repkg/constants/nums.dart';
import 'package:we_repkg/cores/base.dart';
import 'package:we_repkg/cores/integrity_scan.dart';
import 'package:we_repkg/views/backup/integrity_repair_action.dart';
import 'package:we_repkg/provider/integrity.dart';
import 'package:we_repkg/cores/integrity_rules.dart';
import 'package:we_repkg/utils/tool.dart';
import 'package:we_repkg/widgets/app_icon_button.dart';
import 'package:we_repkg/widgets/count_pill.dart';
import 'package:we_repkg/widgets/issue_note.dart';
import 'package:we_repkg/widgets/scan_progress.dart';

/// Every repair on the tab wears this and says "resolve". What it will do is
/// the confirmation's job, since it is a sentence rather than a word.
const IconData _resolveIcon = Icons.build_outlined;

typedef IntegrityRepairHandler =
    Future<void> Function(
      BuildContext context,
      IntegrityRepair repair,
      List<IntegrityFinding> targets,
    );

/// Beside their enums rather than in `models/enums.dart`, which would drag
/// `dart:io` into every widget that imports it. `BackupFolder`'s labels sit in
/// the backup view for the same reason.
const Map<IntegrityRoot, String> _rootLabels = <IntegrityRoot, String>{
  IntegrityRoot.liveWorkshop: AppI10n.integrityRootLiveWorkshop,
  IntegrityRoot.liveMyProjects: AppI10n.integrityRootLiveMyProjects,
  IntegrityRoot.backupWorkshop: AppI10n.integrityRootBackupWorkshop,
  IntegrityRoot.backupMyProjects: AppI10n.integrityRootBackupMyProjects,
};

/// How one concern is drawn and what it tells the user to do about it.
///
/// A switch rather than a map, so the next verdict added fails the analyzer
/// instead of the app.
typedef VerdictLook = ({
  Color colour,
  String label,
  String advice,
  IntegrityRepair? repair,
});

VerdictLook _verdictLook(
  IntegrityVerdict verdict,
  StatusPalette colours,
) => switch (verdict) {
  // Never drawn: the check lists only what integrityVerdictOrder holds. Kept so
  // the switch stays exhaustive.
  IntegrityVerdict.sound || IntegrityVerdict.empty => (
    colour: colours.note,
    label: AppI10n.integrityVerdictSound,
    advice: AppI10n.integrityClean,
    repair: null,
  ),
  IntegrityVerdict.payloadMissing => (
    colour: colours.bad,
    label: AppI10n.integrityVerdictPayloadMissing,
    advice: AppI10n.integrityAdvicePayloadMissing,
    repair: IntegrityRepair.restorePayload,
  ),
  IntegrityVerdict.projectUnreadable => (
    colour: colours.bad,
    label: AppI10n.integrityVerdictProjectUnreadable,
    advice: AppI10n.integrityAdviceProjectUnreadable,
    repair: IntegrityRepair.replaceProject,
  ),
  IntegrityVerdict.packedSceneNoProject => (
    colour: colours.warn,
    label: AppI10n.integrityVerdictPackedSceneNoProject,
    advice: AppI10n.integrityAdvicePackedSceneNoProject,
    repair: IntegrityRepair.rescue,
  ),
  IntegrityVerdict.unpackedSceneNoProject => (
    colour: colours.warn,
    label: AppI10n.integrityVerdictUnpackedSceneNoProject,
    advice: AppI10n.integrityAdviceUnpackedSceneNoProject,
    repair: IntegrityRepair.writeProject,
  ),
  IntegrityVerdict.mediaOnly => (
    colour: colours.warn,
    label: AppI10n.integrityVerdictMediaOnly,
    advice: AppI10n.integrityAdviceMediaOnly,
    repair: IntegrityRepair.resolveMedia,
  ),
  IntegrityVerdict.shaderCacheOnly => (
    colour: colours.note,
    label: AppI10n.integrityVerdictShaderCacheOnly,
    advice: AppI10n.integrityAdviceShaderCacheOnly,
    repair: IntegrityRepair.recycleShaderCache,
  ),
};

VerdictLook _resolvedLook(StatusPalette colours) => (
  colour: colours.good,
  label: AppI10n.integrityResolved,
  advice: AppI10n.integrityResolvedAdvice,
  repair: null,
);

String _resolutionLabel(IntegrityResolution resolution) => switch (resolution) {
  IntegrityResolution.restoredFile => AppI10n.integrityResolutionRestoredFile,
  IntegrityResolution.replacedProject =>
    AppI10n.integrityResolutionReplacedProject,
  IntegrityResolution.extractedProject =>
    AppI10n.integrityResolutionExtractedProject,
  IntegrityResolution.createdProject =>
    AppI10n.integrityResolutionCreatedProject,
  IntegrityResolution.recycled => AppI10n.integrityResolutionRecycled,
};

/// Every folder in all four roots, judged on whether Wallpaper Engine could
/// load it, with a repair only where the result is unambiguous.
class IntegrityView extends ConsumerWidget {
  const IntegrityView({super.key, this.onRepair});

  final IntegrityRepairHandler? onRepair;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return switch (ref.watch(integrityScanProvider)) {
      AsyncData<IntegrityReport>(:final IntegrityReport value) => _Report(
        report: value,
        onRepair: onRepair ?? applyIntegrityRepair,
      ),
      AsyncError<IntegrityReport>(:final Object error) => Center(
        child: Text('${tr(AppI10n.integrityFailed)} $error'),
      ),
      _ => ScanProgress(label: tr(AppI10n.integrityChecking)),
    };
  }
}

class _Report extends ConsumerWidget {
  const _Report({required this.report, required this.onRepair});

  final IntegrityReport report;
  final IntegrityRepairHandler onRepair;

  /// One pill per concern that holds something: a row of zeroes is a list of
  /// things that did not happen.
  List<Widget> _pills(
    WidgetRef ref,
    Map<IntegrityVerdict, int> counts,
    IntegrityVerdict shown,
    bool resolvedShown,
    int resolvedCount,
    StatusPalette colours,
  ) {
    final List<Widget> pills = <Widget>[];
    for (final IntegrityVerdict verdict in integrityVerdictOrder) {
      final int count = counts[verdict]!;
      if (count == 0) continue;
      final VerdictLook look = _verdictLook(verdict, colours);
      pills.add(
        CountPill(
          colour: look.colour,
          label: tr(look.label),
          count: count,
          on: !resolvedShown && verdict == shown,
          // Every one of these is worth a look, so a glow apiece would be a
          // wall of them.
          nags: false,
          onPressed: () {
            ref.read(integrityResolvedProvider.notifier).show(false);
            ref.read(integrityShownProvider.notifier).show(verdict);
          },
        ),
      );
    }
    if (resolvedCount > 0) {
      final VerdictLook look = _resolvedLook(colours);
      pills.add(
        CountPill(
          colour: look.colour,
          label: tr(look.label),
          count: resolvedCount,
          on: resolvedShown,
          nags: false,
          onPressed: () =>
              ref.read(integrityResolvedProvider.notifier).show(true),
        ),
      );
    }
    return pills;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final StatusPalette colours = Theme.of(context).status;
    final int checked = report.scanned.values.fold(
      0,
      (int sum, int n) => sum + n,
    );
    final Map<IntegrityVerdict, int> counts = verdictCounts(
      report.findings.map((IntegrityFinding f) => f.verdict),
    );
    final IntegrityResolvedState resolvedState = ref.watch(
      integrityResolvedProvider,
    );
    final List<ResolvedIntegrityIssue> resolved = resolvedState.issues;
    final IntegrityVerdict shown = shownVerdict(
      ref.watch(integrityShownProvider),
      counts,
    );
    final bool resolvedShown =
        resolved.isNotEmpty && (resolvedState.shown || report.findings.isEmpty);
    final VerdictLook shownLook = resolvedShown
        ? _resolvedLook(colours)
        : _verdictLook(shown, colours);
    final List<IntegrityFinding> resolvedFindings =
        resolved.map((ResolvedIntegrityIssue item) => item.finding).toList()
          ..sort(
            (IntegrityFinding a, IntegrityFinding b) =>
                a.root.index.compareTo(b.root.index),
          );
    final Map<IntegrityFinding, IntegrityResolution> resolutions =
        <IntegrityFinding, IntegrityResolution>{
          for (final ResolvedIntegrityIssue item in resolved)
            item.finding: item.resolution,
        };
    final bool hasPills = report.findings.isNotEmpty || resolved.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(top: LayoutNums.contentGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: LayoutNums.contentGap,
        children: <Widget>[
          _Summary(
            checked: checked,
            found: report.findings.length,
            onRecheck: () {
              ref.read(integrityResolvedProvider.notifier).show(false);
              ref.invalidate(integrityScanProvider);
            },
          ),
          if (report.missing.isNotEmpty) _MissingRoots(missing: report.missing),
          if (hasPills)
            PillRow(
              children: _pills(
                ref,
                counts,
                shown,
                resolvedShown,
                resolved.length,
                colours,
              ),
            ),
          if (hasPills)
            IssueNote(
              colour: shownLook.colour,
              icon: Icons.info_outline_rounded,
              child: Text(
                tr(shownLook.advice),
                style: Theme.of(
                  context,
                ).meta.mediumStyle.copyWith(height: 1.35),
              ),
            ),
          Expanded(
            child: resolvedShown
                ? _Findings(
                    key: const ValueKey<String>('resolved'),
                    findings: resolvedFindings,
                    look: shownLook,
                    onRepair: onRepair,
                    resolutions: resolutions,
                  )
                : report.findings.isNotEmpty
                ? _Findings(
                    // Keyed, or scrolling deep into a long concern leaves the
                    // next one part way down.
                    key: ValueKey<IntegrityVerdict>(shown),
                    findings: report.findings
                        .where((IntegrityFinding f) => f.verdict == shown)
                        .toList(),
                    look: shownLook,
                    onRepair: onRepair,
                  )
                // Nothing read is not a clean bill of health, and the roots
                // above already say why.
                : checked == 0
                ? const SizedBox.shrink()
                : const _Clean(),
          ),
        ],
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({
    required this.checked,
    required this.found,
    required this.onRecheck,
  });

  final int checked;
  final int found;
  final VoidCallback onRecheck;

  static const double _titleIconBackgroundSize = 34;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color resultColour = found > 0
        ? theme.status.warn
        : theme.status.good;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(LayoutNums.contentGap),
      decoration: BoxDecoration(
        color: theme.inputDecorationTheme.fillColor,
        borderRadius: BorderRadius.circular(LayoutNums.surfaceRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: LayoutNums.compactGap,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: _titleIconBackgroundSize,
                height: _titleIconBackgroundSize,
                decoration: BoxDecoration(
                  color: theme.primaryColor.withValues(alpha: .1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.health_and_safety_outlined,
                  size: 20,
                  color: theme.primaryColor,
                ),
              ),
              const SizedBox(width: LayoutNums.smallGap),
              Expanded(
                child: Text(
                  tr(AppI10n.integrityTitle),
                  overflow: TextOverflow.ellipsis,
                  style: theme.meta.largeStyle.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: onRecheck,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text(tr(AppI10n.integrityRecheck)),
              ),
            ],
          ),
          Text(
            tr(AppI10n.integrityAbout),
            style: theme.meta.mediumStyle.copyWith(height: 1.4),
          ),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: LayoutNums.mediumGap,
              vertical: LayoutNums.compactGap,
            ),
            decoration: BoxDecoration(
              color: resultColour.withValues(alpha: .09),
              borderRadius: BorderRadius.circular(LayoutNums.controlRadius),
            ),
            child: Text(
              found > 0
                  ? tr(
                      AppI10n.integrityFound,
                      namedArgs: <String, String>{
                        'checked': '$checked',
                        'found': '$found',
                      },
                    )
                  : tr(
                      AppI10n.integrityFoundNothing,
                      namedArgs: <String, String>{'checked': '$checked'},
                    ),
              style: theme.meta.mediumStyle.copyWith(
                color: resultColour,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Clean extends StatelessWidget {
  const _Clean();

  @override
  Widget build(BuildContext context) {
    // Said outright, because an empty list reads as "did not run".
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        spacing: LayoutNums.mediumGap,
        children: <Widget>[
          const Icon(Icons.verified_outlined, size: 48, color: Colors.grey),
          Text(tr(AppI10n.integrityClean)),
        ],
      ),
    );
  }
}

class _MissingRoots extends StatelessWidget {
  const _MissingRoots({required this.missing});

  final Set<IntegrityRoot> missing;

  @override
  Widget build(BuildContext context) {
    final Color error = Theme.of(context).colorScheme.error;
    return IssueNote(
      colour: error,
      icon: Icons.folder_off_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: LayoutNums.tinyGap,
        children: <Widget>[
          Text(tr(AppI10n.integrityMissingRoots)),
          for (final IntegrityRoot root in IntegrityRoot.values)
            if (missing.contains(root))
              Text(tr(_rootLabels[root]!), style: TextStyle(color: error)),
        ],
      ),
    );
  }
}

/// The one concern the pills have picked, grouped by library.
class _Findings extends StatelessWidget {
  const _Findings({
    super.key,
    required this.findings,
    required this.look,
    required this.onRepair,
    this.resolutions = const <IntegrityFinding, IntegrityResolution>{},
  });

  final List<IntegrityFinding> findings;
  final VerdictLook look;
  final IntegrityRepairHandler onRepair;
  final Map<IntegrityFinding, IntegrityResolution> resolutions;

  @override
  Widget build(BuildContext context) {
    final Map<IntegrityRoot, List<IntegrityFinding>> perRoot =
        <IntegrityRoot, List<IntegrityFinding>>{};
    for (final IntegrityFinding finding in findings) {
      perRoot
          .putIfAbsent(finding.root, () => <IntegrityFinding>[])
          .add(finding);
    }
    return ListView.builder(
      itemCount: findings.length,
      itemBuilder: (BuildContext context, int row) {
        final int index = row;
        final IntegrityFinding finding = findings[index];
        final IntegrityFinding? previous = index == 0
            ? null
            : findings[index - 1];
        final bool newGroup = previous == null || previous.root != finding.root;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (newGroup)
              Padding(
                padding: EdgeInsets.only(
                  top: index == 0 ? 0 : LayoutNums.sectionGap,
                  bottom: LayoutNums.smallGap,
                ),
                child: _GroupHeader(
                  root: finding.root,
                  findings: perRoot[finding.root]!,
                  look: look,
                  onRepair: onRepair,
                ),
              ),
            _FindingRow(
              finding: finding,
              look: look,
              onRepair: onRepair,
              resolution: resolutions[finding],
            ),
          ],
        );
      },
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.root,
    required this.findings,
    required this.look,
    required this.onRepair,
  });

  final IntegrityRoot root;
  final List<IntegrityFinding> findings;
  final VerdictLook look;
  final IntegrityRepairHandler onRepair;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: LayoutNums.smallGap,
      runSpacing: LayoutNums.tinyGap,
      children: <Widget>[
        Text(
          tr(_rootLabels[root]!),
          style: theme.meta.largeStyle.copyWith(fontWeight: FontWeight.w600),
        ),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: LayoutNums.smallGap,
            vertical: LayoutNums.tinyGap,
          ),
          decoration: BoxDecoration(
            color: look.colour.withValues(alpha: .1),
            borderRadius: BorderRadius.circular(LayoutNums.controlRadius),
          ),
          child: Text(
            '${findings.length}',
            style: theme.meta.captionStyle.copyWith(
              color: look.colour,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (look.repair case final IntegrityRepair repair)
          TextButton.icon(
            icon: const Icon(_resolveIcon, size: 16),
            onPressed: () => onRepair(context, repair, findings),
            style: TextButton.styleFrom(
              foregroundColor: look.colour,
              backgroundColor: look.colour.withValues(alpha: .1),
              padding: const EdgeInsets.symmetric(
                horizontal: LayoutNums.mediumGap,
                vertical: LayoutNums.smallGap,
              ),
              shape: const StadiumBorder(),
            ),
            label: Text(
              tr(AppI10n.integrityFixAll, args: <String>['${findings.length}']),
            ),
          ),
      ],
    );
  }
}

class _FindingRow extends StatelessWidget {
  const _FindingRow({
    required this.finding,
    required this.look,
    required this.onRepair,
    this.resolution,
  });

  final IntegrityFinding finding;
  final VerdictLook look;
  final IntegrityRepairHandler onRepair;
  final IntegrityResolution? resolution;

  static const double _height = 58;
  static const double _stripe = 4;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: LayoutNums.compactGap),
      child: Material(
        color: theme.inputDecorationTheme.fillColor,
        borderRadius: BorderRadius.circular(LayoutNums.controlRadius),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          height: _height,
          child: Row(
            children: <Widget>[
              Container(
                width: _stripe,
                height: double.infinity,
                color: look.colour,
              ),
              const SizedBox(width: LayoutNums.mediumGap),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Row(
                      spacing: LayoutNums.smallGap,
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            finding.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.meta.mediumStyle.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        // Which file, since "missing files" on its own sends
                        // the user into the folder to work it out.
                        if (resolution == null)
                          if (finding.missing case final String missing)
                            Text(
                              tr(
                                AppI10n.integrityMissingFile,
                                args: <String>[missing],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.meta.captionStyle.copyWith(
                                color: look.colour,
                              ),
                            ),
                        if (resolution case final IntegrityResolution value)
                          Text(
                            tr(_resolutionLabel(value)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.meta.captionStyle.copyWith(
                              color: look.colour,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                    Text(
                      finding.folder,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.meta.captionStyle,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: LayoutNums.contentGap),
              // Zero means unsized, not empty: a root holding no loadable
              // wallpaper is not walked. An empty folder has its own verdict.
              if (finding.bytes > 0)
                Text(formatSize(finding.bytes), style: theme.meta.captionStyle),
              const SizedBox(width: LayoutNums.contentGap),
              if (resolution == null)
                if (look.repair case final IntegrityRepair repair)
                  _ResolveButton(
                    colour: look.colour,
                    onPressed: () =>
                        onRepair(context, repair, <IntegrityFinding>[finding]),
                  ),
              const SizedBox(width: LayoutNums.smallGap),
              if (resolution == null)
                AppIconButton(
                  icon: Icons.folder_open_rounded,
                  tooltip: tr(AppI10n.integrityOpenFolder),
                  onPressed: () => browserFolder(finding.folder),
                )
              else
                Icon(Icons.check_circle_outline_rounded, color: look.colour),
              const SizedBox(width: LayoutNums.smallGap),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResolveButton extends StatelessWidget {
  const _ResolveButton({required this.colour, required this.onPressed});

  final Color colour;
  final VoidCallback onPressed;

  static const double _size = 36;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colour.withValues(alpha: .13),
        shape: BoxShape.circle,
      ),
      child: AppIconButton(
        icon: _resolveIcon,
        iconSize: 18,
        width: _size,
        height: _size,
        color: colour,
        tooltip: tr(AppI10n.integrityFixResolve),
        onPressed: onPressed,
      ),
    );
  }
}
