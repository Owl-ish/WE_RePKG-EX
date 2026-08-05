/// What the memory ceiling setting means on the machine as it is right now.
///
/// Asking for more than is free is not an error, which is why this is advice
/// and not a clamp: Windows pages, RePKG serialises its conversions rather than
/// failing, and a reading taken a moment ago has no authority over a setting
/// the user will extract with later. Worth saying out loud all the same.
({int? freeMb, bool exceedsFree}) memoryAdvice({
  required int settingMb,
  required int? availableBytes,
}) {
  if (availableBytes == null) return (freeMb: null, exceedsFree: false);
  final int freeMb = availableBytes ~/ (1024 * 1024);
  return (freeMb: freeMb, exceedsFree: settingMb > freeMb);
}

/// Megabytes as gigabytes to one decimal, which is how the numbers either side
/// of this comparison are worth reading: 6.1 GB, not 6231 MB.
String formatGb(int megabytes) => '${(megabytes / 1024).toStringAsFixed(1)} GB';
