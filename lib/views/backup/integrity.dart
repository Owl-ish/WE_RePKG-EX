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
import 'package:we_repkg/widgets/scan_progress.dart';

/// Every repair on the tab wears this and says "resolve". What it will do is
/// the confirmation's job, since it is a sentence rather than a word.
const IconData _resolveIcon = Icons.build_outlined;

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
  IntegrityRepair repair,
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
    repair: IntegrityRepair.none,
  ),
  IntegrityVerdict.payloadMissing => (
    colour: colours.bad,
    label: AppI10n.integrityVerdictPayloadMissing,
    advice: AppI10n.integrityAdvicePayloadMissing,
    // The missing file is the wallpaper itself. Nothing here can conjure it.
    repair: IntegrityRepair.none,
  ),
  IntegrityVerdict.projectUnreadable => (
    colour: colours.bad,
    label: AppI10n.integrityVerdictProjectUnreadable,
    advice: AppI10n.integrityAdviceProjectUnreadable,
    // Overwriting a file the user hand-edited would throw away whatever they
    // were trying to do to it.
    repair: IntegrityRepair.none,
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
    repair: IntegrityRepair.none,
  ),
  IntegrityVerdict.shaderCacheOnly => (
    colour: colours.note,
    label: AppI10n.integrityVerdictShaderCacheOnly,
    advice: AppI10n.integrityAdviceShaderCacheOnly,
    repair: IntegrityRepair.none,
  ),
};

/// Every folder in all four roots, judged on whether Wallpaper Engine could
/// load it, with a repair only where the result is unambiguous.
class IntegrityView extends ConsumerWidget {
  const IntegrityView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return switch (ref.watch(integrityScanProvider)) {
      AsyncData<IntegrityReport>(:final IntegrityReport value) => _Report(
        report: value,
      ),
      AsyncError<IntegrityReport>(:final Object error) => Center(
        child: Text('${tr(AppI10n.integrityFailed)} $error'),
      ),
      _ => ScanProgress(label: tr(AppI10n.integrityChecking)),
    };
  }
}

class _Report extends ConsumerWidget {
  const _Report({required this.report});

  final IntegrityReport report;

