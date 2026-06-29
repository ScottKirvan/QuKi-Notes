import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Tracks whether the user prefers to be in edit mode (keyboard up, a block
/// active) when a note is opened.
///
/// - `true` (default): focus the first block on note load → keyboard appears.
/// - `false`: open in browse mode → all blocks rendered, keyboard hidden.
///
/// Updated by [EditorScreen] as the user moves between edit and browse mode:
/// - A block becomes active → `true`
/// - All blocks lose focus (keyboard dismissed) → `false`
///
/// In-memory only — not persisted to disk. The default of `true` ensures cold
/// launch always opens in edit mode, satisfying the manifesto velocity promise.
class EditModePreferenceNotifier extends Notifier<bool> {
  @override
  bool build() => true;

  void setPreference(bool value) => state = value;
}

final editModePreferredProvider =
    NotifierProvider<EditModePreferenceNotifier, bool>(
  EditModePreferenceNotifier.new,
);
