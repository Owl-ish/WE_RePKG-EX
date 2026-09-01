part of '../file_compare.dart';

Future<void> _showImageDialog(
  BuildContext context, {
  required FileImageSide first,
  required String title,
  required String unavailableText,
  required String zoomOutTooltip,
  required String resetViewTooltip,
  required String zoomInTooltip,
  required String linkViewsTooltip,
  required String unlinkViewsTooltip,
  String sideBySideLabel = 'Side by side',
  String overlayLabel = 'Overlay',
  String blinkLabel = 'Blink',
  String differenceLabel = 'Difference',
  String overlayOpacityLabel = 'New image opacity',
  String differenceSameHint = 'Black means matching pixels',
  String differenceIntensityLabel = 'Difference intensity',
  String differenceSizeMismatch =
      'Difference view requires matching image dimensions.',
  FileImageSide? second,
  bool directional = false,
}) => showDialog<void>(
  context: context,
  builder: (BuildContext context) {
    final Size screen = MediaQuery.sizeOf(context);
    return Dialog(
      key: const ValueKey<String>('file-image-compare-dialog'),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: min(1080.0, screen.width * .88),
        height: min(760.0, screen.height * .82),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    key: const ValueKey<String>('file-image-dialog-close'),
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Expanded(
                child: second == null
                    ? _ImagePane(
                        sideKey: 'single',
                        side: first,
                        unavailableText: unavailableText,
                        zoomOutTooltip: zoomOutTooltip,
                        resetViewTooltip: resetViewTooltip,
                        zoomInTooltip: zoomInTooltip,
                      )
                    : _ImageComparisonPair(
                        first: first,
                        second: second,
                        directional: directional,
                        unavailableText: unavailableText,
                        zoomOutTooltip: zoomOutTooltip,
                        resetViewTooltip: resetViewTooltip,
                        zoomInTooltip: zoomInTooltip,
                        linkViewsTooltip: linkViewsTooltip,
                        unlinkViewsTooltip: unlinkViewsTooltip,
                        sideBySideLabel: sideBySideLabel,
                        overlayLabel: overlayLabel,
                        blinkLabel: blinkLabel,
                        differenceLabel: differenceLabel,
                        overlayOpacityLabel: overlayOpacityLabel,
                        differenceSameHint: differenceSameHint,
                        differenceIntensityLabel: differenceIntensityLabel,
                        differenceSizeMismatch: differenceSizeMismatch,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  },
);

enum _ImageComparisonMode { sideBySide, overlay, blink, difference }

class _ImageComparisonPair extends StatefulWidget {
  const _ImageComparisonPair({
    required this.first,
    required this.second,
    required this.directional,
    required this.unavailableText,
    required this.zoomOutTooltip,
    required this.resetViewTooltip,
    required this.zoomInTooltip,
    required this.linkViewsTooltip,
    required this.unlinkViewsTooltip,
    required this.sideBySideLabel,
    required this.overlayLabel,
    required this.blinkLabel,
    required this.differenceLabel,
    required this.overlayOpacityLabel,
    required this.differenceSameHint,
    required this.differenceIntensityLabel,
    required this.differenceSizeMismatch,
  });

  final FileImageSide first;
  final FileImageSide second;
  final bool directional;
  final String unavailableText;
  final String zoomOutTooltip;
  final String resetViewTooltip;
  final String zoomInTooltip;
  final String linkViewsTooltip;
  final String unlinkViewsTooltip;
  final String sideBySideLabel;
  final String overlayLabel;
  final String blinkLabel;
  final String differenceLabel;
  final String overlayOpacityLabel;
  final String differenceSameHint;
  final String differenceIntensityLabel;
  final String differenceSizeMismatch;

  @override
  State<_ImageComparisonPair> createState() => _ImageComparisonPairState();
}

class _ImageComparisonPairState extends State<_ImageComparisonPair> {
  final TransformationController _firstController = TransformationController();
  final TransformationController _secondController = TransformationController();
  bool _linked = true;
  bool _syncing = false;
  _ImageComparisonMode _mode = _ImageComparisonMode.sideBySide;
  double _overlayOpacity = .5;
  double _differenceGain = 4;
  bool _blinkShowsSecond = false;
  Timer? _blinkTimer;

  @override
  void initState() {
    super.initState();
    _firstController.addListener(_syncFirstToSecond);
    _secondController.addListener(_syncSecondToFirst);
  }

  void _syncFirstToSecond() => _sync(_firstController, _secondController);

  void _syncSecondToFirst() => _sync(_secondController, _firstController);

  void _sync(
    TransformationController source,
    TransformationController destination,
  ) {
    if (!_linked || _syncing) return;
    _syncing = true;
    destination.value = source.value.clone();
    _syncing = false;
  }

  void _toggleLinked() {
    setState(() => _linked = !_linked);
    if (_linked) {
      _syncing = true;
      _secondController.value = _firstController.value.clone();
      _syncing = false;
    }
  }

  void _setMode(_ImageComparisonMode mode) {
    if (_mode == mode) return;
    _blinkTimer?.cancel();
    _blinkTimer = null;
    setState(() {
      _mode = mode;
      _blinkShowsSecond = false;
    });
    if (mode == _ImageComparisonMode.blink) {
      _blinkTimer = Timer.periodic(const Duration(milliseconds: 650), (_) {
        if (!mounted || _mode != _ImageComparisonMode.blink) return;
        setState(() => _blinkShowsSecond = !_blinkShowsSecond);
      });
    }
  }

  void _zoomComposite(double factor) {
    final next = _firstController.value.clone();
    final double currentScale = next.entry(0, 0).abs();
    final double targetScale = (currentScale * factor).clamp(.5, 8).toDouble();
    next.setEntry(0, 0, targetScale);
    next.setEntry(1, 1, targetScale);
    _firstController.value = next;
  }

  void _resetComposite() {
    _firstController.value = _firstController.value.clone()..setIdentity();
  }

  @override
  void dispose() {
    _blinkTimer?.cancel();
    _firstController.removeListener(_syncFirstToSecond);
    _secondController.removeListener(_syncSecondToFirst);
    _firstController.dispose();
    _secondController.dispose();
    super.dispose();
  }

  Widget _modeChip(
    _ImageComparisonMode mode,
    String label,
    IconData icon,
    String keyName,
  ) => ChoiceChip(
    key: ValueKey<String>('file-image-mode-$keyName'),
    label: Text(label),
    avatar: Icon(icon, size: 16),
    selected: _mode == mode,
    onSelected: (_) => _setMode(mode),
    visualDensity: VisualDensity.compact,
  );

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 6,
        runSpacing: 4,
        children: <Widget>[
          _modeChip(
            _ImageComparisonMode.sideBySide,
            widget.sideBySideLabel,
            Icons.view_column_outlined,
            'side-by-side',
          ),
          _modeChip(
            _ImageComparisonMode.overlay,
            widget.overlayLabel,
            Icons.layers_outlined,
            'overlay',
          ),
          _modeChip(
            _ImageComparisonMode.blink,
            widget.blinkLabel,
            Icons.visibility_outlined,
            'blink',
          ),
          _modeChip(
            _ImageComparisonMode.difference,
            widget.differenceLabel,
            Icons.difference_outlined,
            'difference',
          ),
          if (_mode == _ImageComparisonMode.sideBySide)
            IconButton(
              key: const ValueKey<String>('file-image-link-views'),
              tooltip: _linked
                  ? widget.unlinkViewsTooltip
                  : widget.linkViewsTooltip,
              onPressed: _toggleLinked,
              visualDensity: VisualDensity.compact,
              icon: Icon(
                _linked ? Icons.link_rounded : Icons.link_off_rounded,
                size: 18,
              ),
            ),
        ],
      ),
      if (_mode == _ImageComparisonMode.overlay)
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              '${widget.overlayOpacityLabel}: '
              '${(_overlayOpacity * 100).round()}%',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            SizedBox(
              width: min(320.0, MediaQuery.sizeOf(context).width * .32),
              child: Slider(
                key: const ValueKey<String>('file-image-overlay-opacity'),
                value: _overlayOpacity,
                onChanged: (double value) =>
                    setState(() => _overlayOpacity = value),
              ),
            ),
          ],
        ),
      if (_mode == _ImageComparisonMode.difference) ...<Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              '${widget.differenceIntensityLabel}: '
              '${_differenceGain.toStringAsFixed(0)}×',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            SizedBox(
              width: min(320.0, MediaQuery.sizeOf(context).width * .32),
              child: Slider(
                key: const ValueKey<String>('file-image-difference-intensity'),
                min: 1,
                max: 16,
                divisions: 15,
                value: _differenceGain,
                onChanged: (double value) =>
                    setState(() => _differenceGain = value),
              ),
            ),
          ],
        ),
        Text(
          widget.differenceSameHint,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
      const SizedBox(height: 4),
      Expanded(
        child: _mode == _ImageComparisonMode.sideBySide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Expanded(
                    child: _ImagePane(
                      sideKey: 'first',
                      side: widget.first,
                      controller: _firstController,
                      unavailableText: widget.unavailableText,
                      zoomOutTooltip: widget.zoomOutTooltip,
                      resetViewTooltip: widget.resetViewTooltip,
                      zoomInTooltip: widget.zoomInTooltip,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Icon(
                      widget.directional
                          ? Icons.arrow_forward_rounded
                          : Icons.compare_arrows_rounded,
                    ),
                  ),
                  Expanded(
                    child: _ImagePane(
                      sideKey: 'second',
                      side: widget.second,
                      controller: _secondController,
                      unavailableText: widget.unavailableText,
                      zoomOutTooltip: widget.zoomOutTooltip,
                      resetViewTooltip: widget.resetViewTooltip,
                      zoomInTooltip: widget.zoomInTooltip,
                    ),
                  ),
                ],
              )
            : _CompositeImagePane(
                first: widget.first,
                second: widget.second,
                mode: _mode,
                overlayOpacity: _overlayOpacity,
                differenceGain: _differenceGain,
                blinkShowsSecond: _blinkShowsSecond,
                controller: _firstController,
                unavailableText: widget.unavailableText,
                zoomOutTooltip: widget.zoomOutTooltip,
                resetViewTooltip: widget.resetViewTooltip,
                zoomInTooltip: widget.zoomInTooltip,
                differenceSizeMismatch: widget.differenceSizeMismatch,
                onZoomOut: () => _zoomComposite(.8),
                onReset: _resetComposite,
                onZoomIn: () => _zoomComposite(1.25),
              ),
      ),
    ],
  );
}

