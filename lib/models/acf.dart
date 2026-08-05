class AcfInfo {
  final String id;
  final int size;
  final int time;

  /// Steam's content version, changing only when the author republishes. Too
  /// wide for an int, and only ever compared for equality.
  final String? manifest;

  AcfInfo({
    required this.id,
    required this.size,
    required this.time,
    this.manifest,
  });

  // 用于创建WorkshopItemsInstalled中的AcfInfo对象
  factory AcfInfo.fromWorkshopInstalled(String id, Map<String, dynamic> json) {
    return AcfInfo(
      id: id,
      size: int.tryParse(json['size'].toString()) ?? 0,
      time: int.tryParse(json['timeupdated'].toString()) ?? 0,
      manifest: json['manifest']?.toString(),
    );
  }

  @override
  String toString() {
    return 'AcfInfo{id: $id, size: $size, time: $time, manifest: $manifest}';
  }
}
