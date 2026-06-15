class QuKiMeta {
  const QuKiMeta({
    required this.id,
    required this.filePath,
    required this.createdAt,
    required this.modifiedAt,
  });

  final String id;
  final String filePath;
  final DateTime createdAt;
  final DateTime modifiedAt;

  QuKiMeta copyWith({String? filePath, DateTime? modifiedAt}) => QuKiMeta(
        id: id,
        filePath: filePath ?? this.filePath,
        createdAt: createdAt,
        modifiedAt: modifiedAt ?? this.modifiedAt,
      );
}
