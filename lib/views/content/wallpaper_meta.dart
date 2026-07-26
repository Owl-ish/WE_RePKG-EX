import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:we_repkg/config/custom_theme.dart';
import 'package:we_repkg/constants/content_rating.dart';
import 'package:we_repkg/constants/i10n.dart';
import 'package:we_repkg/models/wallpaper.dart';
import 'package:we_repkg/utils/tool.dart';
import 'package:we_repkg/widgets/copy.dart';

String ratingText(String rating) {
  switch (rating) {
    case ContentRating.mature:
      return tr(AppI10n.homeFilterRatingMature);
    case ContentRating.questionable:
      return tr(AppI10n.homeFilterRatingQuestionable);
    // A project.json can carry an unrecognised contentrating or none at all, and
    // filterWallpaperList already counts anything that isn't mature or
    // questionable as all ages. Label it the same way rather than echoing a raw
    // value the filter checkboxes don't recognise.
    default:
      return tr(AppI10n.homeFilterRatingEveryone);
  }
}

/// Every field of a wallpaper as label/value rows, shared by the hover card and
/// the detail dialog so the two can't drift apart.
///
/// [copyable] adds copy buttons to the id and the title. The hover card leaves
/// them off: it disappears the moment the pointer leaves the tile, so a button
/// inside it can never be reached.
class WallpaperMeta extends StatelessWidget {
  const WallpaperMeta({
    super.key,
    required this.wallpaper,
    this.copyable = false,
    this.showTitle = true,
    this.foreground,
  });

  final WallpaperInfo wallpaper;
  final bool copyable;
  final bool showTitle;

  /// Overrides every text and icon colour. The detail dialog draws this over a
  /// frosted wallpaper rather than a theme surface, so it picks a colour from
  /// what is actually behind the panel; the theme's fixed grey would vanish on
  /// a dark image and glare on a pale one.
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final MetaTheme meta = theme.extension<MetaTheme>()!;
    // A halo in the opposite colour. The glass panel is deliberately sheer, so
    // a blurred wallpaper can still leave a patch that matches the text colour
    // closely enough to swallow a letter; the halo keeps the edge regardless.
    final List<Shadow>? halo = foreground == null
        ? null
        : [
            Shadow(
              color:
                  (foreground!.computeLuminance() > .5
                          ? Colors.black
                          : Colors.white)
                      .withValues(alpha: .5),
              blurRadius: 6,
            ),
          ];
    // Sizes still come from the theme; only the colour is overridden.
    final TextStyle body = foreground == null
        ? meta.mediumStyle
        : meta.mediumStyle.copyWith(color: foreground, shadows: halo);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showTitle) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                child: Text(
                  wallpaper.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontSize: 16,
                    color: foreground,
                    shadows: halo,
                  ),
                ),
              ),
              if (copyable) CopyBtn(text: wallpaper.title, color: foreground),
            ],
          ),
          const SizedBox(height: 8),
        ],
        _MetaRow(
          label: tr(AppI10n.homeType),
          value: typeText(wallpaper.type),
          style: body,
        ),
        _MetaRow(
          label: tr(AppI10n.homeSize),
          value: formatSize(wallpaper.size),
          style: body,
        ),
        _MetaRow(
          label: tr(AppI10n.homeRating),
          value: ratingText(wallpaper.contentRating),
          style: body,
        ),
        _MetaRow(
          label: 'ID',
          value: wallpaper.id,
          style: body,
          trailing: copyable
              ? CopyBtn(text: wallpaper.id, size: 12, color: foreground)
              : null,
        ),
        _MetaRow(
          label: tr(AppI10n.homeCreatedDate),
          value: wallpaper.createTime.toString().substring(0, 19),
          style: body,
        ),
        if (wallpaper.updateTime != null)
          _MetaRow(
            label: tr(AppI10n.homeUpdateDate),
            value: formattedTime(wallpaper.updateTime),
            style: body,
          ),
        if (wallpaper.tags.isNotEmpty)
          _MetaRow(
            label: tr(AppI10n.homeTags),
            value: wallpaper.tags.join(', '),
            style: body,
            maxLines: 3,
          ),
      ],
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({
    required this.label,
    required this.value,
    required this.style,
    this.trailing,
    this.maxLines = 1,
  });

  final String label;
  final String value;
  final TextStyle style;
  final Widget? trailing;
  final int maxLines;

  /// Fixed so the values line up into a column instead of stepping in and out
  /// with the length of each label. Wide enough for "Creation date", the
  /// longest of them, which ellipsized at 76.
  static const double _labelWidth = 96;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: _labelWidth,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style.copyWith(
                fontSize: style.fontSize! - 1,
                // Dimmer than the value it labels, but not so dim that it drops
                // out over the detail dialog's sheer panel.
                color: style.color?.withValues(alpha: .78),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: maxLines,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
