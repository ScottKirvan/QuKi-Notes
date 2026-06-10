import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import 'plugins/clipboard_toss.dart';
import 'plugins/share_sheet_toss.dart';
import 'registry.dart';
import 'transport_plugin.dart';
import 'transport_settings_notifier.dart';

final _log = Logger('TransportRegistry');

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
    // Return empty list while loading — prevents disabled transports from
    // flashing as enabled during the async SharedPreferences read (#post-96).
    loading: () => [],
    error: (err, st) {
      _log.warning(
          'enabledTransportsProvider: failed to load settings; '
          'falling back to all plugins enabled',
          err,
          st);
      return registry.plugins;
    },
  );
});
