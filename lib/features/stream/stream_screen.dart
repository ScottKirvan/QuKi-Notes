import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../app.dart';
import '../../core/database/app_database.dart';
import '../../core/database/database_provider.dart';
import '../../shared/relative_time.dart';
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
  Timer? _undoTimer;

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

  void _openExisting(Quki quki) {
    ref.read(activeQukiIdProvider.notifier).setId(quki.id);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete(Quki quki) async {
    final db = ref.read(appDatabaseProvider);
    // Capture messenger before async gap so context is never stale below.
    final messenger = ScaffoldMessenger.of(context);
    await db.qukisDao.softDelete(quki.id, DateTime.now());
    if (!mounted) return;
    _undoTimer?.cancel();
    messenger.clearSnackBars();
    final controller = messenger.showSnackBar(
      SnackBar(
        content: Text('Deleted: ${_preview(quki.body)}'),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            _undoTimer?.cancel();
            _undoTimer = null;
            db.qukisDao.restoreQuki(quki.id);
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

  String _preview(String body) {
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
        title: const Text('QuKis'),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.plus),
            tooltip: 'New QuKi',
            onPressed: _openNew,
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
                          LucideIcons.trash2,
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
                          relativeTime(quki.modifiedAt),
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
          const SingleActivator(LogicalKeyboardKey.keyN, control: true):
              _openNew,
        },
        child: Focus(autofocus: true, skipTraversal: true, child: screen),
      );
    }
    return screen;
  }
}
