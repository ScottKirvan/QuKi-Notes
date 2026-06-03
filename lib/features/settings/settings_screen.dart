import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/app_info.dart';
import '../../core/transports/registry_provider.dart';
import '../../core/transports/transport_settings_notifier.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final labelStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          letterSpacing: 1.1,
        );

    Widget sectionHeader(String title) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
          child: Text(title.toUpperCase(), style: labelStyle),
        );

    final registry = ref.watch(transportRegistryProvider);
    final settings = ref.watch(transportSettingsProvider);
    final notifier = ref.read(transportSettingsProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          sectionHeader('Appearance'),
          const ListTile(
            title: Text('Theme'),
            trailing: Text('System'),
          ),
          const Divider(indent: 16, endIndent: 16),
          sectionHeader('Transports'),
          if (registry.plugins.isEmpty)
            const ListTile(
              title: Text('No transports installed'),
              subtitle: Text('Toss plugins land in Phase 2.'),
              enabled: false,
            )
          else
            ...registry.plugins.map((p) {
              final enabled = settings.when(
                data: (map) => map[p.id] ?? true,
                loading: () => true,
                error: (_, __) => true,
              );
              return SwitchListTile(
                title: Text(p.displayName),
                subtitle: Text(p.description),
                value: enabled,
                onChanged: (v) => notifier.setEnabled(p.id, v),
              );
            }),
          const Divider(indent: 16, endIndent: 16),
          sectionHeader('Sync'),
          const ListTile(
            title: Text('No sync backends installed'),
            subtitle: Text('Sync is opt-in — coming in v1.1+.'),
            enabled: false,
          ),
          const Divider(indent: 16, endIndent: 16),
          sectionHeader('About'),
          FutureBuilder<PackageInfo>(
            future: PackageInfo.fromPlatform(),
            builder: (context, snapshot) {
              final version = snapshot.data?.version ?? '…';
              return ListTile(
                title: const Text(kAppName),
                trailing: Text('v$version'),
              );
            },
          ),
        ],
      ),
    );
  }
}
