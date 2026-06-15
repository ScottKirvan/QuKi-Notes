import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quki_notes/core/storage/quki_search.dart' as qs;
import 'package:quki_notes/core/storage/quki_storage.dart';

void main() {
  late Directory tmpDir;
  late QuKiStorage storage;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('quki_search_test_');
    storage = QuKiStorage(tmpDir);
  });

  tearDown(() async {
    await tmpDir.delete(recursive: true);
  });

  test('returns all items for empty query', () async {
    final a = await storage.create('buy milk');
    final b = await storage.create('call dentist');
    final index = [a, b];
    final results = await qs.search('', index, storage);
    expect(results.length, 2);
  });

  test('filters by body content case-insensitively', () async {
    final a = await storage.create('buy MILK please');
    final b = await storage.create('call dentist');
    final index = [a, b];

    final results = await qs.search('milk', index, storage);
    expect(results.length, 1);
    expect(results.first.id, a.id);
  });

  test('returns empty when no match', () async {
    final a = await storage.create('buy milk');
    final index = [a];
    final results = await qs.search('zzz', index, storage);
    expect(results, isEmpty);
  });

  test('matches multiple items', () async {
    final a = await storage.create('go to the store');
    final b = await storage.create('store the leftovers');
    final c = await storage.create('call dentist');
    final index = [a, b, c];

    final results = await qs.search('store', index, storage);
    expect(results.length, 2);
    expect(results.map((m) => m.id), containsAll([a.id, b.id]));
  });
}
