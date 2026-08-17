import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/app_info.dart';
import '../../core/storage/quki_index.dart';
import '../../core/storage/storage_location_service.dart';
import '../recently_deleted/recently_deleted_screen.dart';
import '../setup/storage_setup_screen.dart';

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

    final locationSvc = ref.watch(storageLocationServiceProvider);
    final isAppStorage = locationSvc.isAppStorage;
    final currentPath = locationSvc.basePath;

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
          sectionHeader('Storage'),
          if (isAppStorage)
            ListTile(
              title: const Text('App storage (private)'),
              subtitle: Text(
                'Files will be removed on uninstall. Change location.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            )
          else
            ListTile(
              title: const Text('Filesystem storage'),
              subtitle: Text(
                currentPath,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ListTile(
            title: const Text('Change location'),
            trailing: const Icon(LucideIcons.chevronRight),
            onTap: () => Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    const StorageSetupScreen(isChangingLocation: true),
              ),
            ).then((_) {
              // Refresh the active index when returning from the setup screen
              // in case the user changed location.
              if (context.mounted) {
                ref.read(quKiIndexProvider.notifier).refresh();
              }
            }),
          ),
          const Divider(indent: 16, endIndent: 16),
          sectionHeader('Notes'),
          ListTile(
            title: const Text('Trash'),
            trailing: const Icon(LucideIcons.chevronRight),
            onTap: () => Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (_) => const RecentlyDeletedScreen(),
              ),
            ),
          ),
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
              final versionText = 'v$version';
              return ListTile(
                title: const Text(kAppName),
                trailing: Text(versionText),
                onTap: () async {
                  await Clipboard.setData(ClipboardData(text: versionText));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Copied to clipboard.'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  }
                },
              );
            },
          ),
        ],
      ),
    );
  }
}
