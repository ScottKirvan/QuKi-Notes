import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'plugins/clipboard_toss.dart';
import 'plugins/share_sheet_toss.dart';
import 'registry.dart';
import 'transport_plugin.dart';
import 'transport_settings_notifier.dart';

final transportRegistryProvider = Provider<TransportRegistry>(
  (ref) =>
      const TransportRegistry(plugins: [ClipboardToss(), ShareSheetToss()]),
);

// Plugins the user has enabled — use this for the toss picker.
final enabledTransportsProvider = Provider<List<TransportPlugin>>((ref) {
  final registry = ref.watch(transportRegistryProvider);
  final settings = ref.watch(transportSettingsProvider);
  return settings.when(
    data: (enabled) =>
        registry.plugins.where((p) => enabled[p.id] ?? true).toList(),
    loading: () => registry.plugins,
    error: (_, __) => registry.plugins,
  );
});
