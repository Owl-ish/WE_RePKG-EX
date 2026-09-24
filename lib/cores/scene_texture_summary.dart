import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as image;

typedef SceneTextureSummary = ({
  int format,
  int flags,
  int textureWidth,
  int textureHeight,
  int imageWidth,
  int imageHeight,
  int imageCount,
  int firstMipmapCount,
});

typedef SceneTextureEncodedImage = ({
  SceneTextureSummary summary,
  String extension,
  int payloadOffset,
  int payloadLength,
  Uint8List prelude,
  List<SceneTextureMipmap> mipmaps,
});

typedef SceneTextureMipmap = ({
  int width,
  int height,
  int compression,
  int decodedLength,
  int payloadOffset,
  int payloadLength,
});

typedef SceneTextureRawImage = ({
  SceneTextureSummary summary,
  int payloadOffset,
  int payloadLength,
  int decodedLength,
  int width,
  int height,
  bool compressed,
});

typedef SceneTextureVideo = ({
  SceneTextureSummary summary,
  int payloadOffset,
  int payloadLength,
});

typedef SceneTextureGif = ({SceneTextureSummary summary});

const int _maxRawImageBytes = 64 * 1024 * 1024;

/// Recognizes a bounded one-frame animated TEX. The caller can account for
/// missing generated GIF/metadata files without synthesizing a GIF palette.
/// Existing generated GIFs still require a separate semantic comparison.
Future<SceneTextureGif?> readSceneTextureGif(
  File source, {
  int offset = 0,
  int? length,
}) async {
  RandomAccessFile? input;
  try {
    input = await source.open();
    final int fileLength = await input.length();
    final int sectionLength = length ?? fileLength - offset;
    if (offset < 0 ||
        sectionLength < 140 ||
        offset > fileLength ||
        sectionLength > fileLength - offset) {
      return null;
    }
    await input.setPosition(offset);
    final Uint8List prefix = Uint8List.fromList(await input.read(91));
    final SceneTextureSummary? summary = readSceneTextureSummary(prefix);
    if (summary == null ||
        (summary.flags & 4) == 0 ||
        (summary.flags & 32) != 0 ||
        summary.imageCount != 1 ||
        summary.firstMipmapCount != 1 ||
        ascii.decode(prefix.sublist(46, 54)) != 'TEXB0003') {
      return null;
    }
    final ByteData header = ByteData.sublistView(prefix);
    final int imageFormat = header.getInt32(59, Endian.little);
    final int mipWidth = header.getInt32(67, Endian.little);
    final int mipHeight = header.getInt32(71, Endian.little);
    final int compression = header.getInt32(75, Endian.little);
    final int payloadLength = header.getInt32(83, Endian.little);
    const int payloadStart = 87;
    const int trailerLength = 53;
    if (!<int>{2, 13}.contains(imageFormat) ||
        mipWidth <= 0 ||
        mipHeight <= 0 ||
        compression != 0 ||
        payloadLength < 8 ||
        payloadStart + payloadLength + trailerLength != sectionLength) {
      return null;
    }
    final bool isJpeg =
        imageFormat == 2 &&
        _startsWith(prefix.sublist(payloadStart), const <int>[255, 216, 255]);
    final bool isPng =
        imageFormat == 13 &&
        _startsWith(prefix.sublist(payloadStart), const <int>[137, 80, 78, 71]);
    if (!isJpeg && !isPng) return null;
    await input.setPosition(offset + payloadStart + payloadLength);
    final Uint8List trailer = Uint8List.fromList(
      await input.read(trailerLength),
    );
    if (trailer.length != trailerLength ||
        ascii.decode(trailer.sublist(0, 8)) != 'TEXS0003' ||
        trailer[8] != 0) {
      return null;
    }
    final ByteData frames = ByteData.sublistView(trailer);
    if (frames.getInt32(9, Endian.little) != 1 ||
        frames.getInt32(13, Endian.little) <= 0 ||
        frames.getInt32(17, Endian.little) <= 0 ||
        frames.getInt32(21, Endian.little) != 0 ||
        !frames.getFloat32(25, Endian.little).isFinite) {
      return null;
    }
    for (int at = 29; at < trailerLength; at += 4) {
      if (!frames.getFloat32(at, Endian.little).isFinite) return null;
    }
    return (summary: summary);
  } on FileSystemException {
    return null;
  } on FormatException {
    return null;
  } finally {
    await input?.close();
  }
}