  /// One pill per concern that holds something: a row of zeroes is a list of
  /// things that did not happen.
  List<Widget> _pills(
    WidgetRef ref,
    Map<IntegrityVerdict, int> counts,
    IntegrityVerdict shown,
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
          on: verdict == shown,
          // Every one of these is worth a look, so a glow apiece would be a
          // wall of them.
          nags: false,
          onPressed: () =>
              ref.read(integrityShownProvider.notifier).show(verdict),
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
    final IntegrityVerdict shown = shownVerdict(
      ref.watch(integrityShownProvider),
      counts,
    );

    return Padding(
      padding: const EdgeInsets.only(top: LayoutNums.contentGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: LayoutNums.contentGap,
        children: <Widget>[
          _Summary(
            checked: checked,
            found: report.findings.length,
            onRecheck: () => ref.invalidate(integrityScanProvider),
          ),
          if (report.missing.isNotEmpty) _MissingRoots(missing: report.missing),
          if (report.findings.isNotEmpty)
            PillRow(children: _pills(ref, counts, shown, colours)),
          Expanded(
            child: report.findings.isNotEmpty
                ? _Findings(
                    // Keyed, or scrolling deep into a long concern leaves the
                    // next one part way down.
                    key: ValueKey<IntegrityVerdict>(shown),
                    findings: report.findings
                        .where((IntegrityFinding f) => f.verdict == shown)
                        .toList(),
                    look: _verdictLook(shown, colours),
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

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
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
              Icon(
                Icons.health_and_safety_outlined,
                size: 20,
                color: theme.primaryColor,
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
          Text(tr(AppI10n.integrityAbout), style: theme.meta.captionStyle),
          Text(
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
            style: theme.meta.mediumStyle,
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
    return _Note(
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

/// A tinted line in the colour of whatever it is about. Kept low: it sits under
/// a pill, and a deep panel out-shouted the thing it was explaining.
class _Note extends StatelessWidget {
  const _Note({required this.colour, required this.icon, required this.child});

  final Color colour;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: LayoutNums.mediumGap,
        vertical: LayoutNums.smallGap,
      ),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(LayoutNums.surfaceRadius),
        border: Border.all(color: colour.withValues(alpha: .3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: LayoutNums.smallGap,
        children: <Widget>[
          Icon(icon, size: 16, color: colour),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// The one concern the pills have picked, under a line saying what to do about
/// it, with a heading per library since the findings arrive sorted by that.
class _Findings extends StatelessWidget {
  const _Findings({super.key, required this.findings, required this.look});

  final List<IntegrityFinding> findings;
  final VerdictLook look;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Map<IntegrityRoot, List<IntegrityFinding>> perRoot =
        <IntegrityRoot, List<IntegrityFinding>>{};
    for (final IntegrityFinding finding in findings) {
      perRoot
          .putIfAbsent(finding.root, () => <IntegrityFinding>[])
          .add(finding);
    }
    return ListView.builder(
      // The advice sits in the list rather than above it, so a long one
      // scrolls away instead of eating the window.
      itemCount: findings.length + 1,
      itemBuilder: (BuildContext context, int row) {
        if (row == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: LayoutNums.mediumGap),
            child: _Note(
              colour: look.colour,
              icon: Icons.info_outline_rounded,
              // The tab's own text colour rather than the muted one the paths
              // wear: this is the line the user is here to read.
              child: Text(tr(look.advice)),
            ),
          );
        }
        final int index = row - 1;
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
                  top: index == 0 ? LayoutNums.tinyGap : LayoutNums.sectionGap,
                  bottom: LayoutNums.smallGap,
                ),
                child: Row(
                  spacing: LayoutNums.smallGap,
                  children: <Widget>[
                    Text(
                      tr(_rootLabels[finding.root]!),
                      style: theme.meta.mediumStyle.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '${perRoot[finding.root]!.length}',
                      style: theme.meta.captionStyle,
                    ),
                    // The whole library at once, since these arrive in dozens
                    // and every one of them wants the same answer.
                    if (look.repair != IntegrityRepair.none)
                      TextButton.icon(
                        icon: const Icon(_resolveIcon, size: 16),
                        onPressed: () => applyIntegrityRepair(
                          context,
                          look.repair,
                          perRoot[finding.root]!,
                        ),
                        label: Text(
                          tr(
                            AppI10n.integrityFixAll,
                            args: <String>['${perRoot[finding.root]!.length}'],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            _FindingRow(finding: finding, look: look),
          ],
        );
      },
    );
  }
}

class _FindingRow extends StatelessWidget {
  const _FindingRow({required this.finding, required this.look});

  final IntegrityFinding finding;
  final VerdictLook look;

  static const double _height = 52;
  static const double _stripe = 3;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: LayoutNums.compactGap),
      child: Material(
        color: theme.inputDecorationTheme.fillColor,
        borderRadius: BorderRadius.circular(LayoutNums.controlRadius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => browserFolder(finding.folder),
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
                              style: theme.meta.mediumStyle,
                            ),
                          ),
                          // Which file, since "missing files" on its own sends
                          // the user into the folder to work it out.
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
                  Text(
                    formatSize(finding.bytes),
                    style: theme.meta.captionStyle,
                  ),
                const SizedBox(width: LayoutNums.contentGap),
                if (look.repair != IntegrityRepair.none)
                  AppIconButton(
                    icon: _resolveIcon,
                    tooltip: tr(AppI10n.integrityFixResolve),
                    onPressed: () => applyIntegrityRepair(
                      context,
                      look.repair,
                      <IntegrityFinding>[finding],
                    ),
                  ),
                AppIconButton(
                  icon: Icons.folder_open_rounded,
                  tooltip: tr(AppI10n.integrityOpenFolder),
                  onPressed: () => browserFolder(finding.folder),
                ),
                const SizedBox(width: LayoutNums.smallGap),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
