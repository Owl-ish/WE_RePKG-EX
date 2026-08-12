import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:we_repkg/utils/storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory appData;

  setUp(() {
    appData = Directory.systemTemp.createTempSync('we_repkg_appdata');
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });
  tearDown(() {
    if (appData.existsSync()) appData.deleteSync(recursive: true);
  });

  File settings() =>
      File(path.join(appData.path, 'WeRePKG-EX', 'settings.json'));

  File plugin() =>
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

  group('the move from the old install folder', () {
    test('old settings come across on the first launch', () async {
      writeLegacy('{"flutter.toolPath":"C:/RePKG.exe"}');

      expect(await StorageUtil.moveSettingsFile(appData.path), settings().path);
      expect(plugin().readAsStringSync(), contains('C:/RePKG.exe'));
      // The original stays put, so an interrupted move cannot lose a config.
      expect(legacy().existsSync(), isTrue);
      // Staged under a temp name, then renamed. Nothing left beside it.
      expect(plugin().parent.listSync(), hasLength(1));
    });

    test('a file already in place wins', () async {
      writeLegacy('{"flutter.toolPath":"old"}');
      plugin()
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('{"flutter.toolPath":"current"}');

      await StorageUtil.moveSettingsFile(appData.path);

      expect(plugin().readAsStringSync(), contains('current'));
    });

    test('a half-copied file left behind is replaced', () async {
      writeLegacy('{"flutter.toolPath":"C:/RePKG.exe"}');
      // What an interrupted copy leaves: truncated JSON under the staging name.
      final File stale = File('${plugin().path}.part');
      stale
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('{"flutter.tool');

      await StorageUtil.moveSettingsFile(appData.path);

      expect(plugin().readAsStringSync(), contains('C:/RePKG.exe'));
      expect(stale.existsSync(), isFalse);
    });

    test('a fresh install reports the path without creating anything', () async {
      expect(await StorageUtil.moveSettingsFile(appData.path), settings().path);
      expect(plugin().existsSync(), isFalse);
      // Nothing should conjure the old reverse-domain folder on a clean machine.
      expect(legacy().parent.existsSync(), isFalse);
    });
  });

  group('the settings file', () {
    test('is written indented, sorted, and one key per line', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'toolPath': r'C:\RePKG.exe',
        'backupRoot': r'D:\backup',
      });

      await StorageUtil.initAt(appData.path);

      expect(settings().readAsStringSync(), '''
{
  "backupRoot": "D:\\\\backup",
  "toolPath": "C:\\\\RePKG.exe"
}''');
    });

    // The upgrade path: everything the plugin held has to arrive intact, or the
    // user's paths and toggles reset on the version that stops using it.
    test('takes over what shared_preferences held', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'toolPath': 'tool',
        'sortType': 2,
        'replaceFile': true,
      });

      await StorageUtil.initAt(appData.path);

      expect(StorageUtil.getString('toolPath'), 'tool');
      expect(StorageUtil.getInt('sortType'), 2);
      expect(StorageUtil.getBool('replaceFile'), isTrue);
    });

    test('is what the next launch reads, not the plugin', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'toolPath': 'first',
      });
      await StorageUtil.initAt(appData.path);
      await StorageUtil.setString('toolPath', 'second');

      // As if the app restarted with the plugin still holding the old value.
      SharedPreferences.setMockInitialValues(<String, Object>{
        'toolPath': 'first',
      });
      await StorageUtil.initAt(appData.path);

      expect(StorageUtil.getString('toolPath'), 'second');
    });

    test('a removed setting leaves the file', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'toolPath': 'tool',
        'acfPath': 'acf',
      });
      await StorageUtil.initAt(appData.path);

      await StorageUtil.remove('acfPath');

      expect(settings().readAsStringSync(), isNot(contains('acfPath')));
      expect(StorageUtil.getString('toolPath'), 'tool');
    });

    // A file cut short by a killed write would otherwise take every setting
    // with it, and the app would come up with no paths at all.
    test('a corrupt file falls back rather than throwing', () async {
      settings()
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('{"toolPath": "half');
      SharedPreferences.setMockInitialValues(<String, Object>{
        'toolPath': 'from the plugin',
      });

      await StorageUtil.initAt(appData.path);

      expect(StorageUtil.getString('toolPath'), 'from the plugin');
    });

    // The file is meant to be edited by hand, so one bad character must not be
    // the end of every path and toggle the user ever set.
    test('a corrupt file is kept, not written over', () async {
      settings()
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('{"toolPath": "half');

      await StorageUtil.initAt(appData.path);
      await StorageUtil.setString('toolPath', 'new');

      expect(
        File('${settings().path}.unreadable').readAsStringSync(),
        '{"toolPath": "half',
      );
      expect(settings().readAsStringSync(), contains('new'));
    });

    // Before this class owned a file the plugin still wrote one. Without the
    // fallback a whole session of changes would go at exit with nothing said.
    test('with nowhere to write, settings still persist', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await StorageUtil.initWithoutFile();

      await StorageUtil.setString('toolPath', 'tool');
      await StorageUtil.setInt('sortType', 1);

      final SharedPreferences prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('toolPath'), 'tool');
      expect(prefs.getInt('sortType'), 1);
    });

    // Hand-edited values reach an enum index at startup, where the old lookup
    // threw before the app could draw anything.
    test('a value of the wrong type or range reads as unset', () async {
      settings()
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('{"toolPath": 7, "sortType": 99}');

      await StorageUtil.initAt(appData.path);

      expect(StorageUtil.getString('toolPath'), isNull);
      expect(StorageUtil.getEnum('sortType', <String>['a', 'b']), isNull);
    });

    test('writes go through a part file, never over the live one', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{'toolPath': 'a'});
      await StorageUtil.initAt(appData.path);

      await StorageUtil.setString('toolPath', 'b');

      expect(File('${settings().path}.part').existsSync(), isFalse);
      expect(settings().readAsStringSync(), contains('"b"'));
    });
  });
}