/// Video textures expose the original MP4 as their first mipmap. Validate the
/// bounded v3 payload so it can be compared by streaming bytes, without decode.
Future<SceneTextureVideo?> readSceneTextureVideo(
  File source, {
  int offset = 0,
  int? length,
}) async {
  RandomAccessFile? input;
  try {
    input = await source.open();
    final int fileLength = await input.length();
    final int sectionLength = length ?? fileLength - offset;
    if (offset < 0 ||
        sectionLength < 99 ||
        offset > fileLength ||
        sectionLength > fileLength - offset) {
      return null;
    }
    await input.setPosition(offset);
    final Uint8List prefix = Uint8List.fromList(await input.read(99));
    final SceneTextureSummary? summary = readSceneTextureSummary(prefix);
    if (summary == null ||
        summary.imageCount != 1 ||
        summary.firstMipmapCount != 1 ||
        (summary.flags & 32) == 0 ||
        (summary.flags & 4) != 0 ||
        ascii.decode(prefix.sublist(46, 54)) != 'TEXB0003') {
      return null;
    }
    final ByteData header = ByteData.sublistView(prefix);
    if (header.getInt32(59, Endian.little) != -1 ||
        header.getInt32(75, Endian.little) != 0) {
      return null;
    }
    final int payloadLength = header.getInt32(83, Endian.little);
    const int payloadStart = 87;
    if (payloadLength < 12 || payloadLength != sectionLength - payloadStart) {
      return null;
    }
    final String signature = ascii.decode(prefix.sublist(91, 99)).toLowerCase();
    if (!<String>{'ftypisom', 'ftypmsnv', 'ftypmp42'}.contains(signature)) {
      return null;
    }
    return (
      summary: summary,
      payloadOffset: offset + payloadStart,
      payloadLength: payloadLength,
    );
  } on FileSystemException {
    return null;
  } on FormatException {
    return null;
  } finally {
    await input?.close();
  }
}

