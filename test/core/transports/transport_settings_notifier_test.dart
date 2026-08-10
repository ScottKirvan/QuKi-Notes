import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:quki_notes/core/transports/registry.dart';
import 'package:quki_notes/core/transports/registry_provider.dart';
import 'package:quki_notes/core/transports/transport_plugin.dart';
import 'package:quki_notes/core/transports/transport_settings_notifier.dart';

/// Minimal stub transport for test purposes only.
class _StubTransport extends TransportPlugin {
  const _StubTransport(this._id);

  final String _id;

  @override
  String get id => _id;

  @override
  String get displayName => _id;

  @override
  String get description => 'stub';

  @override
  Future<TransportResult> transport({
    required String markdown,
    required List<TransportImage> images,
    required TransportContext ctx,
  }) async =>
      TransportResult(success: true);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('TransportSettingsNotifier — persistence across restart', () {
    test(
        'disabled transport stays disabled after notifier is recreated — '
        'regression: loading-race caused disabled transports to appear enabled (#post-96)',
        () async {
      final registry = TransportRegistry(plugins: [
        const _StubTransport('alpha'),
        const _StubTransport('beta'),
      ]);

      // First container: disable 'alpha'.
      final c1 = ProviderContainer(overrides: [
        transportRegistryProvider.overrideWithValue(registry),
      ]);
      addTearDown(c1.dispose);

      // Wait for initial load.
      final notifier = c1.read(transportSettingsProvider.notifier);
      await c1.read(transportSettingsProvider.future);

      await notifier.setEnabled('alpha', false);

      // Verify disabled in first container.
      final s1 = c1.read(transportSettingsProvider).asData!.value;
      expect(s1['alpha'], isFalse);
      expect(s1['beta'], isTrue);

      // Second container: simulates app restart — reads SharedPreferences again.
      final c2 = ProviderContainer(overrides: [
        transportRegistryProvider.overrideWithValue(registry),
      ]);
      addTearDown(c2.dispose);

      final s2 = await c2.read(transportSettingsProvider.future);

      // 'alpha' must still be disabled after restart.
      expect(s2['alpha'], isFalse,
          reason:
              'Disabled transport must remain disabled after app restart (SharedPreferences reload)');
      expect(s2['beta'], isTrue);
    });

    test(
        'enabledTransportsProvider returns empty list while settings are loading — '
        'regression: loading state returned all plugins, causing disabled transports '
        'to flash as enabled (#post-96)', () async {
      // Verify that the loading branch of enabledTransportsProvider returns []
      // rather than all plugins. We inspect the provider synchronously before
      // the async SharedPreferences read completes.
      final registry = TransportRegistry(plugins: [
        const _StubTransport('alpha'),
        const _StubTransport('beta'),
      ]);

      final container = ProviderContainer(overrides: [
        transportRegistryProvider.overrideWithValue(registry),
      ]);
      addTearDown(container.dispose);

      // Read synchronously — the async notifier is still loading.
      final settings = container.read(transportSettingsProvider);
      expect(settings.isLoading, isTrue,
          reason: 'Settings should still be loading at this point');

      final enabled = container.read(enabledTransportsProvider);
      expect(enabled, isEmpty,
          reason:
              'enabledTransportsProvider must return [] while settings are loading, '
              'not all plugins');
    });
  });
}