class _CompositeImagePane extends StatelessWidget {
  const _CompositeImagePane({
    required this.first,
    required this.second,
    required this.mode,
    required this.overlayOpacity,
    required this.differenceGain,
    required this.blinkShowsSecond,
    required this.controller,
    required this.unavailableText,
    required this.zoomOutTooltip,
    required this.resetViewTooltip,
    required this.zoomInTooltip,
    required this.differenceSizeMismatch,
    required this.onZoomOut,
    required this.onReset,
    required this.onZoomIn,
  });

  final FileImageSide first;
  final FileImageSide second;
  final _ImageComparisonMode mode;
  final double overlayOpacity;
  final double differenceGain;
  final bool blinkShowsSecond;
  final TransformationController controller;
  final String unavailableText;
  final String zoomOutTooltip;
  final String resetViewTooltip;
  final String zoomInTooltip;
  final String differenceSizeMismatch;
  final VoidCallback onZoomOut;
  final VoidCallback onReset;
  final VoidCallback onZoomIn;

  Widget _image(String filePath) => Image.file(
    File(filePath),
    fit: BoxFit.contain,
    errorBuilder: (_, _, _) => Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Text(unavailableText, textAlign: TextAlign.center),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final Color outline = Theme.of(context).colorScheme.outlineVariant;
    final Widget content = switch (mode) {
      _ImageComparisonMode.overlay => Stack(
        fit: StackFit.expand,
        children: <Widget>[
          _image(first.path),
          Opacity(opacity: overlayOpacity, child: _image(second.path)),
        ],
      ),
      _ImageComparisonMode.blink => _image(
        blinkShowsSecond ? second.path : first.path,
      ),
      _ImageComparisonMode.difference => _DifferenceImage(
        firstPath: first.path,
        secondPath: second.path,
        unavailableText: unavailableText,
        sizeMismatchText: differenceSizeMismatch,
        gain: differenceGain,
      ),
      _ImageComparisonMode.sideBySide => const SizedBox.shrink(),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          '${first.label}  ↔  ${second.label}',
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        Text(
          '${path.basename(first.path)}  ↔  ${path.basename(second.path)}',
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        SizedBox(
          height: 30,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              IconButton(
                key: const ValueKey<String>('file-image-composite-zoom-out'),
                tooltip: zoomOutTooltip,
                onPressed: onZoomOut,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.remove_rounded, size: 18),
              ),
              IconButton(
                key: const ValueKey<String>('file-image-composite-reset'),
                tooltip: resetViewTooltip,
                onPressed: onReset,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.center_focus_strong_rounded, size: 17),
              ),
              IconButton(
                key: const ValueKey<String>('file-image-composite-zoom-in'),
                tooltip: zoomInTooltip,
                onPressed: onZoomIn,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.add_rounded, size: 18),
              ),
            ],
          ),
        ),
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: outline),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: InteractiveViewer(
                transformationController: controller,
                minScale: .5,
                maxScale: 8,
                child: SizedBox.expand(child: content),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DifferenceImage extends StatefulWidget {
  const _DifferenceImage({
    required this.firstPath,
    required this.secondPath,
    required this.unavailableText,
    required this.sizeMismatchText,
    required this.gain,
  });

  final String firstPath;
  final String secondPath;
  final String unavailableText;
  final String sizeMismatchText;
  final double gain;

  @override
  State<_DifferenceImage> createState() => _DifferenceImageState();
}

class _DifferenceImageState extends State<_DifferenceImage> {
  ui.Image? _first;
  ui.Image? _second;
  bool _loading = true;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _DifferenceImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.firstPath != widget.firstPath ||
        oldWidget.secondPath != widget.secondPath) {
      _load();
    }
  }

  Future<void> _load() async {
    final int generation = ++_generation;
    if (mounted) setState(() => _loading = true);
    final ui.Image? first = await _decodeUiImage(widget.firstPath);
    final ui.Image? second = await _decodeUiImage(widget.secondPath);
    if (!mounted || generation != _generation) {
      first?.dispose();
      second?.dispose();
      return;
    }
    _first?.dispose();
    _second?.dispose();
    setState(() {
      _first = first;
      _second = second;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _generation++;
    _first?.dispose();
    _second?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final ui.Image? first = _first;
    final ui.Image? second = _second;
    if (first == null || second == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(widget.unavailableText, textAlign: TextAlign.center),
        ),
      );
    }
    if (first.width != second.width || first.height != second.height) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(widget.sizeMismatchText, textAlign: TextAlign.center),
        ),
      );
    }
    return CustomPaint(
      key: const ValueKey<String>('file-image-difference-view'),
      painter: _DifferencePainter(first, second, widget.gain),
      child: const SizedBox.expand(),
    );
  }
}

