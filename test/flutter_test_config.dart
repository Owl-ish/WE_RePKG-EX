import 'dart:async';

import 'package:easy_localization/easy_localization.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  // Widget tests intentionally render localization keys directly as stable
  // selectors. Translation-file coverage lives in i10n_keys_test.dart, so
  // Easy Localization logging is noise here rather than coverage.
  EasyLocalization.logger.enableBuildModes = [];
  await testMain();
}
