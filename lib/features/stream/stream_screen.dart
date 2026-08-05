import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../app.dart';
import '../../core/storage/quki_index.dart';
import '../../core/storage/quki_meta.dart';
import '../../core/storage/quki_search.dart' as qs;
import '../../core/storage/quki_storage.dart';
import '../../shared/relative_time.dart';
import '../settings/help_dialog.dart';
import '../settings/settings_screen.dart';

class StreamScreen extends ConsumerStatefulWidget {
  const StreamScreen({super.key});

  @override
  ConsumerState<StreamScreen> createState() => _StreamScreenState();
}

class _StreamScreenState extends ConsumerState<StreamScreen> {
  static final _headingPattern = RegExp(r'^#+\s*');
  final _searchController = TextEditingController();
  String _query = '';
  List<QuKiMeta>? _searchResults;
  bool _searching = false;
  Timer? _undoTimer;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(quKiIndexProvider.notifier).refresh();
    });
  }

  void _onSearchChanged() {
    final text = _searchController.text.trim();
    if (text == _query) return;
    setState(() {
      _query = text;
      _searchResults = null;
    });
    if (text.isNotEmpty) {
      _runSearch(text);
    }
  }

  Future<void> _runSearch(String query) async {
    setState(() => _searching = true);
    final index = ref.read(quKiIndexProvider).asData?.value ?? [];
    final storage = ref.read(quKiStorageProvider);
    final results = await qs.search(query, index, storage);
    if (!mounted || _query != query) return;
    setState(() {
      _searchResults = results;
      _searching = false;
    });
  }

  @override
  void dispose() {
    _undoTimer?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openSettings() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
  }

  void _openNew() {
    ref.read(activeQukiIdProvider.notifier).setId(null);
    if (mounted) Navigator.pop(context);
  }

  void _openExisting(QuKiMeta meta) {
    ref.read(activeQukiIdProvider.notifier).setId(meta.id);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete(QuKiMeta meta) async {
    final storage = ref.read(quKiStorageProvider);
    final messenger = ScaffoldMessenger.of(context);
    await storage.softDelete(meta.id);
    ref.read(quKiIndexProvider.notifier).removeMeta(meta.id);
    // If the trashed QuKi is the one currently open in the editor, reset to
    // a blank new note so the editor isn't pointing at a deleted file.
    if (ref.read(activeQukiIdProvider) == meta.id) {
      ref.read(activeQukiIdProvider.notifier).setId(null);
    }
    if (!mounted) return;
    _undoTimer?.cancel();
    messenger.clearSnackBars();
    final controller = messenger.showSnackBar(
      SnackBar(
        content: const Text('QuKi moved to Trash.'),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            _undoTimer?.cancel();
            _undoTimer = null;
            storage.restore(meta.id);
            ref.read(quKiIndexProvider.notifier).addMeta(meta);
          },
        ),
      ),
    );
    // Flutter 3.44 + Material 3: SnackBar with SnackBarAction does not reliably
    // auto-dismiss via the internal timer when an action is present. Drive
    // dismissal with an explicit Timer to guarantee the 4s timeout.
    _undoTimer = Timer(const Duration(seconds: 4), () {
      _undoTimer = null;
      controller.close();
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final indexAsync = ref.watch(quKiIndexProvider);

    final Widget screen = Scaffold(
      appBar: AppBar(
        title: const Text('QuKis'),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.plus),
            tooltip: 'New QuKi',
            onPressed: _openNew,
          ),
          IconButton(
            icon: const Icon(LucideIcons.circleHelp),
            tooltip: 'Help',
            onPressed: () => showHelpDialog(context),
          ),
          IconButton(
            icon: const Icon(LucideIcons.settings),
            tooltip: 'Settings',
            onPressed: _openSettings,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search…',
                prefixIcon: const Icon(LucideIcons.search),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(LucideIcons.x),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _query = '';
                            _searchResults = null;
                          });
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
                filled: true,
                isDense: true,
              ),
            ),
          ),
          Expanded(
            child: indexAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (index) {
                if (_query.isNotEmpty && _searching) {
                  return const Center(child: CircularProgressIndicator());
                }
                final qukis =
                    _query.isNotEmpty ? (_searchResults ?? []) : index;
                if (qukis.isEmpty) {
                  return Center(
                    child: Text(
                      _query.isEmpty
                          ? 'No QuKis yet.\nTap + to capture your first thought.'
                          : 'No results for "$_query".',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  );
                }
                return ListView.builder(
                  itemCount: qukis.length,
                  itemBuilder: (context, i) {
                    final meta = qukis[i];
                    return _QuKiTile(
                      key: ValueKey(meta.id),
                      meta: meta,
                      storage: ref.read(quKiStorageProvider),
                      previewFromBody: _previewFromBody,
                      onDelete: _delete,
                      onOpen: _openExisting,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );

    if (Platform.isWindows || Platform.isLinux) {
      return CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyN, control: true):
              _openNew,
        },
        child: Focus(autofocus: true, skipTraversal: true, child: screen),
      );
    }
    return screen;
  }
}

/// Stateful tile that loads and caches its body preview from the file.
class _QuKiTile extends StatefulWidget {
  const _QuKiTile({
    super.key,
    required this.meta,
    required this.storage,
    required this.previewFromBody,
    required this.onDelete,
    required this.onOpen,
  });

  final QuKiMeta meta;
  final QuKiStorage storage;
  final String Function(String body) previewFromBody;
  final Future<void> Function(QuKiMeta) onDelete;
  final void Function(QuKiMeta) onOpen;

  @override
  State<_QuKiTile> createState() => _QuKiTileState();
}

class _QuKiTileState extends State<_QuKiTile> {
  String? _preview;

  @override
  void initState() {
    super.initState();
    _loadPreview();
  }

  Future<void> _loadPreview() async {
    try {
      final body = await widget.storage.read(widget.meta.id);
      if (mounted) setState(() => _preview = widget.previewFromBody(body));
    } catch (_) {
      if (mounted) setState(() => _preview = '(empty)');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey('dismiss_${widget.meta.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        color: Theme.of(context).colorScheme.error,
        padding: const EdgeInsets.only(right: 20),
        child: Icon(
          LucideIcons.trash2,
          color: Theme.of(context).colorScheme.onError,
        ),
      ),
      onDismissed: (_) => widget.onDelete(widget.meta),
      child: ListTile(
        visualDensity: const VisualDensity(horizontal: 0, vertical: -4),
        title: Text(
          _preview ?? '…',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          relativeTime(widget.meta.modifiedAt),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        onTap: () => widget.onOpen(widget.meta),
      ),
    );
  }
}
