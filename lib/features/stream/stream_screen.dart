import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import '../../core/database/database_provider.dart';
import '../editor/editor_screen.dart';
import '../settings/settings_screen.dart';

class StreamScreen extends ConsumerStatefulWidget {
  const StreamScreen({super.key});

  @override
  ConsumerState<StreamScreen> createState() => _StreamScreenState();
}

class _StreamScreenState extends ConsumerState<StreamScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    final text = _searchController.text.trim();
    if (text != _query) setState(() => _query = text);
  }

  @override
  void dispose() {
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

  Future<void> _openNew() async {
    if (!mounted) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => const EditorScreen()),
    );
  }

  Future<void> _openExisting(Quki quki) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => EditorScreen(qukiId: quki.id, initialBody: quki.body),
      ),
    );
  }

  Future<void> _delete(Quki quki) async {
    final db = ref.read(appDatabaseProvider);
    await db.qukisDao.softDelete(quki.id, DateTime.now());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Deleted: ${_preview(quki.body)}'),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => db.qukisDao.restoreQuki(quki.id),
        ),
      ),
    );
  }

  String _preview(String body) {
    if (body.isEmpty) return '(empty)';
    final first = body
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .firstOrNull
        ?.replaceAll(RegExp(r'^#+\s*'), '')
        .trim();
    if (first == null || first.isEmpty) return '(empty)';
    return first.length > 80 ? '${first.substring(0, 80)}…' : first;
  }

  String _relativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final m = months[dt.month - 1];
    final now = DateTime.now();
    return dt.year == now.year ? '$m ${dt.day}' : '$m ${dt.day}, ${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(appDatabaseProvider);
    // riverpod_generator 4.0.4-dev.1 cannot resolve drift-generated types from
    // part files, so the stream is consumed here via StreamBuilder rather than
    // a separate @riverpod provider. Revisit when generator handles part-file
    // types (or when riverpod_generator stable 4.x ships).
    final stream =
        _query.isEmpty ? db.qukisDao.watchAll() : db.qukisDao.search(_query);
    final scheme = Theme.of(context).colorScheme;

    final Widget screen = Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('QuKis'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'New QuKi',
            onPressed: _openNew,
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
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
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
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
            child: StreamBuilder<List<Quki>>(
              stream: stream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final qukis = snapshot.data!;
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
                  itemBuilder: (context, index) {
                    final quki = qukis[index];
                    return Dismissible(
                      key: ValueKey(quki.id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        color: scheme.error,
                        padding: const EdgeInsets.only(right: 20),
                        child: Icon(
                          Icons.delete_outline,
                          color: scheme.onError,
                        ),
                      ),
                      onDismissed: (_) => _delete(quki),
                      child: ListTile(
                        title: Text(
                          _preview(quki.body),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          _relativeTime(quki.modifiedAt),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        onTap: () => _openExisting(quki),
                      ),
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
          const SingleActivator(LogicalKeyboardKey.keyN, control: true): () {
            _openNew();
          },
        },
        child: Focus(autofocus: true, skipTraversal: true, child: screen),
      );
    }
    return screen;
  }
}
