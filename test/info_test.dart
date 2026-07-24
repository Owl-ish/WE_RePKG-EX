import 'package:flutter_test/flutter_test.dart';
import 'package:we_repkg/utils/info.dart';

void main() {
  group('isImage', () {
    test('recognizes common image extensions', () {
      for (final name in ['a.jpg', 'a.jpeg', 'a.png', 'a.gif', 'a.webp']) {
        expect(isImage(name), isTrue, reason: name);
      }
    });
    test('is case-insensitive', () {
      expect(isImage('PHOTO.PNG'), isTrue);
      expect(isImage('photo.JpG'), isTrue);
    });
    test('rejects non-image extensions', () {
      expect(isImage('clip.mp4'), isFalse);
      expect(isImage('scene.pkg'), isFalse);
    });
    test('rejects names without an extension', () {
      expect(isImage('README'), isFalse);
    });
  });

  group('projectDefaultPath', () {
    test('derives the myprojects path from a workshop content path', () {
      final input = r'C:\Steam\steamapps\workshop\content\431960';
      final result = projectDefaultPath(input);
      expect(result.contains('wallpaper_engine'), isTrue);
      expect(result.contains('myprojects'), isTrue);
    });
  });
}
