import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:we_repkg/utils/storage.dart';

void main() {
  late Directory appData;

  setUp(
    () => appData = Directory.systemTemp.createTempSync('we_repkg_appdata'),
  );
  tearDown(() {
    if (appData.existsSync()) appData.deleteSync(recursive: true);
  });

  File current() =>
      File(path.join(appData.path, 'WeRePKG-EX', 'shared_preferences.json'));

  File legacy() => File(
    path.join(
      appData.path,
      'com.ilgnefz',
      'WeRePKG-EX',
      'shared_preferences.json',
    ),
  );

  void writeLegacy(String json) {
    legacy()
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(json);
  }

  test('old settings come across on the first launch', () async {
    writeLegacy('{"flutter.toolPath":"C:/RePKG.exe"}');

    expect(await StorageUtil.moveSettingsFile(appData.path), current().path);
    expect(current().readAsStringSync(), contains('C:/RePKG.exe'));
    // The original stays put, so an interrupted move cannot lose a config.
    expect(legacy().existsSync(), isTrue);
    // Staged under a temp name, then renamed. Nothing left beside it.
    expect(current().parent.listSync(), hasLength(1));
  });

  test('a file already in place wins', () async {
    writeLegacy('{"flutter.toolPath":"old"}');
    current()
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('{"flutter.toolPath":"current"}');

    await StorageUtil.moveSettingsFile(appData.path);

    expect(current().readAsStringSync(), contains('current'));
  });

  test('a second launch changes nothing', () async {
    writeLegacy('{"flutter.toolPath":"old"}');
    await StorageUtil.moveSettingsFile(appData.path);
    current().writeAsStringSync('{"flutter.toolPath":"newer"}');

    await StorageUtil.moveSettingsFile(appData.path);

    expect(current().readAsStringSync(), contains('newer'));
  });

  test('a fresh install reports the path without creating anything', () async {
    expect(await StorageUtil.moveSettingsFile(appData.path), current().path);
    expect(current().existsSync(), isFalse);
    // Nothing should conjure the old reverse-domain folder on a clean machine.
    expect(legacy().parent.existsSync(), isFalse);
  });
}