/// Reads one raw or DXT texture's primary mipmap. Later mipmaps are only
/// bounds-checked because backup equivalence uses the primary image.
Future<SceneTextureRawImage?> readSceneTextureRawImage(
  File source, {
  int offset = 0,
  int? length,
}) async {
  RandomAccessFile? input;
  try {
    input = await source.open();
    final int fileLength = await input.length();
    final int sectionLength = length ?? fileLength - offset;
    if (offset < 0 ||
        sectionLength < 75 ||
        offset > fileLength ||
        sectionLength > fileLength - offset) {
      return null;
    }
    await input.setPosition(offset);
    final Uint8List prefix = Uint8List.fromList(
      await input.read(sectionLength < 128 ? sectionLength : 128),
    );
    final SceneTextureSummary? summary = readSceneTextureSummary(prefix);
    final String imageMagic = ascii.decode(prefix.sublist(46, 54));
    if (summary == null ||
        summary.imageCount != 1 ||
        summary.firstMipmapCount > 32 ||
        (summary.flags & (4 | 32)) != 0 ||
        !<int>{0, 4, 6, 7, 8, 9}.contains(summary.format) ||
        !<String>{
          'TEXB0001',
          'TEXB0002',
          'TEXB0003',
          'TEXB0004',
        }.contains(imageMagic) ||
        ((imageMagic == 'TEXB0003' || imageMagic == 'TEXB0004') &&
            ByteData.sublistView(prefix).getInt32(59, Endian.little) != -1) ||
        (imageMagic == 'TEXB0004' &&
            ByteData.sublistView(prefix).getInt32(63, Endian.little) != 0)) {
      return null;
    }
    final bool legacy = imageMagic == 'TEXB0001';
    int position = imageMagic == 'TEXB0004'
        ? 71
        : imageMagic == 'TEXB0003'
        ? 67
        : 63;
    SceneTextureRawImage? first;
    for (int mip = 0; mip < summary.firstMipmapCount; mip++) {
      final int headerLength = legacy ? 12 : 20;
      if (sectionLength - position < headerLength) return null;
      await input.setPosition(offset + position);
      final Uint8List header = Uint8List.fromList(
        await input.read(headerLength),
      );
      if (header.length != headerLength) return null;
      final ByteData values = ByteData.sublistView(header);
      final int width = values.getInt32(0, Endian.little);
      final int height = values.getInt32(4, Endian.little);
      final int compression = legacy ? 0 : values.getInt32(8, Endian.little);
      final int payloadLength = values.getInt32(legacy ? 8 : 16, Endian.little);
      final int decompressedLength = legacy
          ? payloadLength
          : values.getInt32(12, Endian.little);
      position += headerLength;
      if (width <= 0 ||
          height <= 0 ||
          (compression != 0 && compression != 1) ||
          payloadLength <= 0 ||
          payloadLength > sectionLength - position) {
        return null;
      }
      if (mip == 0) {
        final int channels = summary.format == 0
            ? 4
            : summary.format == 8
            ? 2
            : 1;
        final int blockBytes = summary.format == 7
            ? 8
            : summary.format == 4 || summary.format == 6
            ? 16
            : 0;
        final int expected = blockBytes != 0
            ? ((width + 3) ~/ 4) * ((height + 3) ~/ 4) * blockBytes
            : width * height * channels;
        if (width * height * 4 > _maxRawImageBytes ||
            expected > _maxRawImageBytes ||
            payloadLength > _maxRawImageBytes ||
            (compression == 0 && payloadLength != expected) ||
            (compression == 1 && decompressedLength != expected)) {
          return null;
        }
        first = (
          summary: summary,
          payloadOffset: offset + position,
          payloadLength: payloadLength,
          decodedLength: expected,
          width: width,
          height: height,
          compressed: compression == 1,
        );
      }
      position += payloadLength;
    }
    return position == sectionLength ? first : null;
  } on FileSystemException {
    return null;
  } on FormatException {
    return null;
  } finally {
    await input?.close();
  }
}

/// Checks the PNG emitted from a raw TEX without writing an image. RePKG crops
/// power-of-two padding from the top left; images needing scaling stay unknown.
Future<bool?> sceneTextureRawImageMatchesFile(
  File source,
  SceneTextureRawImage raw,
  File generatedImage,
) async {
  if (raw.width < raw.summary.imageWidth ||
      raw.height < raw.summary.imageHeight) {
    return null;
  }
  try {
    if (await generatedImage.length() > _maxRawImageBytes) return null;
    return await Isolate.run(
      () => _rawImageMatchesFile(source.path, raw, generatedImage.path),
    );
  } catch (_) {
    return null;
  }
}

