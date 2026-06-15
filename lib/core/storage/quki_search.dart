import 'quki_meta.dart';
import 'quki_storage.dart';

Future<List<QuKiMeta>> search(
  String query,
  List<QuKiMeta> index,
  QuKiStorage storage,
) async {
  if (query.isEmpty) return index;
  final lower = query.toLowerCase();
  final results = <QuKiMeta>[];
  for (final meta in index) {
    final body = await storage.read(meta.id);
    if (body.toLowerCase().contains(lower)) {
      results.add(meta);
    }
  }
  return results;
}
