// Public library facade for Backup content comparison and selective Update UI.
// The part files keep the tightly coupled private renderers in one Dart library
// without exposing implementation-only helpers or creating import cycles.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:we_repkg/models/wallpaper.dart';
import 'package:we_repkg/views/content/detail_dialog.dart';

import 'package:easy_localization/easy_localization.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:we_repkg/config/theme_extensions.dart';
import 'package:we_repkg/constants/i10n.dart';
import 'package:we_repkg/constants/wallpaper_files.dart';
import 'package:we_repkg/cores/backup.dart';
import 'package:we_repkg/actions/wallpaper_actions.dart';
import 'package:we_repkg/cores/scene_pkg_inspection.dart';
import 'package:we_repkg/cores/toast.dart';
import 'package:we_repkg/utils/backup_diff.dart';
import 'package:we_repkg/views/backup/details/backup_update_selection.dart';
import 'package:we_repkg/views/backup/details/detail_layout.dart';
import 'package:we_repkg/views/backup/details/sync_details.dart';
import 'package:we_repkg/widgets/confirm_dialog.dart';
import 'package:we_repkg/widgets/app_dialog_surface.dart';
import 'package:we_repkg/widgets/file_compare.dart';
import 'package:we_repkg/widgets/file_tree_panel.dart';
import 'package:we_repkg/widgets/linked_scroll.dart';

export 'package:we_repkg/views/backup/details/backup_update_selection.dart';
export 'package:we_repkg/views/backup/details/detail_layout.dart';

part 'update_plan_details.dart';
part 'paired_update_tree.dart';
part 'file_difference_tree.dart';
part 'file_comparison_rows.dart';
part 'scene_pkg_details.dart';
