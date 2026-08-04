import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StorageUtil {
  static final StorageUtil _instance = StorageUtil._();
  factory StorageUtil() => _instance;
  static late SharedPreferences _prefs;

  StorageUtil._();

  static const String _file = 'shared_preferences.json';

  /// Both come from the exe's version resource, windows/runner/Runner.rc, which
  /// is what Windows uses to pick the folder. The company was dropped, so the
  /// old path has a level the new one does not.
  static const String _folder = 'WeRePKG-EX';
  static const String _oldCompany = 'com.ilgnefz';

  static String? _filePath;

  /// Where the settings file is, for the settings page. Null off Windows.
  static String? get filePath => _filePath;

  static Future init() async {
    if (Platform.isWindows) await _findSettingsFile();
    _prefs = await SharedPreferences.getInstance();
  }

  static Future<void> _findSettingsFile() async {
    try {
      // path_provider, not %APPDATA%, because this has to land where
      // shared_preferences actually writes and that is what it asks. The two
      // differ under a redirected profile.
      final Directory support = await getApplicationSupportDirectory();
      _filePath = await moveSettingsFile(support.parent.path);
    } catch (e) {
      // Not worth refusing to start over; the page just shows no path.
      debugPrint('Settings file location unavailable: $e');
    }
  }

  /// Brings the old settings file across, once, and says where it now lives.
  /// Must run before the first [SharedPreferences.getInstance], which reads the
  /// file and caches it. [appData] is a temp dir under test.
  @visibleForTesting
  static Future<String> moveSettingsFile(String appData) async {
    final File now = File(path.join(appData, _folder, _file));
    final File old = File(path.join(appData, _oldCompany, _folder, _file));

    // Copy, never move, never overwrite. The old file costs a few kilobytes and
    // is the difference between an interrupted migration and a lost config.
    if (!await now.exists() && await old.exists()) {
      await now.parent.create(recursive: true);
      // Stage then rename, atomic on NTFS. Copying straight to the destination
      // leaves truncated JSON there if the process dies mid-write, and
      // shared_preferences parses that with no error handling.
      final File staged = File('${now.path}.part');
      await old.copy(staged.path);
      await staged.rename(now.path);
    }
    return now.path;
  }

  static Future<bool> setString(String key, String value) {
    return _prefs.setString(key, value);
  }

  static String? getString(String key) => _prefs.getString(key);

  static Future<bool> setBool(String key, bool value) =>
      _prefs.setBool(key, value);

  static bool getBool(String key) => _prefs.getBool(key) ?? false;

  static bool? getNullBool(String key) => _prefs.getBool(key);

  static Future<bool> setInt(String key, int value) =>
      _prefs.setInt(key, value);

  static int? getInt(String key) => _prefs.getInt(key);

  static Future<bool> remove(String key) => _prefs.remove(key);
}