bool? _rawImageMatchesFile(
  String sourcePath,
  SceneTextureRawImage raw,
  String generatedImagePath,
) {
  RandomAccessFile? input;
  try {
    input = File(sourcePath).openSync();
    if (raw.payloadOffset < 0 ||
        raw.payloadOffset > input.lengthSync() ||
        raw.payloadLength > input.lengthSync() - raw.payloadOffset) {
      return null;
    }
    input.setPositionSync(raw.payloadOffset);
    final Uint8List payload = Uint8List.fromList(
      input.readSync(raw.payloadLength),
    );
    if (payload.length != raw.payloadLength) return null;
    final Uint8List? pixels = raw.compressed
        ? _decodeLz4Block(payload, raw.decodedLength)
        : payload;
    if (pixels == null || pixels.length != raw.decodedLength) return null;
    final Uint8List png = File(generatedImagePath).readAsBytesSync();
    if (png.length < 24 ||
        !_startsWith(png, const <int>[137, 80, 78, 71, 13, 10, 26, 10])) {
      return null;
    }
    final ByteData pngHeader = ByteData.sublistView(png);
    final int imageWidth = raw.summary.imageWidth;
    final int imageHeight = raw.summary.imageHeight;
    if (pngHeader.getUint32(16) != imageWidth ||
        pngHeader.getUint32(20) != imageHeight) {
      return null;
    }
    final image.Image? generated = image.decodePng(png);
    if (generated == null ||
        generated.width != imageWidth ||
        generated.height != imageHeight ||
        generated.numFrames != 1) {
      return null;
    }
    final Uint8List rgba = generated.getBytes(order: image.ChannelOrder.rgba);
    if (raw.summary.format == 4 ||
        raw.summary.format == 6 ||
        raw.summary.format == 7) {
      return _dxtImageMatchesRgba(pixels, raw, rgba);
    }
    final int channels = raw.summary.format == 0
        ? 4
        : raw.summary.format == 8
        ? 2
        : 1;
    for (int y = 0; y < imageHeight; y++) {
      for (int x = 0; x < imageWidth; x++) {
        final int source = (y * raw.width + x) * channels;
        final int target = (y * imageWidth + x) * 4;
        final int red = raw.summary.format == 0
            ? pixels[source]
            : raw.summary.format == 8
            ? pixels[source + 1]
            : pixels[source];
        final int alpha = raw.summary.format == 0
            ? pixels[source + 3]
            : raw.summary.format == 8
            ? pixels[source]
            : 255;
        if (rgba[target] != red ||
            rgba[target + 1] !=
                (raw.summary.format == 0 ? pixels[source + 1] : red) ||
            rgba[target + 2] !=
                (raw.summary.format == 0 ? pixels[source + 2] : red) ||
            rgba[target + 3] != alpha) {
          return false;
        }
      }
    }
    return true;
  } on FileSystemException {
    return null;
  } on FormatException {
    return null;
  } catch (_) {
    return null;
  } finally {
    input?.closeSync();
  }
}

bool _dxtImageMatchesRgba(
  Uint8List blocks,
  SceneTextureRawImage raw,
  Uint8List rgba,
) {
  final int format = raw.summary.format;
  final int blockBytes = format == 7 ? 8 : 16;
  final Uint8List colors = Uint8List(16);
  final Uint8List alphas = Uint8List(8);
  int block = 0;
  int expand5(int value) => (value << 3) | (value >> 2);
  int expand6(int value) => (value << 2) | (value >> 4);

  for (int by = 0; by < raw.height; by += 4) {
    for (int bx = 0; bx < raw.width; bx += 4) {
      final int colorAt = block + (format == 7 ? 0 : 8);
      final int endpoint0 = blocks[colorAt] | (blocks[colorAt + 1] << 8);
      final int endpoint1 = blocks[colorAt + 2] | (blocks[colorAt + 3] << 8);
      for (int index = 0; index < 2; index++) {
        final int endpoint = index == 0 ? endpoint0 : endpoint1;
        final int at = index * 4;
        colors[at] = expand5((endpoint >> 11) & 31);
        colors[at + 1] = expand6((endpoint >> 5) & 63);
        colors[at + 2] = expand5(endpoint & 31);
        colors[at + 3] = 255;
      }
      final bool transparentFourth = format == 7 && endpoint0 <= endpoint1;
      for (int channel = 0; channel < 3; channel++) {
        final int first = colors[channel];
        final int second = colors[4 + channel];
        colors[8 + channel] = transparentFourth
            ? (first + second) ~/ 2
            : (2 * first + second) ~/ 3;
        colors[12 + channel] = transparentFourth
            ? 0
            : (first + 2 * second) ~/ 3;
      }
      colors[11] = 255;
      colors[15] = transparentFourth ? 0 : 255;

      int alphaIndices = 0;
      if (format == 4) {
        final int first = blocks[block];
        final int second = blocks[block + 1];
        alphas[0] = first;
        alphas[1] = second;
        if (first > second) {
          for (int index = 1; index <= 6; index++) {
            alphas[index + 1] = ((7 - index) * first + index * second) ~/ 7;
          }
        } else {
          for (int index = 1; index <= 4; index++) {
            alphas[index + 1] = ((5 - index) * first + index * second) ~/ 5;
          }
          alphas[6] = 0;
          alphas[7] = 255;
        }
        for (int index = 0; index < 6; index++) {
          alphaIndices |= blocks[block + 2 + index] << (index * 8);
        }
      }
      for (int py = 0; py < 4; py++) {
        for (int px = 0; px < 4; px++) {
          final int x = bx + px;
          final int y = by + py;
          if (x >= raw.summary.imageWidth || y >= raw.summary.imageHeight) {
            continue;
          }
          final int pixel = py * 4 + px;
          final int colorIndex = (blocks[colorAt + 4 + py] >> (px * 2)) & 3;
          final int color = colorIndex * 4;
          final int alpha = format == 4
              ? alphas[(alphaIndices >> (pixel * 3)) & 7]
              : format == 6
              ? ((blocks[block + (pixel ~/ 2)] >> ((pixel & 1) * 4)) & 15) * 17
              : colors[color + 3];
          final int target = (y * raw.summary.imageWidth + x) * 4;
          if (rgba[target] != colors[color] ||
              rgba[target + 1] != colors[color + 1] ||
              rgba[target + 2] != colors[color + 2] ||
              rgba[target + 3] != alpha) {
            return false;
          }
        }
      }
      block += blockBytes;
    }
  }
  return block == blocks.length;
}

