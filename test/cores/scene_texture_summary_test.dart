import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:we_repkg/cores/scene_pkg_index.dart';
import 'package:we_repkg/cores/scene_texture_summary.dart';

void main() {
  late Directory temporary;

  setUp(() {
    temporary = Directory.systemTemp.createTempSync('scene-texture-layout');
  });

  tearDown(() {
    if (temporary.existsSync()) temporary.deleteSync(recursive: true);
  });

  test('locates an encoded image inside a bounded package entry', () async {
    const List<int> png = <int>[137, 80, 78, 71, 13, 10, 26, 10, 1, 2];
    final Uint8List texture = _texture(png);
    final File package = File('${temporary.path}/scene.pkg')
      ..writeAsBytesSync(<int>[0, 1, 2, ...texture, 3, 4]);

    final SceneTextureEncodedImage? image = await readSceneTextureEncodedImage(
      package,
      offset: 3,
      length: texture.length,
    );

    expect(image?.extension, '.png');
    expect(image?.payloadLength, png.length);
    expect(image?.payloadOffset, 3 + texture.length - png.length);
    expect(image?.summary.firstMipmapCount, 1);
    expect(await readSceneTextureEncodedImage(package, offset: 3), isNull);
    final File extractedImage = File('${temporary.path}/image.png')
      ..writeAsBytesSync(png);
    expect(
      await fileSegmentMatchesFile(
        source: package,
        offset: image!.payloadOffset,
        length: image.payloadLength,
        counterpart: extractedImage,
      ),
      isTrue,
    );
    extractedImage.writeAsBytesSync(<int>[...png.take(9), 3]);
    expect(
      await fileSegmentMatchesFile(
        source: package,
        offset: image.payloadOffset,
        length: image.payloadLength,
        counterpart: extractedImage,
      ),
      isFalse,
    );
  });

  test('declines truncated, compressed, and animated textures', () async {
    const List<int> jpeg = <int>[255, 216, 255, 224, 1, 2, 3, 4];
    final Uint8List texture = _texture(jpeg, imageFormat: 2);
    final File file = File('${temporary.path}/image.tex');
    file.writeAsBytesSync(texture);
    expect((await readSceneTextureEncodedImage(file))?.extension, '.jpg');

    file.writeAsBytesSync(texture.sublist(0, texture.length - 1));
    expect(await readSceneTextureEncodedImage(file), isNull);

    final Uint8List compressed = _texture(jpeg)..[75] = 1;
    file.writeAsBytesSync(compressed);
    expect(await readSceneTextureEncodedImage(file), isNull);

    final Uint8List animated = _texture(jpeg)..[22] = 4;
    file.writeAsBytesSync(animated);
    expect(await readSceneTextureEncodedImage(file), isNull);
  });

  test(
    'changed encoded TEX requires identical header and later mipmaps',
    () async {
      const List<int> png = <int>[137, 80, 78, 71, 13, 10, 26, 10, 1, 2];
      final File first = File('${temporary.path}/first.tex')
        ..writeAsBytesSync(_texture(png, secondMipmap: <int>[4, 5, 6]));
      final File second = File('${temporary.path}/second.tex')
        ..writeAsBytesSync(
          _texture(<int>[...png, 3], secondMipmap: <int>[4, 5, 6]),
        );
      final SceneTextureEncodedImage firstImage =
          (await readSceneTextureEncodedImage(first))!;
      SceneTextureEncodedImage secondImage =
          (await readSceneTextureEncodedImage(second))!;
      expect(
        sceneTexturePrimaryAssetLayoutMatches(firstImage, secondImage),
        isTrue,
      );
      expect(
        await compareSceneTextureEncodedRemainder(
          first: first,
          firstImage: firstImage,
          second: second,
          secondImage: secondImage,
        ),
        SceneTextureRemainderResult.match,
      );

      second.writeAsBytesSync(
        _texture(<int>[...png, 3], secondMipmap: <int>[4, 5, 7]),
      );
      secondImage = (await readSceneTextureEncodedImage(second))!;
      expect(
        sceneTexturePrimaryAssetLayoutMatches(firstImage, secondImage),
        isTrue,
      );
      expect(
        await compareSceneTextureEncodedRemainder(
          first: first,
          firstImage: firstImage,
          second: second,
          secondImage: secondImage,
        ),
        SceneTextureRemainderResult.mipmapPayloadDifferent,
      );

      final Uint8List changedHeader = _texture(
        <int>[...png, 3],
        secondMipmap: <int>[4, 5, 6],
      )..[42] = 1;
      second.writeAsBytesSync(changedHeader);
      secondImage = (await readSceneTextureEncodedImage(second))!;
      expect(
        sceneTexturePrimaryAssetLayoutMatches(firstImage, secondImage),
        isTrue,
      );
      expect(
        await compareSceneTextureEncodedRemainder(
          first: first,
          firstImage: firstImage,
          second: second,
          secondImage: secondImage,
        ),
        SceneTextureRemainderResult.headerDifferent,
      );

      changedHeader[22] = 1;
      second.writeAsBytesSync(changedHeader);
      secondImage = (await readSceneTextureEncodedImage(second))!;
      expect(
        sceneTexturePrimaryAssetLayoutMatches(firstImage, secondImage),
        isFalse,
      );

      second.writeAsBytesSync(_texture(<int>[...png, 3]));
      secondImage = (await readSceneTextureEncodedImage(second))!;
      expect(
        sceneTexturePrimaryAssetLayoutMatches(firstImage, secondImage),
        isTrue,
      );
      expect(
        await compareSceneTextureEncodedRemainder(
          first: first,
          firstImage: firstImage,
          second: second,
          secondImage: secondImage,
        ),
        SceneTextureRemainderResult.mipmapCountDifferent,
      );
    },
  );

  test('raw RG88 maps luminance and alpha and rejects damaged LZ4', () async {
    final image.Image pixels = image.Image(width: 2, height: 2, numChannels: 4);
    image.fill(pixels, color: image.ColorRgba8(128, 128, 128, 64));
    final File generated = File('${temporary.path}/image.png')
      ..writeAsBytesSync(image.encodePng(pixels));
    final List<int> raw = <int>[
      for (int pixel = 0; pixel < 4; pixel++) ...<int>[64, 128],
    ];
    final File texture = File('${temporary.path}/image.tex')
      ..writeAsBytesSync(
        _texture(
          <int>[0x80, ...raw],
          imageFormat: -1,
          textureFormat: 8,
          compression: 1,
          decodedLength: raw.length,
        ),
      );
    final SceneTextureRawImage? layout = await readSceneTextureRawImage(
      texture,
    );
    expect(layout, isNotNull);
    expect(
      await sceneTextureRawImageMatchesFile(texture, layout!, generated),
      isTrue,
    );
    expect(
      await sceneTextureRawImageMatchesFile(
        texture,
        layout,
        generated,
        compareNative: (_, __, ___) async => null,
      ),
      isTrue,
    );
    expect(
      await sceneTextureRawImageMatchesFile(
        texture,
        layout,
        generated,
        compareNative: (_, __, ___) async => false,
      ),
      isFalse,
    );

    image.fill(pixels, color: image.ColorRgba8(129, 129, 129, 64));
    generated.writeAsBytesSync(image.encodePng(pixels));
    expect(
      await sceneTextureRawImageMatchesFile(texture, layout, generated),
      isFalse,
    );
    final Uint8List damaged = texture.readAsBytesSync();
    damaged[layout.payloadOffset] = 0x90;
    texture.writeAsBytesSync(damaged);
    expect(
      await sceneTextureRawImageMatchesFile(texture, layout, generated),
      isNull,
    );
  });

  test('raw first mip compares cropped main image, not padding', () async {
    final image.Image main = image.Image(width: 2, height: 2);
    image.fill(main, color: image.ColorRgba8(10, 20, 30, 255));
    final File generated = File('${temporary.path}/cropped.png')
      ..writeAsBytesSync(image.encodePng(main));
    final List<int> pixels = <int>[
      for (int y = 0; y < 4; y++)
        for (int x = 0; x < 4; x++)
          if (x < 2 && y < 2) ...<int>[10, 20, 30, 255] else ...<int>[
            50,
            60,
            70,
            255,
          ],
    ];
    final File texture = File('${temporary.path}/cropped.tex')
      ..writeAsBytesSync(
        _texture(pixels, imageFormat: -1, firstWidth: 4, firstHeight: 4),
      );
    SceneTextureRawImage raw = (await readSceneTextureRawImage(texture))!;
    expect(
      await sceneTextureRawImageMatchesFile(texture, raw, generated),
      isTrue,
    );

    pixels[60] = 51;
    texture.writeAsBytesSync(
      _texture(pixels, imageFormat: -1, firstWidth: 4, firstHeight: 4),
    );
    raw = (await readSceneTextureRawImage(texture))!;
    expect(
      await sceneTextureRawImageMatchesFile(texture, raw, generated),
      isTrue,
    );

    pixels[0] = 11;
    texture.writeAsBytesSync(
      _texture(pixels, imageFormat: -1, firstWidth: 4, firstHeight: 4),
    );
    raw = (await readSceneTextureRawImage(texture))!;
    expect(
      await sceneTextureRawImageMatchesFile(texture, raw, generated),
      isFalse,
    );
  });

  test('DXT1, DXT3, and DXT5 compare decoded primary pixels', () async {
    final List<int> color = <int>[
      0x00,
      0xf8,
      0x1f,
      0x00,
      0xaa,
      0xaa,
      0xaa,
      0xaa,
    ];
    final int alphaIndices = List<int>.generate(
      16,
      (int _) => 2,
    ).fold<int>(0, (int bits, int index) => (bits << 3) | index);
    final List<int> dxt5 = <int>[
      255,
      0,
      for (int byte = 0; byte < 6; byte++) (alphaIndices >> (byte * 8)) & 255,
      ...color,
    ];
    final Map<int, List<int>> blocks = <int, List<int>>{
      7: color,
      6: <int>[for (int i = 0; i < 8; i++) 0xff, ...color],
      4: dxt5,
    };
    for (final MapEntry<int, List<int>> entry in blocks.entries) {
      final File texture = File('${temporary.path}/${entry.key}.tex')
        ..writeAsBytesSync(
          _texture(
            entry.value,
            imageFormat: -1,
            textureFormat: entry.key,
            firstWidth: 4,
            firstHeight: 4,
            imageWidth: 4,
            imageHeight: 4,
          ),
        );
      final SceneTextureRawImage? layout = await readSceneTextureRawImage(
        texture,
      );
      expect(layout, isNotNull);
      final image.Image expected = image.Image(
        width: 4,
        height: 4,
        numChannels: 4,
      );
      image.fill(
        expected,
        color: image.ColorRgba8(170, 0, 85, entry.key == 4 ? 218 : 255),
      );
      final File png = File('${temporary.path}/${entry.key}.png')
        ..writeAsBytesSync(image.encodePng(expected));
      expect(
        await sceneTextureRawImageMatchesFile(texture, layout!, png),
        isTrue,
        reason: 'DXT${entry.key}',
      );
      image.fill(expected, color: image.ColorRgba8(171, 0, 85, 255));
      png.writeAsBytesSync(image.encodePng(expected));
      expect(
        await sceneTextureRawImageMatchesFile(texture, layout, png),
        isFalse,
      );
    }
  });

  test('legacy raw and LZ4 DXT5 compare only the cropped main image', () async {
    final image.Image main = image.Image(width: 2, height: 2);
    image.fill(main, color: image.ColorRgba8(255, 0, 0, 255));
    final File png = File('${temporary.path}/legacy.png')
      ..writeAsBytesSync(image.encodePng(main));
    final List<int> rgba = <int>[
      for (int i = 0; i < 16; i++) ...<int>[255, 0, 0, 255],
    ];
    final File legacy = File('${temporary.path}/legacy.tex')
      ..writeAsBytesSync(_legacyTexture(rgba));
    final SceneTextureRawImage? raw = await readSceneTextureRawImage(legacy);
    expect(raw, isNotNull);
    expect(await sceneTextureRawImageMatchesFile(legacy, raw!, png), isTrue);

    final List<int> dxt = <int>[
      255,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0x00,
      0xf8,
      0x1f,
      0x00,
      0,
      0,
      0,
      0,
    ];
    legacy.writeAsBytesSync(_legacyTexture(dxt, format: 4));
    final SceneTextureRawImage? legacyDxt = await readSceneTextureRawImage(
      legacy,
    );
    expect(legacyDxt, isNotNull);
    expect(
      await sceneTextureRawImageMatchesFile(legacy, legacyDxt!, png),
      isTrue,
    );

    final File compressed = File('${temporary.path}/lz4.tex')
      ..writeAsBytesSync(
        _texture(
          <int>[0xf0, 1, ...dxt],
          imageFormat: -1,
          textureFormat: 4,
          firstWidth: 4,
          firstHeight: 4,
          compression: 1,
          decodedLength: 16,
        ),
      );
    final SceneTextureRawImage? lz4 = await readSceneTextureRawImage(
      compressed,
    );
    expect(lz4, isNotNull);
    expect(
      await sceneTextureRawImageMatchesFile(compressed, lz4!, png),
      isTrue,
    );
    compressed.writeAsBytesSync(
      _texture(
        <int>[0xf0, 1, ...dxt.take(15)],
        imageFormat: -1,
        textureFormat: 4,
        firstWidth: 4,
        firstHeight: 4,
        compression: 1,
        decodedLength: 16,
      ),
    );
    expect(await sceneTextureRawImageMatchesFile(compressed, lz4, png), isNull);
  });

  test('recognizes only a bounded single-frame GIF texture', () async {
    final BytesBuilder trailer = BytesBuilder();
    void word(int value) => trailer.add(
      (ByteData(4)..setInt32(0, value, Endian.little)).buffer.asUint8List(),
    );
    void number(double value) => trailer.add(
      (ByteData(4)..setFloat32(0, value, Endian.little)).buffer.asUint8List(),
    );
    trailer.add(utf8.encode('TEXS0003'));
    trailer.addByte(0);
    for (final int value in <int>[1, 2, 2, 0]) {
      word(value);
    }
    number(0.1);
    for (final double value in <double>[0, 0, 2, 0, 0, 2]) {
      number(value);
    }
    final Uint8List gif = Uint8List.fromList(<int>[
      ..._texture(
        <int>[255, 216, 255, 224, 1, 2, 3, 4],
        imageFormat: 2,
        flags: 4,
      ),
      ...trailer.toBytes(),
    ]);
    final File texture = File('${temporary.path}/animated.tex')
      ..writeAsBytesSync(gif);
    expect(await readSceneTextureGif(texture), isNotNull);
    texture.writeAsBytesSync(gif.sublist(0, gif.length - 1));
    expect(await readSceneTextureGif(texture), isNull);
  });
}

