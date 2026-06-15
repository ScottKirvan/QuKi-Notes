import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../core/storage/quki_index.dart';
import '../../core/storage/quki_meta.dart';
import '../../core/storage/quki_storage.dart';
import '../../shared/relative_time.dart';

class RecentlyDeletedScreen extends ConsumerStatefulWidget {
  const RecentlyDeletedScreen({super.key});

  @override
  ConsumerState<RecentlyDeletedScreen> createState() =>
      _RecentlyDeletedScreenState();
}

class _RecentlyDeletedScreenState extends ConsumerState<RecentlyDeletedScreen> {
  static final _headingPattern = RegExp(r'^#+\s*');

  @override
  void initState() {
    super.initState();
    // Refresh trash on open to pick up external file changes.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(trashIndexProvider.notifier).refresh();
    });
  }

  String _previewFromBody(String body) {
    if (body.isEmpty) return '(empty)';
    final first = body
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .firstOrNull
        ?.replaceAll(_headingPattern, '')
        .trim();
    if (first == null || first.isEmpty) return '(empty)';
    return first.length > 80 ? '${first.substring(0, 80)}…' : first;
  }

  Future<void> _restore(QuKiMeta meta) async {
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore note?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final storage = ref.read(quKiStorageProvider);
    await storage.restore(meta.id);
    ref.read(trashIndexProvider.notifier).removeMeta(meta.id);
    await ref.read(quKiIndexProvider.notifier).refresh();
    if (mounted) Navigator.pop(context);
  }

  // Called from tile's onDismissed — confirmation already handled in tile's
  // confirmDismiss so no second dialog here.
  Future<void> _hardDelete(QuKiMeta meta) async {
    if (!mounted) return;
    final storage = ref.read(quKiStorageProvider);
    await storage.hardDelete(meta.id);
    ref.read(trashIndexProvider.notifier).removeMeta(meta.id);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final trashAsync = ref.watch(trashIndexProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Trash')),
      body: trashAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (trashed) {
          if (trashed.isEmpty) {
            return Center(
              child: Text(
                'No notes in Trash.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            );
          }
          return ListView.builder(
            itemCount: trashed.length,
            itemBuilder: (context, i) {
              final meta = trashed[i];
              return _TrashedTile(
                key: ValueKey(meta.id),
                meta: meta,
                storage: ref.read(quKiStorageProvider),
                previewFromBody: _previewFromBody,
                onRestore: _restore,
                onHardDelete: _hardDelete,
              );
            },
          );
        },
      ),
    );
  }
}

class _TrashedTile extends StatefulWidget {
  const _TrashedTile({
    super.key,
    required this.meta,
    required this.storage,
    required this.previewFromBody,
    required this.onRestore,
    required this.onHardDelete,
  });

  final QuKiMeta meta;
  final QuKiStorage storage;
  final String Function(String body) previewFromBody;
  final Future<void> Function(QuKiMeta) onRestore;
  final Future<void> Function(QuKiMeta) onHardDelete;

  @override
  State<_TrashedTile> createState() => _TrashedTileState();
}

class _TrashedTileState extends State<_TrashedTile> {
  String? _preview;

  @override
  void initState() {
    super.initState();
    _loadPreview();
  }

  Future<void> _loadPreview() async {
    try {
      final body = await widget.storage.readTrash(widget.meta.id);
      if (mounted) setState(() => _preview = widget.previewFromBody(body));
    } catch (_) {
      if (mounted) setState(() => _preview = '(empty)');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey('trash_dismiss_${widget.meta.id}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        return showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete permanently?'),
            content: const Text('This QuKi cannot be recovered.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        );
      },
      onDismissed: (_) => widget.onHardDelete(widget.meta),
      background: Container(
        alignment: Alignment.centerRight,
        color: Theme.of(context).colorScheme.error,
        padding: const EdgeInsets.only(right: 20),
        child: Icon(
          LucideIcons.trash2,
          color: Theme.of(context).colorScheme.onError,
        ),
      ),
      child: ListTile(
        title: Text(
          _preview ?? '…',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          relativeTime(widget.meta.modifiedAt),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        onTap: () => widget.onRestore(widget.meta),
      ),
    );
  }
}