Uint8List? _decodeLz4Block(Uint8List source, int outputLength) {
  final Uint8List output = Uint8List(outputLength);
  int input = 0;
  int written = 0;
  while (input < source.length) {
    final int token = source[input++];
    int literals = token >> 4;
    if (literals == 15) {
      int extra;
      do {
        if (input >= source.length) return null;
        extra = source[input++];
        literals += extra;
      } while (extra == 255);
    }
    if (literals > source.length - input || literals > outputLength - written) {
      return null;
    }
    output.setRange(written, written + literals, source, input);
    input += literals;
    written += literals;
    if (input == source.length) break;
    if (source.length - input < 2) return null;
    final int distance = source[input++] | (source[input++] << 8);
    if (distance == 0 || distance > written) return null;
    int match = (token & 15) + 4;
    if ((token & 15) == 15) {
      int extra;
      do {
        if (input >= source.length) return null;
        extra = source[input++];
        match += extra;
      } while (extra == 255);
    }
    if (match > outputLength - written) return null;
    for (int index = 0; index < match; index++) {
      output[written] = output[written - distance];
      written++;
    }
  }
  return written == outputLength ? output : null;
}

/// Mirrors the metadata written beside a non-animated TEX image by RePKG.
/// Unknown formats are left unavailable rather than assigning a guessed name.
Map<String, Object?>? sceneTextureGeneratedMetadata(
  SceneTextureSummary summary,
) {
  final String? format = switch (summary.format) {
    0 => 'rgba8888',
    4 => 'dxt5',
    6 => 'dxt3',
    7 => 'dxt1',
    8 => 'rg88',
    9 => 'r8',
    _ => null,
  };
  if (format == null || (summary.flags & 4) != 0) return null;
  String flag(bool value) => value ? 'true' : 'false';
  return <String, Object?>{
    'bleedtransparentcolors': true,
    'clampuvs': (summary.flags & 2) != 0,
    'format': format,
    'nomip': flag(summary.firstMipmapCount == 1),
    'nointerpolation': flag((summary.flags & 1) != 0),
    'nonpoweroftwo': flag(
      _nonPowerOfTwo(summary.imageWidth, summary.imageHeight),
    ),
  };
}

/// RePKG's `UnkInt0` at bytes 42-45 is not used to generate the image or its
/// metadata. The final four bytes are the mip count. Both are excluded here;
/// the primary pixels and all rendering fields are checked separately.
bool sceneTexturePrimaryAssetLayoutMatches(
  SceneTextureEncodedImage first,
  SceneTextureEncodedImage second,
) {
  if (first.prelude.length != second.prelude.length ||
      first.prelude.length < 4 ||
      first.mipmaps.first.width != second.mipmaps.first.width ||
      first.mipmaps.first.height != second.mipmaps.first.height) {
    return false;
  }
  for (int index = 0; index < first.prelude.length - 4; index++) {
    if (index >= 42 && index < 46) continue;
    if (first.prelude[index] != second.prelude[index]) return false;
  }
  return true;
}

