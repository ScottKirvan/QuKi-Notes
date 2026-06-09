part of '../app_database.dart';

@DriftAccessor(tables: [Qukis])
class QukisDao extends DatabaseAccessor<AppDatabase>
    with _$QukisDaoMixin
    implements QukisDaoWritable {
  QukisDao(super.db);

  Stream<List<Quki>> watchAll() => (select(qukis)
        ..where((t) => t.deletedAt.isNull())
        ..orderBy([(t) => OrderingTerm.desc(t.modifiedAt)]))
      .watch();

  Stream<Quki?> watchById(String id) =>
      (select(qukis)..where((t) => t.id.equals(id))).watchSingleOrNull();

  Future<Quki?> getById(String id) =>
      (select(qukis)..where((t) => t.id.equals(id))).getSingleOrNull();

  Stream<List<Quki>> search(String query) => (select(qukis)
        ..where((t) =>
            t.deletedAt.isNull() &
            t.body.lower().like('%${query.toLowerCase()}%'))
        ..orderBy([(t) => OrderingTerm.desc(t.modifiedAt)]))
      .watch();

  @override
  Future<void> insertQuki(QukisCompanion entry) => into(qukis).insert(entry);

  @override
  Future<void> updateQuki(QukisCompanion entry) =>
      (update(qukis)..where((t) => t.id.equals(entry.id.value))).write(entry);

  Future<void> softDelete(String id, DateTime at) =>
      (update(qukis)..where((t) => t.id.equals(id)))
          .write(QukisCompanion(deletedAt: Value(at)));

  Future<void> restoreQuki(String id) =>
      (update(qukis)..where((t) => t.id.equals(id)))
          .write(QukisCompanion(deletedAt: Value(null)));

  Future<int> hardDeleteBefore(DateTime threshold) => (delete(qukis)
        ..where((t) =>
            t.deletedAt.isNotNull() &
            t.deletedAt.isSmallerThanValue(threshold)))
      .go();
}
