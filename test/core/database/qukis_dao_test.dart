import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quki_notes/core/database/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  group('QukisDao.watchAll', () {
    test('returns empty list initially', () async {
      final result = await db.qukisDao.watchAll().first;
      expect(result, isEmpty);
    });

    test('returns inserted qukis newest-first', () async {
      final older = DateTime(2026, 1, 1);
      final newer = DateTime(2026, 1, 2);
      await db.qukisDao.insertQuki(QukisCompanion.insert(
        id: 'a',
        createdAt: older,
        modifiedAt: older,
      ));
      await db.qukisDao.insertQuki(QukisCompanion.insert(
        id: 'b',
        createdAt: newer,
        modifiedAt: newer,
      ));
      final result = await db.qukisDao.watchAll().first;
      expect(result.map((q) => q.id).toList(), ['b', 'a']);
    });

    test('edited quki rises to top by modifiedAt', () async {
      final older = DateTime(2026, 1, 1);
      final newer = DateTime(2026, 1, 2);
      await db.qukisDao.insertQuki(QukisCompanion.insert(
        id: 'a',
        createdAt: older,
        modifiedAt: older,
      ));
      await db.qukisDao.insertQuki(QukisCompanion.insert(
        id: 'b',
        createdAt: newer,
        modifiedAt: newer,
      ));
      // 'a' was created first but is now edited — should move to top.
      await db.qukisDao.updateQuki(QukisCompanion(
        id: const Value('a'),
        body: const Value('edited'),
        modifiedAt: Value(newer.add(const Duration(seconds: 1))),
      ));
      final result = await db.qukisDao.watchAll().first;
      expect(result.map((q) => q.id).toList(), ['a', 'b']);
    });

    test('excludes soft-deleted qukis', () async {
      final now = DateTime(2026, 1, 1);
      await db.qukisDao.insertQuki(QukisCompanion.insert(
        id: 'x',
        createdAt: now,
        modifiedAt: now,
      ));
      await db.qukisDao.softDelete('x', now);
      final result = await db.qukisDao.watchAll().first;
      expect(result, isEmpty);
    });
  });

  group('QukisDao.watchById', () {
    test('returns null for unknown id', () async {
      final result = await db.qukisDao.watchById('unknown').first;
      expect(result, isNull);
    });

    test('returns quki after insert', () async {
      final now = DateTime(2026, 1, 1);
      await db.qukisDao.insertQuki(QukisCompanion.insert(
        id: 'q1',
        body: const Value('hello'),
        createdAt: now,
        modifiedAt: now,
      ));
      final result = await db.qukisDao.watchById('q1').first;
      expect(result?.body, 'hello');
    });
  });

  group('QukisDao.restoreQuki', () {
    test('clears deletedAt so row reappears in watchAll', () async {
      final now = DateTime(2026, 1, 1);
      await db.qukisDao.insertQuki(QukisCompanion.insert(
        id: 'r1',
        createdAt: now,
        modifiedAt: now,
      ));
      await db.qukisDao.softDelete('r1', now);
      expect(await db.qukisDao.watchAll().first, isEmpty);

      await db.qukisDao.restoreQuki('r1');
      expect(await db.qukisDao.watchAll().first, hasLength(1));

      final row = await db.qukisDao.watchById('r1').first;
      expect(row?.deletedAt, isNull);
    });
  });

  group('QukisDao.hardDeleteBefore', () {
    test('removes soft-deleted rows older than threshold', () async {
      final past = DateTime(2026, 1, 1);
      await db.qukisDao.insertQuki(QukisCompanion.insert(
        id: 'old',
        createdAt: past,
        modifiedAt: past,
      ));
      await db.qukisDao.softDelete('old', past);
      final count = await db.qukisDao.hardDeleteBefore(DateTime(2099, 1, 1));
      expect(count, 1);
      expect(await db.qukisDao.watchById('old').first, isNull);
    });

    test('does not remove soft-deleted rows newer than threshold', () async {
      final future = DateTime(2099, 1, 1);
      await db.qukisDao.insertQuki(QukisCompanion.insert(
        id: 'new',
        createdAt: future,
        modifiedAt: future,
      ));
      await db.qukisDao.softDelete('new', future);
      final count = await db.qukisDao.hardDeleteBefore(DateTime(2026, 1, 1));
      expect(count, 0);
    });
  });

  group('QukisDao.search', () {
    test('filters by body text', () async {
      final now = DateTime(2026, 1, 1);
      await db.qukisDao.insertQuki(QukisCompanion.insert(
        id: 's1',
        body: const Value('buy milk'),
        createdAt: now,
        modifiedAt: now,
      ));
      await db.qukisDao.insertQuki(QukisCompanion.insert(
        id: 's2',
        body: const Value('call dentist'),
        createdAt: now,
        modifiedAt: now,
      ));
      final result = await db.qukisDao.search('milk').first;
      expect(result.length, 1);
      expect(result.first.id, 's1');
    });

    test('excludes soft-deleted qukis from search results', () async {
      final now = DateTime(2026, 1, 1);
      await db.qukisDao.insertQuki(QukisCompanion.insert(
        id: 'del',
        body: const Value('deleted milk'),
        createdAt: now,
        modifiedAt: now,
      ));
      await db.qukisDao.softDelete('del', now);
      final result = await db.qukisDao.search('milk').first;
      expect(result, isEmpty);
    });
  });
}
