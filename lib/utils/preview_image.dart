import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// Provider for a wallpaper preview. Pass [cacheHeight] to decode at the size
/// the grid draws it; the detail dialog wants full resolution and omits it.
ImageProvider<Object> previewImage(String path, {int? cacheHeight}) =>
    _TrimBlackLead(
      ResizeImage.resizeIfNeeded(null, cacheHeight, FileImage(File(path))),
    );

/// Hides a black opening frame in an animated preview.
///
/// Wallpaper Engine sometimes starts recording preview.gif before the scene
/// draws, leaving frame 0 pure black. Nobody notices on the first pass, only
/// each time the loop comes back round, which is why it looks like a fault at
/// the end.
@immutable
class _TrimBlackLead extends ImageProvider<_Key> {
  const _TrimBlackLead(this.inner);

  final ImageProvider<Object> inner;

  /// Must stay synchronous when [inner] is, or a cached image paints a frame
  /// late and anything rebuilt into a new spot in the tree blanks meanwhile.
  /// Shape copied from [ResizeImage.obtainKey].
  @override
  Future<_Key> obtainKey(ImageConfiguration config) {
    Completer<_Key>? completer;
    SynchronousFuture<_Key>? sync;
    inner.obtainKey(config).then<void>((Object key) {
      if (completer == null) {
        sync = SynchronousFuture<_Key>(_Key(key));
      } else {
        completer.complete(_Key(key));
      }
    });
    if (sync != null) return sync!;
    completer = Completer<_Key>();
    return completer.future;
  }

  @override
  ImageStreamCompleter loadImage(_Key key, ImageDecoderCallback decode) {
    Future<ui.Codec> trim(
      ui.ImmutableBuffer buffer, {
      ui.TargetImageSizeCallback? getTargetSize,
    }) async {
      return trimBlackLead(await decode(buffer, getTargetSize: getTargetSize));
    }

    return inner.loadImage(key.inner, trim);
  }

  @override
  bool operator ==(Object other) =>
      other is _TrimBlackLead &&
      other.runtimeType == runtimeType &&
      other.inner == inner;

  @override
  int get hashCode => inner.hashCode;
}

/// Wraps the inner key so trimmed and untrimmed copies get separate cache slots.
@immutable
class _Key {
  const _Key(this.inner);

  final Object inner;

  @override
  bool operator ==(Object other) =>
      other is _Key && other.runtimeType == runtimeType && other.inner == inner;

  @override
  int get hashCode => Object.hash(runtimeType, inner);
}

/// Returns [codec] as-is unless its first frame is black, in which case the
/// wrapper skips that frame on every pass. Still images short-circuit.
@visibleForTesting
Future<ui.Codec> trimBlackLead(ui.Codec codec) async {
  if (codec.frameCount < 2) return codec;

  final ui.FrameInfo first;
  try {
    first = await codec.getNextFrame();
  } catch (_) {
    // Nobody owns this codec until we return it, so a throw here strands it.
    codec.dispose();
    rethrow;
  }

  if (await _isBlack(first.image)) {
    first.image.dispose();
    return _Trimmed(codec, null);
  }
  return _Trimmed(codec, first);
}

/// Every seventeenth pixel, not sixteenth: preview widths are usually a
/// multiple of 16, and a stride that divides the row keeps hitting the same
/// columns.
Future<bool> _isBlack(ui.Image image) async {
  final ByteData? data = await image.toByteData(
    format: ui.ImageByteFormat.rawRgba,
  );
  if (data == null) return false;
  final Uint8List px = data.buffer.asUint8List(
    data.offsetInBytes,
    data.lengthInBytes,
  );
  for (int i = 0; i + 2 < px.length; i += 68) {
    if (px[i] != 0 || px[i + 1] != 0 || px[i + 2] != 0) return false;
  }
  return true;
}

class _Trimmed implements ui.Codec {
  _Trimmed(this._inner, ui.FrameInfo? first)
    : _held = first,
      _trim = first == null;

  final ui.Codec _inner;

  /// Frame 0, already decoded to inspect it, handed back on the first pull.
  ui.FrameInfo? _held;
  final bool _trim;

  /// Which inner frame came back last. Frame 0 is already gone, hence zero.
  int _at = 0;
  bool _dead = false;

  /// Pulls suspended on an await. The image stream frees its codec as soon as
  /// the last listener leaves, which for a grid tile is any scroll, so a
  /// dispose can land mid-decode and the last one out has to do the freeing.
  int _busy = 0;

  @override
  int get frameCount => _trim ? _inner.frameCount - 1 : _inner.frameCount;

  @override
  int get repetitionCount => _inner.repetitionCount;

  @override
  Future<ui.FrameInfo> getNextFrame() async {
    final ui.FrameInfo? held = _held;
    if (held != null) {
      _held = null;
      return held;
    }

    _busy++;
    try {
      ui.FrameInfo frame = await _inner.getNextFrame();
      _at = (_at + 1) % _inner.frameCount;
      if (_trim && _at == 0 && !_dead) {
        final ui.FrameInfo next = await _inner.getNextFrame();
        frame.image.dispose();
        frame = next;
        _at = 1;
      }
      return frame;
    } finally {
      _busy--;
      if (_dead && _busy == 0) _inner.dispose();
    }
  }

  @override
  void dispose() {
    if (_dead) return;
    _dead = true;
    _held?.image.dispose();
    _held = null;
    if (_busy == 0) _inner.dispose();
  }
}
