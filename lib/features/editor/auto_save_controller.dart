import 'dart:async';

import 'package:logging/logging.dart';

final _log = Logger('AutoSaveController');

// Implements ADR-6: 2s idle debounce + 30s periodic + lifecycle saves.
class AutoSaveController {
  AutoSaveController({
    required Future<String> Function(String? currentId, String body) onSave,
    required String Function() getBody,
    String? initialId,
    this.debounceDelay = const Duration(seconds: 2),
    this.periodicInterval = const Duration(seconds: 30),
  })  : _onSave = onSave,
        _getBody = getBody,
        _savedId = initialId;

  final Future<String> Function(String? currentId, String body) _onSave;
  final String Function() _getBody;

  final Duration debounceDelay;
  final Duration periodicInterval;

  String? _savedId;
  String? get savedId => _savedId;

  Timer? _debounce;
  Timer? _periodic;

  void start() {
    _periodic = Timer.periodic(periodicInterval, (_) => save());
  }

  void notifyChanged() {
    _debounce?.cancel();
    _debounce = Timer(debounceDelay, save);
  }

  Future<void> flush() async {
    _debounce?.cancel();
    _debounce = null;
    await save();
  }

  Future<void> save() async {
    final body = _getBody();
    if (body.isEmpty) return;
    try {
      _savedId = await _onSave(_savedId, body);
    } catch (e, st) {
      _log.severe('save failed', e, st);
    }
  }

  void resetForQuki({String? id}) {
    _debounce?.cancel();
    _debounce = null;
    _savedId = id;
  }

  void dispose() {
    _debounce?.cancel();
    _periodic?.cancel();
  }
}