/// Locates an uncompressed JPEG/PNG first mipmap inside a TEX file or package
/// entry. This reads headers only; it neither extracts nor decodes the image.
/// Other texture formats and malformed containers are unavailable to this path.
Future<SceneTextureEncodedImage?> readSceneTextureEncodedImage(
  File source, {
  int offset = 0,
  int? length,
}) async {
  RandomAccessFile? input;
  try {
    input = await source.open();
    final int fileLength = await input.length();
    final int sectionLength = length ?? fileLength - offset;
    if (offset < 0 ||
        sectionLength < 87 ||
        offset > fileLength ||
        sectionLength > fileLength - offset) {
      return null;
    }
    await input.setPosition(offset);
    final Uint8List prefix = Uint8List.fromList(
      await input.read(sectionLength < 128 ? sectionLength : 128),
    );
    final SceneTextureSummary? summary = readSceneTextureSummary(prefix);
    if (summary == null ||
        summary.imageCount != 1 ||
        summary.firstMipmapCount > 32 ||
        (summary.flags & (4 | 32)) != 0 ||
        !<int>{0, 4, 6, 7, 8, 9}.contains(summary.format)) {
      return null;
    }
    final ByteData header = ByteData.sublistView(prefix);
    final String imageMagic = ascii.decode(prefix.sublist(46, 54));
    if (imageMagic != 'TEXB0003' && imageMagic != 'TEXB0004') {
      return null;
    }
    final int imageFormat = header.getInt32(59, Endian.little);
    if (imageFormat != 2 && imageFormat != 13) return null;
    if (imageMagic == 'TEXB0004' && header.getInt32(63, Endian.little) != 0) {
      return null;
    }

    int position = imageMagic == 'TEXB0004' ? 71 : 67;
    int? firstPayloadOffset;
    int? firstPayloadLength;
    final Uint8List prelude = Uint8List.fromList(prefix.sublist(0, position));
    final List<SceneTextureMipmap> mipmaps = <SceneTextureMipmap>[];
    for (int mip = 0; mip < summary.firstMipmapCount; mip++) {
      if (sectionLength - position < 20) return null;
      await input.setPosition(offset + position);
      final Uint8List mipHeader = Uint8List.fromList(await input.read(20));
      if (mipHeader.length != 20) return null;
      final ByteData values = ByteData.sublistView(mipHeader);
      final int width = values.getInt32(0, Endian.little);
      final int height = values.getInt32(4, Endian.little);
      final int compression = values.getInt32(8, Endian.little);
      final int decompressedLength = values.getInt32(12, Endian.little);
      final int payloadLength = values.getInt32(16, Endian.little);
      position += 20;
      if (width <= 0 ||
          height <= 0 ||
          (compression != 0 && compression != 1) ||
          decompressedLength < 0 ||
          payloadLength <= 0 ||
          payloadLength > sectionLength - position) {
        return null;
      }
      if (mip == 0) {
        if (compression != 0 || payloadLength < 8) return null;
        firstPayloadOffset = offset + position;
        firstPayloadLength = payloadLength;
      }
      mipmaps.add((
        width: width,
        height: height,
        compression: compression,
        decodedLength: decompressedLength,
        payloadOffset: offset + position,
        payloadLength: payloadLength,
      ));
      position += payloadLength;
    }
    if (position != sectionLength ||
        firstPayloadOffset == null ||
        firstPayloadLength == null) {
      return null;
    }
    await input.setPosition(firstPayloadOffset);
    final Uint8List imagePrefix = Uint8List.fromList(await input.read(8));
    if (imagePrefix.length != 8) return null;
    final bool isPng =
        imageFormat == 13 &&
        _startsWith(imagePrefix, const <int>[137, 80, 78, 71, 13, 10, 26, 10]);
    final bool isJpeg =
        imageFormat == 2 &&
        _startsWith(imagePrefix, const <int>[255, 216, 255]);
    if (!isPng && !isJpeg) return null;
    return (
      summary: summary,
      extension: isPng ? '.png' : '.jpg',
      payloadOffset: firstPayloadOffset,
      payloadLength: firstPayloadLength,
      prelude: prelude,
      mipmaps: mipmaps,
    );
  } on FileSystemException {
    return null;
  } on FormatException {
    return null;
  } finally {
    await input?.close();
  }
}

