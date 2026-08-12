import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The app's settings, in one indented JSON file the user can read.
///
/// `shared_preferences` writes one long line with no formatting option, and this
/// file is opened by hand often enough to be worth owning. Its values seed the
/// first run, so nothing is lost on the way over. The interface language is the
/// exception: easy_localization keeps its own, so a `locale` here does nothing.
class StorageUtil {
  static final StorageUtil _instance = StorageUtil._();
  factory StorageUtil() => _instance;

  StorageUtil._();

  static const String _file = 'settings.json';
  static const String _legacyFile = 'shared_preferences.json';

  /// Both come from the exe's version resource, windows/runner/Runner.rc, which
  /// is what Windows uses to pick the folder. The company was dropped, so the
  /// old path has a level the new one does not.
  static const String _folder = 'WeRePKG-EX';
  static const String _oldCompany = 'com.ilgnefz';

  static const JsonEncoder _json = JsonEncoder.withIndent('  ');

  static Map<String, Object> _values = <String, Object>{};
  static String? _filePath;

  /// Where writes go when the settings folder could not be found, which is
  /// where they went before this class owned a file. Without it a whole session
  /// of changes would be dropped at exit with nothing said.
  static SharedPreferences? _fallback;

  /// Writes run one after another, so two settings changed at once cannot
  /// interleave into half a file.
  static Future<void> _writing = Future<void>.value();

  /// Where the settings file is, for the settings page. Null off Windows and
  /// under test, where writes stay in memory.
  static String? get filePath => _filePath;

  static Future init() async {
    if (Platform.isWindows) await _findSettingsFile();
    _values = await _load();
  }

  /// [init] against a folder of the caller's choosing, since the real one comes
  /// from a plugin that is not registered under test.
  @visibleForTesting
  static Future<void> initAt(String appData) async {
    _filePath = await moveSettingsFile(appData);
    _values = await _load();
  }

  /// [init] with nowhere to write, which is what a failed folder lookup leaves.
  @visibleForTesting
  static Future<void> initWithoutFile() async {
    _filePath = null;
    _values = await _load();
  }

  static Future<void> _findSettingsFile() async {
    try {
      // path_provider, not %APPDATA%, because this has to land where
      // shared_preferences wrote and that is what it asks. The two differ under
      // a redirected profile.
      final Directory support = await getApplicationSupportDirectory();
      _filePath = await moveSettingsFile(support.parent.path);
    } catch (e) {
      // Not worth refusing to start over; the page just shows no path.
      debugPrint('Settings file location unavailable: $e');
    }
  }

  /// This app's own file if it has one, otherwise whatever `shared_preferences`
  /// holds, which is both the upgrade path and how a test seeds settings.
  static Future<Map<String, Object>> _load() async {
    final String? here = _filePath;
    if (here != null && await File(here).exists()) {
      try {
        final Object? parsed = json.decode(await File(here).readAsString());
        if (parsed is Map<String, dynamic>) {
          return <String, Object>{
            for (final MapEntry<String, dynamic> e in parsed.entries)
              if (e.value != null) e.key: e.value as Object,
          };
        }
      } catch (e) {
        debugPrint('Settings file unreadable: $e');
      }
      // Kept, never written over. One bad character in a hand edit would
      // otherwise cost every path and toggle the user has ever set, with the
      // only warning a debug line nobody sees in a release build.
      await _setAside(here);
    }
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    _fallback = here == null ? prefs : null;
    final Map<String, Object> seeded = <String, Object>{
      for (final String key in prefs.getKeys())
        if (prefs.get(key) case final Object value) key: value,
    };
    if (seeded.isNotEmpty) await _write(seeded);
    return seeded;
  }

  /// Where a file that would not parse is kept, beside the one that replaces it.
  static const String _badSuffix = '.unreadable';

  static Future<void> _setAside(String here) async {
    try {
      await File(here).rename('$here$_badSuffix');
    } catch (e) {
      debugPrint('Unreadable settings file kept where it is: $e');
    }
  }

  /// Brings the old settings file across, once, and says where the new one
  /// lives. [appData] is a temp dir under test.
  @visibleForTesting
  static Future<String> moveSettingsFile(String appData) async {
    final File now = File(path.join(appData, _folder, _legacyFile));
    final File old = File(
      path.join(appData, _oldCompany, _folder, _legacyFile),
    );

    // Copy, never move, never overwrite. The old file costs a few kilobytes and
    // is the difference between an interrupted migration and a lost config.
    if (!await now.exists() && await old.exists()) {
      await now.parent.create(recursive: true);
      // Stage then rename, atomic on NTFS. Copying straight to the destination
      // leaves truncated JSON there if the process dies mid-write.
      final File staged = File('${now.path}.part');
      await old.copy(staged.path);
      await staged.rename(now.path);
    }
    return path.join(appData, _folder, _file);
  }

  static Future<bool> _set(String key, Object value) async {
    if (_values[key] == value) return true;
    _values[key] = value;
    await switch (value) {
          final String v => _fallback?.setString(key, v),
          final bool v => _fallback?.setBool(key, v),
          final int v => _fallback?.setInt(key, v),
          _ => null,
        } ??
        Future<void>.value();
    await _write(_values);
    return true;
  }

  static Future<void> _write(Map<String, Object> values) {
    final String? here = _filePath;
    if (here == null) return Future<void>.value();
    // Sorted, so one changed setting shows as one changed line.
    final Map<String, Object> ordered = <String, Object>{
      for (final String key in values.keys.toList()..sort()) key: values[key]!,
    };
    _writing = _writing.then((_) async {
      try {
        final File file = File(here);
        await file.parent.create(recursive: true);
        // Named for this process: two copies of the app staging under one name
        // would rename each other's half-written file into place.
        final File part = File('$here.$pid.part');
        await part.writeAsString(_json.convert(ordered), flush: true);
        await part.rename(here);
      } catch (e) {
        debugPrint('Settings file not written: $e');
      }
    });
    return _writing;
  }

  static Future<bool> setString(String key, String value) => _set(key, value);

  // Typed rather than cast: this file is meant to be edited by hand, and a
  // number where a string belongs would otherwise throw during startup.
  static String? getString(String key) =>
      _values[key] is String ? _values[key] as String : null;

  static Future<bool> setBool(String key, bool value) => _set(key, value);

  static bool getBool(String key) => getNullBool(key) ?? false;

  static bool? getNullBool(String key) =>
      _values[key] is bool ? _values[key] as bool : null;

  static Future<bool> setInt(String key, int value) => _set(key, value);

  static int? getInt(String key) =>
      _values[key] is int ? _values[key] as int : null;

  /// An index into [values], for a setting stored as an enum position. Out of
  /// range reads as unset rather than throwing.
  static T? getEnum<T>(String key, List<T> values) {
    final int? index = getInt(key);
    return index != null && index >= 0 && index < values.length
        ? values[index]
        : null;
  }

  static Future<bool> remove(String key) async {
    if (_values.remove(key) == null) return true;
    await (_fallback?.remove(key) ?? Future<void>.value());
    await _write(_values);
    return true;
  }
}
