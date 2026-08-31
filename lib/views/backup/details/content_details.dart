// Public entry point for Backup content-comparison and Update details.

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:we_repkg/config/theme_extensions.dart';
import 'package:we_repkg/constants/i10n.dart';
import 'package:we_repkg/cores/backup.dart';
import 'package:we_repkg/utils/backup_diff.dart';
import 'package:we_repkg/views/backup/details/backup_update_selection.dart';
import 'package:we_repkg/views/backup/details/detail_layout.dart';
import 'package:we_repkg/views/backup/details/sync_details.dart';
import 'package:we_repkg/views/backup/details/update_file_changes.dart';
import 'package:we_repkg/widgets/file_tree_panel.dart';

export 'backup_update_selection.dart';
export 'detail_layout.dart';

// These renderers collaborate through private helpers. Keeping them in one
// library avoids widening those helpers into public APIs.
part 'file_difference_tree.dart';
part 'update_plan_details.dart';
