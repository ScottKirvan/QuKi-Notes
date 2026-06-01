import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quki_notes/core/database/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<void> insertQuki(String id) => db.qukisDao.insertQuki(
        QukisCompanion.insert(
          id: id,
          createdAt: DateTime(2026, 1, 1),
          modifiedAt: DateTime(2026, 1, 1),
        ),
      );

  group('ImagesDao', () {
    test('insert and getForQuki returns the image', () async {
      await insertQuki('q1');
      await db.imagesDao.insertImage(ImagesCompanion.insert(
        id: 'img1',
        qukiId: 'q1',
        filename: '2026-01-01-abc12345.jpg',
      ));
      final result = await db.imagesDao.getForQuki('q1');
      expect(result.length, 1);
      expect(result.first.filename, '2026-01-01-abc12345.jpg');
    });

    test('getForQuki returns empty for unknown qukiId', () async {
      final result = await db.imagesDao.getForQuki('no-such-quki');
      expect(result, isEmpty);
    });

    test('cascade delete removes images when quki is hard-deleted', () async {
      await insertQuki('q2');
      await db.imagesDao.insertImage(ImagesCompanion.insert(
        id: 'img2',
        qukiId: 'q2',
        filename: '2026-01-01-def67890.jpg',
      ));
      await (db.delete(db.qukis)..where((t) => t.id.equals('q2'))).go();
      final result = await db.imagesDao.getForQuki('q2');
      expect(result, isEmpty);
    });

    test('updateLocalPath persists the path', () async {
      await insertQuki('q3');
      await db.imagesDao.insertImage(ImagesCompanion.insert(
        id: 'img3',
        qukiId: 'q3',
        filename: '2026-01-01-ghi11111.jpg',
      ));
      await db.imagesDao
          .updateLocalPath('img3', '/data/images/2026-01-01-ghi11111.jpg');
      final result = await db.imagesDao.getForQuki('q3');
      expect(result.first.localPath, '/data/images/2026-01-01-ghi11111.jpg');
    });
  });
}
