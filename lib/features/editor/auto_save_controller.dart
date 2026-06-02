import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:uuid/uuid.dart';

import '../../core/database/app_database.dart';

// Implements ADR-6: 2s idle debounce + 30s periodic + lifecycle saves.
// Phase 1.3 save-on-leave bridge (ADR-20) is superseded by this controller.
class AutoSaveController {
  AutoSaveController({
    required QukisDao dao,
    required String Function() getBody,
    String? initialId,
    this.debounceDelay = const Duration(seconds: 2),
    this.periodicInterval = const Duration(seconds: 30),
  })  : _dao = dao,
        _getBody = getBody,
        _savedId = initialId;

  final QukisDao _dao;
  final String Function() _getBody;

  // Exposed for tests; read-only after construction.
  final Duration debounceDelay;
  final Duration periodicInterval;

  String? _savedId;
  String? get savedId => _savedId;

  Timer? _debounce;
  Timer? _periodic;

  void start() {
    _periodic = Timer.periodic(periodicInterval, (_) => save());
  }

  // Call on every document change to reset the idle debounce.
  void notifyChanged() {
    _debounce?.cancel();
    _debounce = Timer(debounceDelay, save);
  }

  // Cancel any pending debounce and save immediately.
  // Use this when the user explicitly navigates away.
  Future<void> flush() async {
    _debounce?.cancel();
    _debounce = null;
    await save();
  }

  Future<void> save() async {
    final body = _getBody();
    if (body.isEmpty) return;
    final now = DateTime.now();
    if (_savedId != null) {
      await _dao.updateQuki(QukisCompanion(
        id: Value(_savedId!),
        body: Value(body),
        modifiedAt: Value(now),
      ));
    } else {
      final id = const Uuid().v4();
      _savedId = id;
      await _dao.insertQuki(QukisCompanion(
        id: Value(id),
        body: Value(body),
        createdAt: Value(now),
        modifiedAt: Value(now),
      ));
    }
  }

  void dispose() {
    _debounce?.cancel();
    _periodic?.cancel();
  }
}
