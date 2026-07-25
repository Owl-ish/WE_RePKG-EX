import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:we_repkg/constants/strings.dart';

/// The RePKG version lives in two places that cannot see each other: the tag the
/// release workflow downloads, and the string the About screen shows. Bumping
/// one and forgetting the other ships a build whose About screen lies about
/// which RePKG is inside it, and nothing at runtime would notice.
///
/// REPKG_SHA256 needs no test here: the workflow verifies it against the
/// downloaded archive on every release build and fails loudly on a mismatch.
void main() {
  test('the release workflow ships the RePKG version About claims', () {
    final workflow = File('.github/workflows/release.yml').readAsStringSync();

    final match = RegExp(r'REPKG_TAG:\s*(\S+)').firstMatch(workflow);
    expect(match, isNotNull, reason: 'REPKG_TAG is missing from release.yml');

    expect(
      match!.group(1),
      'v${AppStrings.repkgVersion}',
      reason:
          'REPKG_TAG in .github/workflows/release.yml and '
          'AppStrings.repkgVersion in lib/constants/strings.dart must move '
          'together. Update REPKG_SHA256 in the same commit, since a new tag '
          'means a new archive.',
    );
  });
}