Future<ui.Image?> _decodeUiImage(String filePath) async {
  ui.Codec? codec;
  try {
    final bytes = await File(filePath).readAsBytes();
    codec = await ui.instantiateImageCodec(bytes);
    final ui.FrameInfo frame = await codec.getNextFrame();
    return frame.image;
  } on FileSystemException {
    return null;
  } catch (_) {
    return null;
  } finally {
    codec?.dispose();
  }
}

class _DifferencePainter extends CustomPainter {
  const _DifferencePainter(this.first, this.second, this.gain);

  final ui.Image first;
  final ui.Image second;
  final double gain;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final double scale = min(
      size.width / first.width,
      size.height / first.height,
    );
    final Size fitted = Size(first.width * scale, first.height * scale);
    final Rect destination = Rect.fromLTWH(
      (size.width - fitted.width) / 2,
      (size.height - fitted.height) / 2,
      fitted.width,
      fitted.height,
    );
    final Rect source = Rect.fromLTWH(
      0,
      0,
      first.width.toDouble(),
      first.height.toDouble(),
    );
    canvas.saveLayer(
      destination,
      Paint()
        ..colorFilter = ColorFilter.matrix(<double>[
          gain,
          0,
          0,
          0,
          0,
          0,
          gain,
          0,
          0,
          0,
          0,
          0,
          gain,
          0,
          0,
          0,
          0,
          0,
          1,
          0,
        ]),
    );
    canvas.drawImageRect(first, source, destination, Paint());
    canvas.drawImageRect(
      second,
      source,
      destination,
      Paint()..blendMode = BlendMode.difference,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _DifferencePainter oldDelegate) =>
      oldDelegate.first != first ||
      oldDelegate.second != second ||
      oldDelegate.gain != gain;
}

