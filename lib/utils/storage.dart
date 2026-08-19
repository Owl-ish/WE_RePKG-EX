import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Owns readable `settings.json` persistence and legacy SharedPreferences import.
class StorageUtil {
  static final StorageUtil _instance = StorageUtil._();
  factory StorageUtil() => _instance;

  StorageUtil._();

  static const String _file = 'settings.json';
  static const String _legacyFile = 'shared_preferences.json';
  static const String _folder = 'WeRePKG-EX';
  static const String _olderFolder = 'WeRePKG';
  static const String _oldCompany = 'com.ilgnefz';

  static const JsonEncoder _json = JsonEncoder.withIndent('  ');

  static Map<String, Object> _values = <String, Object>{};
  static String? _filePath;

  /// Where writes go when the settings folder could not be found
  static SharedPreferences? _fallback;

  /// Writes run one after another, so two settings changed at once cannot
  /// interleave into half a file.
  static Future<void> _writing = Future<void>.value();
  static String? get filePath => _filePath;

  static Future init() async {
    if (Platform.isWindows) await _findSettingsFile();
    _values = await _load();
  }

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
      // Let path_provider resolve the Windows support directory; its parent is
      // the roaming app-data root used for legacy migration.
      final Directory support = await getApplicationSupportDirectory();
      _filePath = await moveSettingsFile(support.parent.path);
    } catch (e) {
      // Missing support-directory access must not block startup;
      // SharedPreferences remains the fallback.
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

  /// Preserves an unreadable file when possible without blocking startup.
  static Future<void> _setAside(String here) async {
    try {
      await File(here).rename('$here$_badSuffix');
    } catch (e) {
      debugPrint('Unreadable settings file kept where it is: $e');
    }
  }

  /// Copies a legacy SharedPreferences file into the current app folder once.
  ///
  /// Returns the `settings.json` path. [appData] is a temp directory under test.
  @visibleForTesting
  static Future<String> moveSettingsFile(String appData) async {
    final File now = File(path.join(appData, _folder, _legacyFile));
    final List<File> oldFiles = <File>[
      File(path.join(appData, _oldCompany, _folder, _legacyFile)),
      File(path.join(appData, _oldCompany, _olderFolder, _legacyFile)),
    ];

    // Copy, never move or overwrite. Prefer the WeRePKG-EX legacy folder when
    // both exist so a pre-rename config cannot replace newer settings. Keeping
    // the source makes an interrupted migration recoverable.
    if (!await now.exists()) {
      for (final File old in oldFiles) {
        if (!await old.exists()) continue;
        await now.parent.create(recursive: true);
        // Stage then rename, atomic on NTFS. Copying straight to the destination
        // leaves truncated JSON there if the process dies mid-write.
        final File staged = File('${now.path}.part');
        await old.copy(staged.path);
        await staged.rename(now.path);
        break;
      }
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
        // Keep in-memory settings usable even when persistence fails.
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
