import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:we_repkg/constants/i10n.dart';
import 'package:we_repkg/constants/nums.dart';
import 'package:we_repkg/cores/base.dart';
import 'package:we_repkg/cores/integrity.dart';
import 'package:we_repkg/provider/integrity.dart';
import 'package:we_repkg/utils/wallpaper_integrity.dart';
import 'package:we_repkg/utils/tool.dart';
import 'package:we_repkg/widgets/app_icon_button.dart';

/// Beside their enums rather than in `models/enums.dart`, which would drag
/// `dart:io` into every widget that imports it. `BackupFolder`'s labels sit in
/// the backup view for the same reason.
const Map<IntegrityRoot, String> _rootLabels = <IntegrityRoot, String>{
  IntegrityRoot.liveWorkshop: AppI10n.integrityRootLiveWorkshop,
  IntegrityRoot.liveMyProjects: AppI10n.integrityRootLiveMyProjects,
  IntegrityRoot.backupWorkshop: AppI10n.integrityRootBackupWorkshop,
  IntegrityRoot.backupMyProjects: AppI10n.integrityRootBackupMyProjects,
};

/// A switch rather than a map, so the next verdict added fails the analyzer
/// instead of the app.
String _verdictLabel(IntegrityVerdict verdict) => switch (verdict) {
  IntegrityVerdict.sound => AppI10n.integrityVerdictSound,
  IntegrityVerdict.packedSceneNoProject =>
    AppI10n.integrityVerdictPackedSceneNoProject,
  IntegrityVerdict.unpackedSceneNoProject =>
    AppI10n.integrityVerdictUnpackedSceneNoProject,
  IntegrityVerdict.mediaOnly => AppI10n.integrityVerdictMediaOnly,
  IntegrityVerdict.payloadMissing => AppI10n.integrityVerdictPayloadMissing,
  IntegrityVerdict.projectUnreadable =>
    AppI10n.integrityVerdictProjectUnreadable,
  IntegrityVerdict.empty => AppI10n.integrityVerdictEmpty,
  IntegrityVerdict.shaderCacheOnly => AppI10n.integrityVerdictShaderCacheOnly,
};

/// Every folder in all four roots, judged on whether Wallpaper Engine could
/// load it. Read-only: the fix is manual, so each row opens its folder.
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
      _ => const Center(child: CircularProgressIndicator()),
    };
  }
}

class _Report extends ConsumerWidget {
  const _Report({required this.report});

  final IntegrityReport report;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final int checked = report.scanned.values.fold(
      0,
      (int sum, int n) => sum + n,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            spacing: 12,
            children: <Widget>[
              Text(tr(AppI10n.integrityScanned, args: <String>['$checked'])),
              TextButton.icon(
                onPressed: () => ref.invalidate(integrityScanProvider),
                icon: const Icon(Icons.refresh_rounded),
                label: Text(tr(AppI10n.integrityRecheck)),
              ),
            ],
          ),
        ),
        if (report.missing.isNotEmpty) _MissingRoots(missing: report.missing),
        Expanded(
          child: report.findings.isNotEmpty
              ? _Findings(findings: report.findings)
              // Nothing read is not a clean bill of health, and the roots above
              // already say why.
              : checked == 0
              ? const SizedBox.shrink()
              : const _Clean(),
        ),
      ],
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
        spacing: 12,
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
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

/// One heading per root and verdict, since the findings arrive sorted by both.
class _Findings extends StatelessWidget {
  const _Findings({required this.findings});

  final List<IntegrityFinding> findings;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return ListView.builder(
      itemCount: findings.length,
      itemBuilder: (BuildContext context, int index) {
        final IntegrityFinding finding = findings[index];
        final IntegrityFinding? previous = index == 0
            ? null
            : findings[index - 1];
        final bool newGroup =
            previous == null ||
            previous.root != finding.root ||
            previous.verdict != finding.verdict;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (newGroup)
              Padding(
                padding: EdgeInsets.only(top: index == 0 ? 0 : 16, bottom: 4),
                child: Text(
                  '${tr(_rootLabels[finding.root]!)}  •  '
                  '${tr(_verdictLabel(finding.verdict))}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            _FindingRow(finding: finding),
          ],
        );
      },
    );
  }
}

class _FindingRow extends StatelessWidget {
  const _FindingRow({required this.finding});

  final IntegrityFinding finding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              finding.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Zero means unsized, not empty: a root holding no loadable wallpaper
          // is not walked. An empty folder has its own verdict.
          if (finding.bytes > 0)
            Text(
              formatSize(finding.bytes),
              style: TextStyle(color: Colors.grey),
            ),
          const SizedBox(width: LayoutNums.contentGap),
          AppIconButton(
            icon: Icons.folder_open_rounded,
            tooltip: tr(AppI10n.integrityOpenFolder),
            onPressed: () => browserFolder(finding.folder),
          ),
        ],
      ),
    );
  }
}
