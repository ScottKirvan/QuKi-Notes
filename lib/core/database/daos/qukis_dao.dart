part of '../app_database.dart';

@DriftAccessor(tables: [Qukis])
class QukisDao extends DatabaseAccessor<AppDatabase> with _$QukisDaoMixin {
  QukisDao(super.db);

  Stream<List<Quki>> watchAll() => (select(qukis)
        ..where((t) => t.deletedAt.isNull())
        ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
      .watch();

  Stream<Quki?> watchById(String id) =>
      (select(qukis)..where((t) => t.id.equals(id))).watchSingleOrNull();

  Stream<List<Quki>> search(String query) => (select(qukis)
        ..where((t) => t.deletedAt.isNull() & t.body.like('%$query%'))
        ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
      .watch();

  Future<void> insertQuki(QukisCompanion entry) => into(qukis).insert(entry);

  Future<void> updateQuki(QukisCompanion entry) =>
      (update(qukis)..where((t) => t.id.equals(entry.id.value))).write(entry);

  Future<void> softDelete(String id, DateTime at) =>
      (update(qukis)..where((t) => t.id.equals(id)))
          .write(QukisCompanion(deletedAt: Value(at)));

  Future<int> hardDeleteBefore(DateTime threshold) => (delete(qukis)
        ..where((t) =>
            t.deletedAt.isNotNull() &
            t.deletedAt.isSmallerThanValue(threshold)))
      .go();
}
