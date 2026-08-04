class WallpaperInfo {
  final String id;
  final String title;
  final String contentRating;
  final List<String> tags;
  final String previews;
  final String type;
  final int? updateTime;
  final DateTime createTime;
  final String target;
  final String folder;
  final int size;

  WallpaperInfo({
    required this.id,
    required this.title,
    required this.contentRating,
    required this.tags,
    required this.previews,
    required this.type,
    required this.updateTime,
    required this.createTime,
    required this.target,
    required this.folder,
    required this.size,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is WallpaperInfo && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'WallpaperInfo{id: $id, title: $title, contentRating: $contentRating, tags: $tags, previews: $previews, type: $type, updateTime: $updateTime, createTime: $createTime, target: $target, folder: $folder, size: $size}\n';
  }
}
