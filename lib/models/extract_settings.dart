import 'dart:math';

/// Ceiling on the textures one RePKG converts at once. Past this, more threads
/// bought almost nothing: a 15 texture scene ran 8.3s on eight and 4.8s on
/// sixteen, for twice the memory.
const int _maxTextureThreads = 8;

/// Smallest share worth giving a worker. Below roughly this, every texture is
/// larger than the whole share and conversions serialise.
const int _minProcessMemoryMb = 192;

/// How many wallpapers to extract at once, how many textures each may convert,
/// and how much memory each is allowed to hold.
class ExtractPlan {
  const ExtractPlan({
    required this.concurrency,
    required this.threads,
    required this.memoryMb,
  });

  final int concurrency;
  final int threads;
  final int memoryMb;
}

/// How many textures one RePKG may convert at once, given how many wallpapers
/// are already running side by side. Dividing keeps the two levels from
/// multiplying, and scales with whatever the machine has: 2 threads each on a
/// four core box, 8 on a sixteen core one.
int textureThreads({required int cores, required int concurrency}) =>
    max(1, cores ~/ max(1, concurrency)).clamp(1, _maxTextureThreads);

/// Sized once per batch, because a worker cannot re-derive it: the pool runs no
/// more workers than there are wallpapers, so one that only knew the setting
/// would size itself for company it does not have.
///
/// The memory figure is a ceiling handed to RePKG, not a prediction. Peak
/// follows the largest texture, which only RePKG sees.
ExtractPlan extractPlan({
  required int requested,
  required int batchSize,
  required int cores,
  required int totalMemoryMb,
}) {
  final int concurrency = max(1, min(max(1, requested), batchSize));
  return ExtractPlan(
    concurrency: concurrency,
    threads: textureThreads(cores: cores, concurrency: concurrency),
    memoryMb: max(_minProcessMemoryMb, totalMemoryMb ~/ concurrency),
  );
}

/// What a batch runs under, read before the first worker starts. None of it
/// changes mid-batch, and reading it here keeps the WidgetRef out of the
/// workers, where it would be provider state reached for after an await.
class ExtractSettings {
  const ExtractSettings({
    required this.rePKGPath,
    required this.excludeTexture,
    required this.onlySaveImage,
    required this.deleteTransparency,
    required this.overwrite,
    required this.useTitleName,
    required this.newFlags,
    required this.supportsThreads,
    required this.plan,
  });

  final String? rePKGPath;
  final bool excludeTexture;
  final bool onlySaveImage;
  final bool deleteTransparency;
  final bool overwrite;
  final bool useTitleName;

  /// Whether the tool on disk understands the flags added since 0.5.3-ex, and
  /// the ones since 0.5.4-ex. An older RePKG exits 0 having written nothing
  /// when handed an option it does not know.
  final bool newFlags;
  final bool supportsThreads;

  final ExtractPlan plan;
}
