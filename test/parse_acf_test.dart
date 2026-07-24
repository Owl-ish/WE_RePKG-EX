import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:we_repkg/utils/parse_acf.dart';

const _validAcf = '''
"AppWorkshop"
{
  "appid"  "431960"
  "WorkshopItemsInstalled"
  {
    "111"
    {
      "size"  "2048"
      "timeupdated"  "1700000000"
    }
    "222"
    {
      "size"  "4096"
      "timeupdated"  "1700000001"
    }
  }
}
''';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('we_repkg_acf'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<Map<String, dynamic>> parseContent(String content) {
    final f = File(p.join(tmp.path, 'test.acf'))..writeAsStringSync(content);
    return parseAcf(f.path);
  }

  group('parseAcf', () {
    test('parses a valid workshop ACF into a nested map', () async {
      final result = await parseContent(_validAcf);
      final installed =
          result['AppWorkshop']['WorkshopItemsInstalled'] as Map;
      expect(installed.keys, containsAll(['111', '222']));
      expect(installed['111']['size'], '2048');
      expect(installed['111']['timeupdated'], '1700000000');
    });

    test('throws on a missing closing brace', () async {
      await expectLater(
        parseContent('"AppWorkshop"\n{\n  "appid"  "431960"\n'),
        throwsFormatException,
      );
    });

    test('throws on a missing closing quote', () async {
      await expectLater(parseContent('"AppWorkshop'), throwsFormatException);
    });
  });

  group('convertToAcfInfoList', () {
    test('maps WorkshopItemsInstalled entries to AcfInfo', () async {
      final parsed = await parseContent(_validAcf);
      final list = convertToAcfInfoList(parsed);
      expect(list.length, 2);
      final byId = {for (final a in list) a.id: a};
      expect(byId['111']!.size, 2048);
      expect(byId['111']!.time, 1700000000);
      expect(byId['222']!.size, 4096);
    });

    test('returns empty for a map without AppWorkshop', () {
      expect(convertToAcfInfoList({'Other': <String, dynamic>{}}), isEmpty);
    });

    test('returns empty for an empty map', () {
      expect(convertToAcfInfoList({}), isEmpty);
    });
  });
}