/// A changed TEX can use the first image as its semantic comparison only
/// when its other mipmaps and rendering header are byte-for-byte unchanged.
/// Byte differences in secondary mipmaps do not prove different pixels.
enum SceneTextureRemainderResult {
  match,
  headerDifferent,
  mipmapCountDifferent,
  mipmapLayoutDifferent,
  mipmapPayloadDifferent,
  unavailable,
}

Future<SceneTextureRemainderResult> compareSceneTextureEncodedRemainder({
  required File first,
  required SceneTextureEncodedImage firstImage,
  required File second,
  required SceneTextureEncodedImage secondImage,
  bool Function()? isCancelled,
}) async {
  if (isCancelled?.call() == true) {
    return SceneTextureRemainderResult.unavailable;
  }
  final Uint8List firstPrelude = firstImage.prelude;
  final Uint8List secondPrelude = secondImage.prelude;
  if (firstImage.mipmaps.length != secondImage.mipmaps.length) {
    return SceneTextureRemainderResult.mipmapCountDifferent;
  }
  if (firstPrelude.length != secondPrelude.length) {
    return SceneTextureRemainderResult.headerDifferent;
  }
  for (int index = 0; index < firstPrelude.length; index++) {
    if (firstPrelude[index] != secondPrelude[index]) {
      return SceneTextureRemainderResult.headerDifferent;
    }
  }
  RandomAccessFile? firstInput;
  RandomAccessFile? secondInput;
  try {
    firstInput = await first.open();
    secondInput = await second.open();
    final int firstLength = await firstInput.length();
    final int secondLength = await secondInput.length();
    final Uint8List firstChunk = Uint8List(64 * 1024);
    final Uint8List secondChunk = Uint8List(64 * 1024);
    for (int mip = 0; mip < firstImage.mipmaps.length; mip++) {
      if (isCancelled?.call() == true) {
        return SceneTextureRemainderResult.unavailable;
      }
      final SceneTextureMipmap a = firstImage.mipmaps[mip];
      final SceneTextureMipmap b = secondImage.mipmaps[mip];
      if (a.width != b.width ||
          a.height != b.height ||
          a.compression != b.compression ||
          a.decodedLength != b.decodedLength) {
        return SceneTextureRemainderResult.mipmapLayoutDifferent;
      }
      if (mip == 0) continue;
      if (a.payloadLength != b.payloadLength) {
        return SceneTextureRemainderResult.mipmapPayloadDifferent;
      }
      if (a.payloadOffset < 0 ||
          b.payloadOffset < 0 ||
          a.payloadOffset > firstLength ||
          b.payloadOffset > secondLength ||
          a.payloadLength > firstLength - a.payloadOffset ||
          b.payloadLength > secondLength - b.payloadOffset) {
        return SceneTextureRemainderResult.unavailable;
      }
      await firstInput.setPosition(a.payloadOffset);
      await secondInput.setPosition(b.payloadOffset);
      int remaining = a.payloadLength;
      while (remaining > 0) {
        if (isCancelled?.call() == true) {
          return SceneTextureRemainderResult.unavailable;
        }
        final int size = remaining < firstChunk.length
            ? remaining
            : firstChunk.length;
        if (await firstInput.readInto(firstChunk, 0, size) != size ||
            await secondInput.readInto(secondChunk, 0, size) != size) {
          return SceneTextureRemainderResult.unavailable;
        }
        for (int index = 0; index < size; index++) {
          if (firstChunk[index] != secondChunk[index]) {
            return SceneTextureRemainderResult.mipmapPayloadDifferent;
          }
        }
        remaining -= size;
      }
    }
    return SceneTextureRemainderResult.match;
  } on FileSystemException {
    return SceneTextureRemainderResult.unavailable;
  } finally {
    await firstInput?.close();
    await secondInput?.close();
  }
}

