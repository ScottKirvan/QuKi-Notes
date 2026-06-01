part of '../app_database.dart';

@DriftAccessor(tables: [Images])
class ImagesDao extends DatabaseAccessor<AppDatabase> with _$ImagesDaoMixin {
  ImagesDao(super.db);

  Future<List<ImageRecord>> getForQuki(String qukiId) =>
      (select(images)..where((t) => t.qukiId.equals(qukiId))).get();

  Stream<List<ImageRecord>> watchForQuki(String qukiId) =>
      (select(images)..where((t) => t.qukiId.equals(qukiId))).watch();

  Future<void> insertImage(ImagesCompanion entry) => into(images).insert(entry);

  Future<void> updateLocalPath(String id, String localPath) =>
      (update(images)..where((t) => t.id.equals(id)))
          .write(ImagesCompanion(localPath: Value(localPath)));
}