Uint8List _legacyTexture(List<int> payload, {int format = 0}) {
  final BytesBuilder bytes = BytesBuilder();
  void name(String value) {
    bytes.add(utf8.encode(value));
    bytes.addByte(0);
  }

  void word(int value) => bytes.add(
    (ByteData(4)..setInt32(0, value, Endian.little)).buffer.asUint8List(),
  );
  name('TEXV0005');
  name('TEXI0001');
  for (final int value in <int>[format, 0, 4, 4, 2, 2, 0]) {
    word(value);
  }
  name('TEXB0001');
  for (final int value in <int>[1, 1, 4, 4, payload.length]) {
    word(value);
  }
  bytes.add(payload);
  return bytes.toBytes();
}

Uint8List _texture(
  List<int> payload, {
  int imageFormat = 13,
  int textureFormat = 0,
  int flags = 0,
  int compression = 0,
  int decodedLength = 0,
  int firstWidth = 2,
  int firstHeight = 2,
  int imageWidth = 2,
  int imageHeight = 2,
  List<int>? secondMipmap,
}) {
  final BytesBuilder bytes = BytesBuilder();
  void name(String value) {
    bytes.add(utf8.encode(value));
    bytes.addByte(0);
  }

  void word(int value) {
    bytes.add(
      (ByteData(4)..setInt32(0, value, Endian.little)).buffer.asUint8List(),
    );
  }

  name('TEXV0005');
  name('TEXI0001');
  for (final int value in <int>[
    textureFormat,
    flags,
    firstWidth,
    firstHeight,
    imageWidth,
    imageHeight,
    0,
  ]) {
    word(value);
  }
  name('TEXB0003');
  word(1);
  word(imageFormat);
  word(secondMipmap == null ? 1 : 2);
  for (final int value in <int>[
    firstWidth,
    firstHeight,
    compression,
    decodedLength,
    payload.length,
  ]) {
    word(value);
  }
  bytes.add(payload);
  if (secondMipmap != null) {
    for (final int value in <int>[1, 1, 0, 0, secondMipmap.length]) {
      word(value);
    }
    bytes.add(secondMipmap);
  }
  return bytes.toBytes();
}
