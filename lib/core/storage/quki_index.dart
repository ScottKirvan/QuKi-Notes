import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'quki_meta.dart';
import 'quki_storage.dart';
import 'storage_base_path_provider.dart';

final quKiStorageProvider = Provider<QuKiStorage>((ref) {
  final basePath = ref.watch(storageBasePathProvider);
  return QuKiStorage.fromPath(basePath);
});

class QuKiIndexNotifier extends AsyncNotifier<List<QuKiMeta>> {
  @override
  Future<List<QuKiMeta>> build() {
    final storage = ref.watch(quKiStorageProvider);
    return storage.scanActive();
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(
      () => ref.read(quKiStorageProvider).scanActive(),
    );
  }

  void addMeta(QuKiMeta meta) {
    state.whenData((list) {
      final updated = [meta, ...list]
        ..sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
      state = AsyncValue.data(updated);
    });
  }

  void updateMeta(String id, DateTime modifiedAt) {
    state.whenData((list) {
      final updated = [
        for (final m in list)
          if (m.id == id) m.copyWith(modifiedAt: modifiedAt) else m,
      ]..sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
      state = AsyncValue.data(updated);
    });
  }

  void removeMeta(String id) {
    state.whenData((list) {
      state = AsyncValue.data(list.where((m) => m.id != id).toList());
    });
  }
}

final quKiIndexProvider =
    AsyncNotifierProvider<QuKiIndexNotifier, List<QuKiMeta>>(
  QuKiIndexNotifier.new,
);

class TrashIndexNotifier extends AsyncNotifier<List<QuKiMeta>> {
  @override
  Future<List<QuKiMeta>> build() {
    final storage = ref.watch(quKiStorageProvider);
    return storage.scanTrash();
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(
      () => ref.read(quKiStorageProvider).scanTrash(),
    );
  }

  void addMeta(QuKiMeta meta) {
    state.whenData((list) {
      final updated = [meta, ...list]
        ..sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
      state = AsyncValue.data(updated);
    });
  }

  void removeMeta(String id) {
    state.whenData((list) {
      state = AsyncValue.data(list.where((m) => m.id != id).toList());
    });
  }
}

final trashIndexProvider =
    AsyncNotifierProvider<TrashIndexNotifier, List<QuKiMeta>>(
  TrashIndexNotifier.new,
);
