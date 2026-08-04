import 'dart:io';

import 'package:we_repkg/models/acf.dart';

/// 解析ACF格式文件
///
/// [acfPath] ACF文件路径
/// 返回解析后的Map对象
Future<Map<String, dynamic>> parseAcf(String acfPath) async {
  String content = await File(acfPath).readAsString();
  return _parseAcfContent(content);
}

/// 解析ACF内容
Map<String, dynamic> _parseAcfContent(String content) {
  final result = <String, dynamic>{};
  int i = _skipWhitespace(content, 0);

  // 解析顶层对象键
  if (i < content.length && content[i] == '"') {
    final key = _readString(content, i);
    i = _skipWhitespace(content, key.endIndex);

    // 解析顶层对象的值
    if (i < content.length && content[i] == '{') {
      final objResult = _parseObject(content, i + 1);
      result[key.value] = objResult.value;
    }
  }

  return result;
}

class ParseResult {
  final dynamic value;
  final int endIndex;

  ParseResult(this.value, this.endIndex);
}

/// 解析对象
ParseResult _parseObject(String content, int startIndex) {
  final map = <String, dynamic>{};
  int i = startIndex;

  while (i < content.length) {
    i = _skipWhitespace(content, i);

    if (i < content.length && content[i] == '}') {
      return ParseResult(map, i + 1);
    }

    if (i < content.length && content[i] == '"') {
      final key = _readString(content, i);
      i = _skipWhitespace(content, key.endIndex);

      if (i < content.length) {
        if (content[i] == '"') {
          final value = _readString(content, i);
          map[key.value] = value.value;
          i = value.endIndex;
        } else if (content[i] == '{') {
          final objResult = _parseObject(content, i + 1);
          map[key.value] = objResult.value;
          i = objResult.endIndex;
        } else {
          // Numbers and bare tokens are not kept, so skip to whatever comes
          // next rather than parsing them.
          while (i < content.length &&
              content[i] != '"' &&
              content[i] != '{' &&
              content[i] != '}') {
            i++;
          }
          continue;
        }
      }
    } else {
      i++;
    }
  }

  // 走到这里说明没有遇到收尾的 '}'，文件被截断了
  throw FormatException('Invalid ACF format: missing closing brace');
}

/// Skips spaces, tabs, and newlines from [i] and returns the next
/// non-whitespace index. Replaces the three duplicated whitespace loops.
int _skipWhitespace(String content, int i) {
  while (i < content.length &&
      (content[i] == ' ' || content[i] == '\t' || content[i] == '\n')) {
    i++;
  }
  return i;
}

/// Reads a quoted string starting at [start], returning its content and the
/// index just past the closing quote. Returns an empty value at [start] when
/// there is no opening quote, and throws FormatException on a missing closing
/// quote. Replaces the near-identical _parseString and _skipString.
({String value, int endIndex}) _readString(String content, int start) {
  int i = start;
  if (i >= content.length || content[i] != '"') {
    return (value: '', endIndex: start);
  }
  i++; // opening quote
  final contentStart = i;
  while (i < content.length && content[i] != '"') {
    if (content[i] == '\\' && i + 1 < content.length) {
      i += 2; // escaped char
    } else {
      i++;
    }
  }
  if (i >= content.length || content[i] != '"') {
    throw FormatException('Invalid string format: missing closing quote');
  }
  return (value: content.substring(contentStart, i), endIndex: i + 1);
}

/// 将解析后的ACF数据转换为AcfInfo对象列表
List<AcfInfo> convertToAcfInfoList(Map<String, dynamic> parsedData) {
  if (parsedData.isEmpty) return [];
  if (!parsedData.containsKey('AppWorkshop')) return [];
  final List<AcfInfo> result = [];

  // 获取AppWorkshop对象
  final appWorkshop = parsedData['AppWorkshop'] is Map<String, dynamic>
      ? parsedData['AppWorkshop'] as Map<String, dynamic>
      : null;
  if (appWorkshop == null) return [];

  // 处理WorkshopItemsInstalled
  if (appWorkshop.containsKey('WorkshopItemsInstalled') &&
      appWorkshop['WorkshopItemsInstalled'] is Map<String, dynamic>) {
    final workshopItemsInstalled =
        appWorkshop['WorkshopItemsInstalled'] as Map<String, dynamic>;
    workshopItemsInstalled.forEach((id, value) {
      if (value is Map<String, dynamic>) {
        result.add(AcfInfo.fromWorkshopInstalled(id, value));
      }
    });
  }

  return result;
}