bool _startsWith(Uint8List bytes, List<int> prefix) {
  if (bytes.length < prefix.length) return false;
  for (int index = 0; index < prefix.length; index++) {
    if (bytes[index] != prefix[index]) return false;
  }
  return true;
}

/// Only fields that RePKG writes to `.tex-json` can reject a pair here.
/// Asset-level callers ignore `nomip`; other callers retain the strict check.
bool sceneTextureMetadataDiffers(
  SceneTextureSummary first,
  SceneTextureSummary second, {
  bool compareMipSetting = true,
}) =>
    first.format != second.format ||
    (first.flags & 3) != (second.flags & 3) ||
    (compareMipSetting &&
        (first.firstMipmapCount == 1) != (second.firstMipmapCount == 1)) ||
    _nonPowerOfTwo(first.imageWidth, first.imageHeight) !=
        _nonPowerOfTwo(second.imageWidth, second.imageHeight);

bool _nonPowerOfTwo(int width, int height) =>
    !_powerOfTwo(width) || !_powerOfTwo(height);

bool _powerOfTwo(int value) => value > 0 && (value & (value - 1)) == 0;

/// Reads only TEX structure that changes rendering or generated metadata.
/// Equal summaries do not prove equal textures; the remaining bytes still need
/// a semantic comparison. Unknown or truncated variants return null.
SceneTextureSummary? readSceneTextureSummary(Uint8List prefix) {
  final _TextureCursor cursor = _TextureCursor(prefix);
  if (cursor.readName() != 'TEXV0005' || cursor.readName() != 'TEXI0001') {
    return null;
  }
  final int? format = cursor.readInt();
  final int? flags = cursor.readInt();
  final int? textureWidth = cursor.readInt();
  final int? textureHeight = cursor.readInt();
  final int? imageWidth = cursor.readInt();
  final int? imageHeight = cursor.readInt();
  final int? unknown = cursor.readInt();
  final String? imageMagic = cursor.readName();
  final int? imageCount = cursor.readInt();
  if (format == null ||
      flags == null ||
      textureWidth == null ||
      textureHeight == null ||
      imageWidth == null ||
      imageHeight == null ||
      unknown == null ||
      imageCount == null ||
      textureWidth <= 0 ||
      textureHeight <= 0 ||
      imageWidth <= 0 ||
      imageHeight <= 0 ||
      imageCount <= 0) {
    return null;
  }
  switch (imageMagic) {
    case 'TEXB0001' || 'TEXB0002':
      break;
    case 'TEXB0003':
      if (cursor.readInt() == null) return null;
    case 'TEXB0004':
      if (cursor.readInt() == null || cursor.readInt() == null) return null;
    default:
      return null;
  }
  final int? firstMipmapCount = cursor.readInt();
  if (firstMipmapCount == null || firstMipmapCount <= 0) return null;
  return (
    format: format,
    flags: flags,
    textureWidth: textureWidth,
    textureHeight: textureHeight,
    imageWidth: imageWidth,
    imageHeight: imageHeight,
    imageCount: imageCount,
    firstMipmapCount: firstMipmapCount,
  );
}

class _TextureCursor {
  _TextureCursor(Uint8List bytes)
    : _bytes = bytes,
      _data = ByteData.sublistView(bytes);

  final Uint8List _bytes;
  final ByteData _data;
  int _position = 0;

  String? readName() {
    final int start = _position;
    while (_position < _bytes.length && _position - start <= 16) {
      if (_bytes[_position++] == 0) {
        try {
          return utf8.decode(_bytes.sublist(start, _position - 1));
        } on FormatException {
          return null;
        }
      }
    }
    return null;
  }

  int? readInt() {
    if (_position + 4 > _bytes.length) return null;
    final int value = _data.getInt32(_position, Endian.little);
    _position += 4;
    return value;
  }
}
