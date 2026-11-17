class VideoDirectory {
  final int? id;
  final String path;
  final String? projectId;
  final DateTime addedAt;

  VideoDirectory({
    this.id,
    required this.path,
    this.projectId,
    required this.addedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'path': path,
      'project_id': projectId,
      'added_at': addedAt.toIso8601String(),
    };
  }

  factory VideoDirectory.fromMap(Map<String, dynamic> map) {
    return VideoDirectory(
      id: map['id'],
      path: map['path'],
      projectId: map['project_id'],
      addedAt: DateTime.parse(map['added_at']),
    );
  }
}
