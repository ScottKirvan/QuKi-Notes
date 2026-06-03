import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'registry_provider.dart';

String _key(String id) => 'transport.$id.enabled';

class TransportSettingsNotifier extends AsyncNotifier<Map<String, bool>> {
  @override
  Future<Map<String, bool>> build() async {
    final prefs = await SharedPreferences.getInstance();
    final registry = ref.read(transportRegistryProvider);
    return {
      for (final p in registry.plugins) p.id: prefs.getBool(_key(p.id)) ?? true,
    };
  }

  Future<void> setEnabled(String id, bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key(id), enabled);
    state = AsyncData({...?state.asData?.value, id: enabled});
  }
}

final transportSettingsProvider =
    AsyncNotifierProvider<TransportSettingsNotifier, Map<String, bool>>(
  TransportSettingsNotifier.new,
);
