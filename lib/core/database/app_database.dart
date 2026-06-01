import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';

part 'daos/qukis_dao.dart';
part 'daos/images_dao.dart';
part 'app_database.g.dart';

class Qukis extends Table {
  TextColumn get id => text()();
  TextColumn get body => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get modifiedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('ImageRecord')
class Images extends Table {
  TextColumn get id => text()();
  TextColumn get qukiId =>
      text().references(Qukis, #id, onDelete: KeyAction.cascade)();
  TextColumn get filename => text()();
  TextColumn get localPath => text().nullable()();
  IntColumn get bytes => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [Qukis, Images], daos: [QukisDao, ImagesDao])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openConnection());

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {},
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/quki_notes.sqlite');
    return NativeDatabase.createInBackground(file);
  });
}