typedef _ImageFileInfo = ({int bytes, int width, int height, String format});

Future<_ImageFileInfo?> _readImageInfo(String filePath) async {
  final File file = File(filePath);
  if (!await file.exists()) return null;
  ui.ImageDescriptor? descriptor;
  ui.ImmutableBuffer? buffer;
  try {
    final FileStat stat = await file.stat();
    buffer = await ui.ImmutableBuffer.fromUint8List(await file.readAsBytes());
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    final String extension = path.extension(filePath).replaceFirst('.', '');
    return (
      bytes: stat.size,
      width: descriptor.width,
      height: descriptor.height,
      format: extension.isEmpty ? 'IMAGE' : extension.toUpperCase(),
    );
  } on FileSystemException {
    return null;
  } catch (_) {
    return null;
  } finally {
    descriptor?.dispose();
    buffer?.dispose();
  }
}

class _ImagePane extends StatefulWidget {
  const _ImagePane({
    required this.sideKey,
    required this.side,
    required this.unavailableText,
    required this.zoomOutTooltip,
    required this.resetViewTooltip,
    required this.zoomInTooltip,
    this.controller,
  });

  final String sideKey;
  final FileImageSide side;
  final String unavailableText;
  final String zoomOutTooltip;
  final String resetViewTooltip;
  final String zoomInTooltip;
  final TransformationController? controller;

