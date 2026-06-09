import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:quki_notes/core/database/app_database.dart';
import 'package:quki_notes/features/editor/auto_save_controller.dart';

/// Fake [QukisDaoWritable] that throws on every write — used to verify that
/// [AutoSaveController] swallows and logs DB exceptions rather than crashing.
class _ThrowingDao implements QukisDaoWritable {
  @override
  Future<void> insertQuki(QukisCompanion entry) async =>
      throw Exception('insert failed');

  @override
  Future<void> updateQuki(QukisCompanion entry) async =>
      throw Exception('update failed');
}

// Short durations so tests run fast without fake_async.
const _debounce = Duration(milliseconds: 20);
const _periodic = Duration(milliseconds: 100);
// Padding to avoid flakiness on slow CI.
const _debounceWait = Duration(milliseconds: 60);
const _periodicWait = Duration(milliseconds: 250);

void main() {
  late AppDatabase db;
  late AutoSaveController controller;
  var body = '';

  AutoSaveController makeController({String? initialId}) {
    controller = AutoSaveController(
      dao: db.qukisDao,
      getBody: () => body,
      initialId: initialId,
      debounceDelay: _debounce,
      periodicInterval: _periodic,
    );
    return controller;
  }

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    body = '';
  });

  tearDown(() async {
    controller.dispose();
    await db.close();
  });

  group('AutoSaveController.save', () {
    test('does nothing when body is empty', () async {
      makeController();
      controller.start();
      await controller.save();
      expect(await db.qukisDao.watchAll().first, isEmpty);
    });

    test('inserts a new row on first call', () async {
      body = 'hello world';
      makeController();
      controller.start();
      await controller.save();
      final rows = await db.qukisDao.watchAll().first;
      expect(rows.length, 1);
      expect(rows.first.body, 'hello world');
      expect(controller.savedId, isNotNull);
    });

    test('updates the same row on subsequent calls', () async {
      body = 'first';
      makeController();
      controller.start();
      await controller.save();
      final id = controller.savedId!;

      body = 'updated';
      await controller.save();

      final rows = await db.qukisDao.watchAll().first;
      expect(rows.length, 1);
      expect(rows.first.body, 'updated');
      expect(rows.first.id, id);
    });

    test('uses initialId to update an existing row', () async {
      final now = DateTime(2026, 1, 1);
      await db.qukisDao.insertQuki(QukisCompanion.insert(
        id: 'existing',
        body: const Value('old'),
        createdAt: now,
        modifiedAt: now,
      ));

      body = 'new content';
      makeController(initialId: 'existing');
      controller.start();
      await controller.save();

      final rows = await db.qukisDao.watchAll().first;
      expect(rows.length, 1);
      expect(rows.first.body, 'new content');
      expect(rows.first.id, 'existing');
    });
  });

  group('AutoSaveController.flush', () {
    test('saves immediately and cancels pending debounce', () async {
      body = 'flush test';
      makeController();
      controller.start();

      controller.notifyChanged(); // arms debounce
      await controller.flush(); // should save now, cancel debounce

      final rows = await db.qukisDao.watchAll().first;
      expect(rows.length, 1);
      expect(rows.first.body, 'flush test');

      // Wait for debounce window — should not insert a second row.
      await Future<void>.delayed(_debounceWait);
      expect(await db.qukisDao.watchAll().first, hasLength(1));
    });
  });

  group('AutoSaveController.notifyChanged debounce', () {
    test('saves after debounce delay elapses', () async {
      body = 'debounced save';
      makeController();
      controller.start();

      controller.notifyChanged();
      await Future<void>.delayed(_debounceWait);

      final rows = await db.qukisDao.watchAll().first;
      expect(rows.length, 1);
      expect(rows.first.body, 'debounced save');
    });

    test('multiple rapid calls only trigger one save', () async {
      body = 'rapid';
      makeController();
      controller.start();

      for (var i = 0; i < 5; i++) {
        controller.notifyChanged();
        await Future<void>.delayed(Duration(milliseconds: 5));
      }
      await Future<void>.delayed(_debounceWait);

      expect(await db.qukisDao.watchAll().first, hasLength(1));
    });
  });

  group('AutoSaveController periodic timer', () {
    test('saves once per interval', () async {
      body = 'periodic content';
      makeController();
      controller.start();

      await Future<void>.delayed(_periodicWait);

      final rows = await db.qukisDao.watchAll().first;
      expect(rows.length, 1);
      expect(rows.first.body, 'periodic content');
    });
  });

  group('AutoSaveController.resetForQuki', () {
    test('subsequent save updates the new target QuKi — regression: #36 #38',
        () async {
      final now = DateTime(2026, 1, 1);
      await db.qukisDao.insertQuki(QukisCompanion.insert(
        id: 'existing-quki',
        body: const Value('old body'),
        createdAt: now,
        modifiedAt: now,
      ));

      // Controller starts blank (no initialId)
      body = 'new content';
      makeController();
      controller.start();

      // Reset to target the existing QuKi
      controller.resetForQuki(id: 'existing-quki');
      await controller.save();

      // Must update the existing row, not insert a new one
      final rows = await db.qukisDao.watchAll().first;
      expect(rows.length, 1);
      expect(rows.first.id, 'existing-quki');
      expect(rows.first.body, 'new content');
      expect(controller.savedId, 'existing-quki');
    });

    test('resetForQuki to null causes next save to insert a new row', () async {
      body = 'first quki';
      makeController();
      controller.start();
      await controller.save();
      expect(controller.savedId, isNotNull);

      // Reset to blank — next save should create a new QuKi
      controller.resetForQuki(id: null);
      body = 'second quki';
      await controller.save();

      final rows = await db.qukisDao.watchAll().first;
      expect(rows.length, 2);
      expect(
          rows.map((r) => r.body), containsAll(['first quki', 'second quki']));
    });
  });

  group('AutoSaveController DB exception handling', () {
    test(
        'save does not throw when insert raises an exception — '
        'regression: silent data loss on DB error', () async {
      final logged = <LogRecord>[];
      final sub = Logger('AutoSaveController').onRecord.listen(logged.add);
      addTearDown(sub.cancel);

      final throwingController = AutoSaveController(
        dao: _ThrowingDao(),
        getBody: () => 'hello',
        debounceDelay: _debounce,
        periodicInterval: _periodic,
      );
      addTearDown(throwingController.dispose);

      // Must not throw — exception should be caught and logged.
      await expectLater(throwingController.save(), completes);

      // Verify the exception was logged at SEVERE level.
      expect(logged, isNotEmpty);
      expect(logged.first.level, Level.SEVERE);
    });

    test(
        'save does not throw when update raises an exception — '
        'regression: silent data loss on DB error', () async {
      final logged = <LogRecord>[];
      final sub = Logger('AutoSaveController').onRecord.listen(logged.add);
      addTearDown(sub.cancel);

      // initialId triggers the update path.
      final throwingController = AutoSaveController(
        dao: _ThrowingDao(),
        getBody: () => 'hello',
        initialId: 'existing-id',
        debounceDelay: _debounce,
        periodicInterval: _periodic,
      );
      addTearDown(throwingController.dispose);

      await expectLater(throwingController.save(), completes);

      expect(logged, isNotEmpty);
      expect(logged.first.level, Level.SEVERE);
    });
  });
}
