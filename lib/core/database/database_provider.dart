import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:quki_notes/core/database/app_database.dart';

part 'database_provider.g.dart';

@Riverpod(keepAlive: true)
AppDatabase appDatabase(Ref ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
}