  @override
  State<_ImagePane> createState() => _ImagePaneState();
}

class _ImagePaneState extends State<_ImagePane> {
  late Future<_ImageFileInfo?> _info;
  TransformationController? _ownedController;

  TransformationController get _controller =>
      widget.controller ?? _ownedController!;

  @override
  void initState() {
    super.initState();
    _info = _readImageInfo(widget.side.path);
    if (widget.controller == null) {
      _ownedController = TransformationController();
    }
  }

  @override
  void didUpdateWidget(covariant _ImagePane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.side.path != widget.side.path) {
      _info = _readImageInfo(widget.side.path);
    }
    if (oldWidget.controller != widget.controller) {
      _ownedController?.dispose();
      _ownedController = widget.controller == null
          ? TransformationController()
          : null;
    }
  }

  void _zoom(double factor) {
    final next = _controller.value.clone();
    final double currentScale = next.entry(0, 0).abs();
    final double targetScale = (currentScale * factor).clamp(.5, 8).toDouble();
    next.setEntry(0, 0, targetScale);
    next.setEntry(1, 1, targetScale);
    _controller.value = next;
  }

  void _resetView() {
    _controller.value = _controller.value.clone()..setIdentity();
  }

  @override
  void dispose() {
    _ownedController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color outline = Theme.of(context).colorScheme.outlineVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          widget.side.label,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 3),
        Text(
          path.basename(widget.side.path),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 3),
        SizedBox(
          height: 18,
          child: FutureBuilder<_ImageFileInfo?>(
            future: _info,
            builder:
                (
                  BuildContext context,
                  AsyncSnapshot<_ImageFileInfo?> snapshot,
                ) {
                  final _ImageFileInfo? info = snapshot.data;
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(
                      child: SizedBox.square(
                        dimension: 12,
                        child: CircularProgressIndicator(strokeWidth: 1.5),
                      ),
                    );
                  }
                  if (info == null) return const SizedBox.shrink();
                  return Text(
                    '${info.width} × ${info.height}  •  ${_formatBytes(info.bytes)}  •  ${info.format}',
                    key: ValueKey<String>(
                      'file-image-info-${widget.side.path}',
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  );
                },
          ),
        ),
        SizedBox(
          height: 30,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              IconButton(
                key: ValueKey<String>('file-image-${widget.sideKey}-zoom-out'),
                tooltip: widget.zoomOutTooltip,
                onPressed: () => _zoom(.8),
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.remove_rounded, size: 18),
              ),
              IconButton(
                key: ValueKey<String>('file-image-${widget.sideKey}-reset'),
                tooltip: widget.resetViewTooltip,
                onPressed: _resetView,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.center_focus_strong_rounded, size: 17),
              ),
              IconButton(
                key: ValueKey<String>('file-image-${widget.sideKey}-zoom-in'),
                tooltip: widget.zoomInTooltip,
                onPressed: () => _zoom(1.25),
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.add_rounded, size: 18),
              ),
            ],
          ),
        ),
        const SizedBox(height: 3),
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: outline),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: InteractiveViewer(
                transformationController: _controller,
                minScale: .5,
                maxScale: 8,
                child: Center(
                  child: Image.file(
                    File(widget.side.path),
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        widget.unavailableText,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
