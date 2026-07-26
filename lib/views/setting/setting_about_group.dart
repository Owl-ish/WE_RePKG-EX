import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:we_repkg/constants/i10n.dart';
import 'package:we_repkg/constants/strings.dart';
import 'package:we_repkg/provider/system.dart';
import 'package:we_repkg/utils/pack.dart';
import 'package:we_repkg/widgets/link_text.dart';
import 'package:we_repkg/widgets/setting_info.dart';
import 'package:we_repkg/widgets/setting_label.dart';

class SettingAboutGroup extends ConsumerWidget {
  const SettingAboutGroup({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String repkgVersion = ref
        .watch(toolVersionProvider)
        .when(
          data: (version) => version ?? '—',
          loading: () => '…',
          error: (_, _) => '—',
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingLabel(tr(AppI10n.settingAboutLabel)),
        SettingInfo.text(
          title: tr(AppI10n.settingAboutOpenSourceLicense),
          content: AppStrings.license,
        ),
        _RepositoryVersionInfo(
          title: tr(AppI10n.settingAboutWeRepkgUrl),
          label: AppStrings.appRepoGithubLabel,
          uri: AppStrings.appRepoGithub,
          version: PackInfo.getVersion(),
        ),
        _RepositoryVersionInfo(
          title: tr(AppI10n.settingAboutRepkgUrl),
          label: AppStrings.repkgRepoLabel,
          uri: AppStrings.repkgRepo,
          version: repkgVersion,
        ),
        SettingInfo.custom(
          title: tr(AppI10n.settingAboutWeRepkgAuthor),
          child: LinkText(
            label: AppStrings.appOriginalRepoLabel,
            uri: AppStrings.appOriginalRepo,
          ),
        ),
        SettingInfo.custom(
          title: tr(AppI10n.settingAboutRepkgAuthor),
          child: LinkText(
            label: AppStrings.repkgOriginalRepoLabel,
            uri: AppStrings.repkgOriginalRepo,
          ),
        ),
      ],
    );
  }
}

class _RepositoryVersionInfo extends StatelessWidget {
  const _RepositoryVersionInfo({
    required this.title,
    required this.label,
    required this.uri,
    required this.version,
  });

  final String title;
  final String label;
  final String uri;
  final String version;

  @override
  Widget build(BuildContext context) {
    final TextStyle? textStyle = Theme.of(context).textTheme.bodyMedium;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 4,
        children: [
          Text('$title:', style: textStyle),
          LinkText(label: label, uri: uri),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('|  ${tr(AppI10n.settingAboutVersion)}: ', style: textStyle),
              Text(version, style: textStyle),
            ],
          ),
        ],
      ),
    );
  }
}
