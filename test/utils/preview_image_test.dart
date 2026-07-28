import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as path;
import 'package:we_repkg/utils/preview_image.dart';

/// An animated GIF of solid grey frames, one per value.
Uint8List gif(List<int> greys) {
  final img.Image anim = img.Image(width: 8, height: 8, numChannels: 3);
  for (int i = 0; i < greys.length; i++) {
    final img.Image frame = i == 0 ? anim : anim.addFrame();
    frame.frameDuration = 40;
    img.fill(frame, color: img.ColorRgb8(greys[i], greys[i], greys[i]));
  }
  return img.encodeGif(anim, dither: img.DitherKernel.none);
}

Future<ui.Codec> decode(Uint8List bytes) async {
  final descriptor = await ui.ImageDescriptor.encoded(
    await ui.ImmutableBuffer.fromUint8List(bytes),
  );
  final ui.Codec codec = await descriptor.instantiateCodec();
  descriptor.dispose();
  return codec;
}

/// Top-left pixel of each frame the codec hands out, over [pulls] frames.
Future<List<int>> play(ui.Codec codec, int pulls) async {
  final List<int> out = <int>[];
  for (int i = 0; i < pulls; i++) {
    final ui.FrameInfo frame = await codec.getNextFrame();
    final ByteData? px = await frame.image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    out.add(px!.getUint8(0));
    frame.image.dispose();
  }
  return out;
}

/// A codec whose frames arrive only when the test says so, to aim a dispose at
/// the moment a decode is suspended.
class _GatedCodec implements ui.Codec {
  _GatedCodec(this._inner);

  final ui.Codec _inner;
  final List<Completer<void>> _waiting = <Completer<void>>[];
  int disposals = 0;

  Future<void> letOneThrough() async {
    while (_waiting.isEmpty) {
      await pumpEventQueue();
    }
    _waiting.removeAt(0).complete();
    await pumpEventQueue();
  }

  @override
  int get frameCount => _inner.frameCount;

  @override
  int get repetitionCount => _inner.repetitionCount;

  @override
  Future<ui.FrameInfo> getNextFrame() async {
    final gate = Completer<void>();
    _waiting.add(gate);
    await gate.future;
    return _inner.getNextFrame();
  }

  @override
  void dispose() {
    disposals++;
    _inner.dispose();
  }
}

/// Stands in for a truncated or malformed preview.
class _BrokenCodec implements ui.Codec {
  bool disposed = false;

  @override
  int get frameCount => 4;

  @override
  int get repetitionCount => -1;

  @override
  Future<ui.FrameInfo> getNextFrame() async => throw Exception('bad frame');

  @override
  void dispose() => disposed = true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a black opening frame never plays, on any loop', () async {
    final ui.Codec codec = await trimBlackLead(
      await decode(gif(<int>[0, 60, 120, 200])),
    );

    expect(codec.frameCount, 3);
    // Two passes. One is not enough: skipping the lead frame only the first
    // time round looks fixed until the loop wraps.
    expect(await play(codec, 6), <int>[60, 120, 200, 60, 120, 200]);
    codec.dispose();
  });

  test('an ordinary animation keeps all its frames', () async {
    final ui.Codec codec = await trimBlackLead(
      await decode(gif(<int>[60, 120, 200])),
    );

    expect(codec.frameCount, 3);
    expect(await play(codec, 6), <int>[60, 120, 200, 60, 120, 200]);
    codec.dispose();
  });

  test('two frames opening on black leaves a still', () async {
    final ui.Codec codec = await trimBlackLead(
      await decode(gif(<int>[0, 200])),
    );

    expect(codec.frameCount, 1);
    expect(await play(codec, 2), <int>[200, 200]);
    codec.dispose();
  });

  test('an all black animation still plays', () async {
    final ui.Codec codec = await trimBlackLead(
      await decode(gif(<int>[0, 0, 0])),
    );

    expect(codec.frameCount, 2);
    expect(await play(codec, 4), <int>[0, 0, 0, 0]);
    codec.dispose();
  });

  test('a still image is handed straight back', () async {
    final ui.Codec inner = await decode(gif(<int>[0]));

    // Identical, not just equivalent: one frame must not pay for a pixel scan.
    expect(identical(await trimBlackLead(inner), inner), isTrue);
    inner.dispose();
  });

  test('disposing mid decode frees the inner codec once, after it', () async {
    final gated = _GatedCodec(await decode(gif(<int>[0, 60, 120])));
    final Future<ui.Codec> trimming = trimBlackLead(gated);
    await gated.letOneThrough();
    final ui.Codec codec = await trimming;

    final Future<ui.FrameInfo> pull = codec.getNextFrame();
    await pumpEventQueue();
    // The image stream frees its codec the moment the last listener leaves,
    // which for a grid tile is any scroll. That lands here.
    codec.dispose();
    expect(gated.disposals, 0, reason: 'a decode is still in flight');

    await gated.letOneThrough();
    (await pull).image.dispose();
    expect(gated.disposals, 1);

    codec.dispose();
    expect(gated.disposals, 1, reason: 'dispose is idempotent');
  });

  test('a codec that cannot decode its first frame is not leaked', () async {
    final _BrokenCodec broken = _BrokenCodec();

    await expectLater(trimBlackLead(broken), throwsA(isA<Exception>()));

    // Nothing owns it until trimBlackLead returns, so if it does not free a
    // codec it gave up on, nothing will.
    expect(broken.disposed, isTrue);
  });

  testWidgets('a preview loads off disk and paints', (tester) async {
    final Directory dir = Directory.systemTemp.createTempSync('we_repkg_gif');
    addTearDown(() => dir.deleteSync(recursive: true));
    final File file = File(path.join(dir.path, 'preview.gif'))
      ..writeAsBytesSync(gif(<int>[0, 60, 120]));

    // The only test that runs the whole chain: file, decode, trim, widget.
    // Everything else stops at the codec or the cache key, so a break in the
    // wiring between them would leave every preview blank and every test green.
    await tester.runAsync(() async {
      await tester.pumpWidget(
        Image(image: previewImage(file.path, cacheHeight: 32)),
      );
      // Real file IO, so it needs real time rather than the fake clock.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await tester.pump();
    });

    expect(tester.takeException(), isNull);
    expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
  });

  test('the key resolves without waiting a microtask', () {
    // An async obtainKey defers the resolve past the frame that asked for it,
    // which blanks a tile the moment its parent changes. That was the white
    // flash on first hover.
    expect(
      previewImage(
        'a.gif',
        cacheHeight: 270,
      ).obtainKey(ImageConfiguration.empty),
      isA<SynchronousFuture<Object>>(),
    );
  });

  test('two providers for one preview share a cache slot', () async {
    const ImageConfiguration config = ImageConfiguration.empty;
    expect(
      await previewImage('a.gif').obtainKey(config),
      await previewImage('a.gif').obtainKey(config),
    );
    expect(
      await previewImage('a.gif', cacheHeight: 64).obtainKey(config),
      isNot(await previewImage('a.gif').obtainKey(config)),
    );
  });
}
