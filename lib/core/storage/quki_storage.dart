import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'quki_meta.dart';

class QuKiStorage {
  QuKiStorage(this._root);

  final Directory _root;

  /// The absolute path of the root directory for this storage instance.
  String get basePath => _root.path;

  Directory get _metaDir => Directory(p.join(_root.path, '.meta'));
  Directory get _trashDir => Directory(p.join(_root.path, '.trash'));
  Directory get _trashMetaDir =>
      Directory(p.join(_root.path, '.trash', '.meta'));

  /// Create a [QuKiStorage] rooted at [basePath].
  ///
  /// [basePath] is an absolute path to the directory that will hold the
  /// `qukis/` subdirectory (e.g. the value from [StorageLocationService.basePath]).
  factory QuKiStorage.fromPath(String basePath) =>
      QuKiStorage(Directory(basePath));

  /// Create a [QuKiStorage] rooted at the app's sandboxed documents directory.
  ///
  /// Kept for use in tests that do not need a configurable path.
  static Future<QuKiStorage> fromAppDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    return QuKiStorage(Directory(p.join(appDir.path, 'qukis')));
  }

  Future<void> _ensureDirs() async {
    await _root.create(recursive: true);
    await _metaDir.create(recursive: true);
    await _trashDir.create(recursive: true);
    await _trashMetaDir.create(recursive: true);
  }

  File _mdFile(String id) => File(p.join(_root.path, '$id.md'));
  File _metaFile(String id) => File(p.join(_metaDir.path, '$id.json'));
  File _trashMdFile(String id) => File(p.join(_trashDir.path, '$id.md'));
  File _trashMetaFile(String id) =>
      File(p.join(_trashMetaDir.path, '$id.json'));

  Future<QuKiMeta> create(String body) async {
    await _ensureDirs();
    final id = const Uuid().v4();
    final now = DateTime.now();
    final nowUtc = now.toUtc();

    await _metaFile(id).writeAsString(
      jsonEncode({
        'createdAt': now.toIso8601String(),
        'modifiedAt': nowUtc.toIso8601String(),
      }),
    );
    await _writeAtomic(_mdFile(id), body);

    return QuKiMeta(
      id: id,
      filePath: _mdFile(id).path,
      createdAt: now,
      modifiedAt: nowUtc,
    );
  }

  /// Updates the content of an existing QuKi and records [modifiedAt] (defaults
  /// to [DateTime.now] in UTC) in the sidecar `.meta/{id}.json` so that sort
  /// order is derived from an explicit timestamp rather than filesystem mtime.
  Future<DateTime> update(String id, String body,
      {DateTime? modifiedAt}) async {
    final ts = (modifiedAt ?? DateTime.now()).toUtc();
    await _writeAtomic(_mdFile(id), body);
    await _writeSidecarModifiedAt(id, ts);
    return ts;
  }

  /// Writes [modifiedAt] into the sidecar JSON, preserving any existing fields
  /// (most importantly [createdAt]).
  ///
  /// Returns without writing if the sidecar is missing or unreadable —
  /// [_readMeta] falls back to [stat.modified] in those cases.
  Future<void> _writeSidecarModifiedAt(String id, DateTime modifiedAt) async {
    final file = _metaFile(id);
    if (!await file.exists()) return;
    Map<String, dynamic> existing;
    try {
      existing = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return; // Corrupt sidecar — skip update; _readMeta falls back to stat.modified.
    }
    existing['modifiedAt'] = modifiedAt.toIso8601String();
    await file.writeAsString(jsonEncode(existing));
  }

  Future<String> read(String id) => _mdFile(id).readAsString();

  Future<String> readTrash(String id) => _trashMdFile(id).readAsString();

  Future<void> softDelete(String id) async {
    await _ensureDirs();
    final md = _mdFile(id);
    final meta = _metaFile(id);
    await _renameIfExists(md, _trashMdFile(id).path);
    await _renameIfExists(meta, _trashMetaFile(id).path);
  }

  /// Renames [source] to [destPath] if [source] currently exists, retrying
  /// briefly on a transient rename failure.
  ///
  /// `exists()` then `rename()` is inherently check-then-act, not atomic —
  /// on Windows a freshly-written file can be transiently grabbed (by
  /// antivirus/search-indexing scanning `Directory.systemTemp`, in
  /// particular) for a few milliseconds right after creation, long enough
  /// for [source] to have existed at the `exists()` check but no longer be
  /// renameable moments later (observed directly: a real
  /// `PathNotFoundException` from [File.rename] on a file [File.exists]
  /// had just confirmed present, under full-suite test load — the same
  /// class of Windows transient-file-access issue already documented
  /// elsewhere in this codebase for `write-temp-then-rename`). Retrying the
  /// rename itself (not re-checking `exists()`, which would just reproduce
  /// the identical race) gives that kind of momentary external interference
  /// a chance to clear. If every retry exhausts and [source] is confirmed
  /// gone by then, there's nothing left to move — return normally rather
  /// than throwing, since the caller (delete) only cares that [source] no
  /// longer exists once this returns, not which path removed it. Any other,
  /// non-transient failure (e.g. permissions) still exhausts retries and is
  /// left in its original location — a real but rare gap (an orphaned file
  /// no longer reachable from the index, matching the already-tracked #272
  /// class of issue) rather than a crash on every delete attempt.
  Future<void> _renameIfExists(File source, String destPath) async {
    if (!await source.exists()) return;
    const maxAttempts = 5;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        await source.rename(destPath);
        return;
      } on FileSystemException {
        if (attempt == maxAttempts) return;
        await Future<void>.delayed(Duration(milliseconds: 20 * attempt));
      }
    }
  }

  Future<void> restore(String id) async {
    await _ensureDirs();
    final trashMd = _trashMdFile(id);
    final trashMeta = _trashMetaFile(id);
    if (await trashMd.exists()) await trashMd.rename(_mdFile(id).path);
    if (await trashMeta.exists()) await trashMeta.rename(_metaFile(id).path);
  }

  Future<void> hardDelete(String id) async {
    final trashMd = _trashMdFile(id);
    final trashMeta = _trashMetaFile(id);
    if (await trashMd.exists()) await trashMd.delete();
    if (await trashMeta.exists()) await trashMeta.delete();
  }

  Future<List<QuKiMeta>> scanActive() async {
    await _ensureDirs();
    return _scan(_root, _metaDir, activeFilePath: true);
  }

  Future<List<QuKiMeta>> scanTrash() async {
    await _ensureDirs();
    return _scan(_trashDir, _trashMetaDir, activeFilePath: false);
  }

  Future<List<QuKiMeta>> _scan(
    Directory dir,
    Directory metaDir, {
    required bool activeFilePath,
  }) async {
    final mds =
        dir.listSync().whereType<File>().where((f) => f.path.endsWith('.md'));
    final metas = <QuKiMeta>[];
    for (final f in mds) {
      final id = p.basenameWithoutExtension(f.path);
      final meta = await _readMeta(id, f, metaDir);
      if (meta != null) metas.add(meta);
    }
    metas.sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
    return metas;
  }

  Future<QuKiMeta?> _readMeta(
    String id,
    File mdFile,
    Directory metaDir,
  ) async {
    final metaFile = File(p.join(metaDir.path, '$id.json'));
    if (!await metaFile.exists()) return null;
    final json =
        jsonDecode(await metaFile.readAsString()) as Map<String, dynamic>;
    final createdAt = DateTime.parse(json['createdAt'] as String);
    // Read modifiedAt from the sidecar when present (set by create/update).
    // Fall back to filesystem mtime for notes written before this change.
    final DateTime modifiedAt;
    final rawModifiedAt = json['modifiedAt'] as String?;
    if (rawModifiedAt != null) {
      modifiedAt = DateTime.parse(rawModifiedAt);
    } else {
      final stat = await mdFile.stat();
      modifiedAt = stat.modified;
    }
    return QuKiMeta(
      id: id,
      filePath: mdFile.path,
      createdAt: createdAt,
      modifiedAt: modifiedAt,
    );
  }

  Future<void> _writeAtomic(File dest, String content) async {
    final tmp = File('${dest.path}.tmp');
    await tmp.writeAsString(content);
    await tmp.rename(dest.path);
  }
}
