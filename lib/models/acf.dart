class AcfInfo {
  final String id;
  final int size;
  final int time;

  AcfInfo({required this.id, required this.size, required this.time});

  // 用于创建WorkshopItemsInstalled中的AcfInfo对象
  factory AcfInfo.fromWorkshopInstalled(String id, Map<String, dynamic> json) {
    return AcfInfo(
      id: id,
      size: int.tryParse(json['size'].toString()) ?? 0,
      time: int.tryParse(json['timeupdated'].toString()) ?? 0,
    );
  }

  @override
  String toString() {
    return 'AcfInfo{id: $id, size: $size, time: $time}';
  }
}
