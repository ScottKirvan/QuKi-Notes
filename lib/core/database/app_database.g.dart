// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $QukisTable extends Qukis with TableInfo<$QukisTable, Quki> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $QukisTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _bodyMeta = const VerificationMeta('body');
  @override
  late final GeneratedColumn<String> body = GeneratedColumn<String>(
      'body', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _modifiedAtMeta =
      const VerificationMeta('modifiedAt');
  @override
  late final GeneratedColumn<DateTime> modifiedAt = GeneratedColumn<DateTime>(
      'modified_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _deletedAtMeta =
      const VerificationMeta('deletedAt');
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
      'deleted_at', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns =>
      [id, body, createdAt, modifiedAt, deletedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'qukis';
  @override
  VerificationContext validateIntegrity(Insertable<Quki> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('body')) {
      context.handle(
          _bodyMeta, body.isAcceptableOrUnknown(data['body']!, _bodyMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('modified_at')) {
      context.handle(
          _modifiedAtMeta,
          modifiedAt.isAcceptableOrUnknown(
              data['modified_at']!, _modifiedAtMeta));
    } else if (isInserting) {
      context.missing(_modifiedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(_deletedAtMeta,
          deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Quki map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Quki(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      body: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}body'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      modifiedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}modified_at'])!,
      deletedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}deleted_at']),
    );
  }

  @override
  $QukisTable createAlias(String alias) {
    return $QukisTable(attachedDatabase, alias);
  }
}

class Quki extends DataClass implements Insertable<Quki> {
  final String id;
  final String body;
  final DateTime createdAt;
  final DateTime modifiedAt;
  final DateTime? deletedAt;
  const Quki(
      {required this.id,
      required this.body,
      required this.createdAt,
      required this.modifiedAt,
      this.deletedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['body'] = Variable<String>(body);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['modified_at'] = Variable<DateTime>(modifiedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    return map;
  }

  QukisCompanion toCompanion(bool nullToAbsent) {
    return QukisCompanion(
      id: Value(id),
      body: Value(body),
      createdAt: Value(createdAt),
      modifiedAt: Value(modifiedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory Quki.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Quki(
      id: serializer.fromJson<String>(json['id']),
      body: serializer.fromJson<String>(json['body']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      modifiedAt: serializer.fromJson<DateTime>(json['modifiedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'body': serializer.toJson<String>(body),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'modifiedAt': serializer.toJson<DateTime>(modifiedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
    };
  }

  Quki copyWith(
          {String? id,
          String? body,
          DateTime? createdAt,
          DateTime? modifiedAt,
          Value<DateTime?> deletedAt = const Value.absent()}) =>
      Quki(
        id: id ?? this.id,
        body: body ?? this.body,
        createdAt: createdAt ?? this.createdAt,
        modifiedAt: modifiedAt ?? this.modifiedAt,
        deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
      );
  Quki copyWithCompanion(QukisCompanion data) {
    return Quki(
      id: data.id.present ? data.id.value : this.id,
      body: data.body.present ? data.body.value : this.body,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      modifiedAt:
          data.modifiedAt.present ? data.modifiedAt.value : this.modifiedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Quki(')
          ..write('id: $id, ')
          ..write('body: $body, ')
          ..write('createdAt: $createdAt, ')
          ..write('modifiedAt: $modifiedAt, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, body, createdAt, modifiedAt, deletedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Quki &&
          other.id == this.id &&
          other.body == this.body &&
          other.createdAt == this.createdAt &&
          other.modifiedAt == this.modifiedAt &&
          other.deletedAt == this.deletedAt);
}

class QukisCompanion extends UpdateCompanion<Quki> {
  final Value<String> id;
  final Value<String> body;
  final Value<DateTime> createdAt;
  final Value<DateTime> modifiedAt;
  final Value<DateTime?> deletedAt;
  final Value<int> rowid;
  const QukisCompanion({
    this.id = const Value.absent(),
    this.body = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.modifiedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  QukisCompanion.insert({
    required String id,
    this.body = const Value.absent(),
    required DateTime createdAt,
    required DateTime modifiedAt,
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        createdAt = Value(createdAt),
        modifiedAt = Value(modifiedAt);
  static Insertable<Quki> custom({
    Expression<String>? id,
    Expression<String>? body,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? modifiedAt,
    Expression<DateTime>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (body != null) 'body': body,
      if (createdAt != null) 'created_at': createdAt,
      if (modifiedAt != null) 'modified_at': modifiedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  QukisCompanion copyWith(
      {Value<String>? id,
      Value<String>? body,
      Value<DateTime>? createdAt,
      Value<DateTime>? modifiedAt,
      Value<DateTime?>? deletedAt,
      Value<int>? rowid}) {
    return QukisCompanion(
      id: id ?? this.id,
      body: body ?? this.body,
      createdAt: createdAt ?? this.createdAt,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (body.present) {
      map['body'] = Variable<String>(body.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (modifiedAt.present) {
      map['modified_at'] = Variable<DateTime>(modifiedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('QukisCompanion(')
          ..write('id: $id, ')
          ..write('body: $body, ')
          ..write('createdAt: $createdAt, ')
          ..write('modifiedAt: $modifiedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ImagesTable extends Images with TableInfo<$ImagesTable, ImageRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ImagesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _qukiIdMeta = const VerificationMeta('qukiId');
  @override
  late final GeneratedColumn<String> qukiId = GeneratedColumn<String>(
      'quki_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES qukis (id) ON DELETE CASCADE'));
  static const VerificationMeta _filenameMeta =
      const VerificationMeta('filename');
  @override
  late final GeneratedColumn<String> filename = GeneratedColumn<String>(
      'filename', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _localPathMeta =
      const VerificationMeta('localPath');
  @override
  late final GeneratedColumn<String> localPath = GeneratedColumn<String>(
      'local_path', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _bytesMeta = const VerificationMeta('bytes');
  @override
  late final GeneratedColumn<int> bytes = GeneratedColumn<int>(
      'bytes', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns =>
      [id, qukiId, filename, localPath, bytes];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'images';
  @override
  VerificationContext validateIntegrity(Insertable<ImageRecord> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('quki_id')) {
      context.handle(_qukiIdMeta,
          qukiId.isAcceptableOrUnknown(data['quki_id']!, _qukiIdMeta));
    } else if (isInserting) {
      context.missing(_qukiIdMeta);
    }
    if (data.containsKey('filename')) {
      context.handle(_filenameMeta,
          filename.isAcceptableOrUnknown(data['filename']!, _filenameMeta));
    } else if (isInserting) {
      context.missing(_filenameMeta);
    }
    if (data.containsKey('local_path')) {
      context.handle(_localPathMeta,
          localPath.isAcceptableOrUnknown(data['local_path']!, _localPathMeta));
    }
    if (data.containsKey('bytes')) {
      context.handle(
          _bytesMeta, bytes.isAcceptableOrUnknown(data['bytes']!, _bytesMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ImageRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ImageRecord(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      qukiId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}quki_id'])!,
      filename: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}filename'])!,
      localPath: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}local_path']),
      bytes: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}bytes']),
    );
  }

  @override
  $ImagesTable createAlias(String alias) {
    return $ImagesTable(attachedDatabase, alias);
  }
}

class ImageRecord extends DataClass implements Insertable<ImageRecord> {
  final String id;
  final String qukiId;
  final String filename;
  final String? localPath;
  final int? bytes;
  const ImageRecord(
      {required this.id,
      required this.qukiId,
      required this.filename,
      this.localPath,
      this.bytes});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['quki_id'] = Variable<String>(qukiId);
    map['filename'] = Variable<String>(filename);
    if (!nullToAbsent || localPath != null) {
      map['local_path'] = Variable<String>(localPath);
    }
    if (!nullToAbsent || bytes != null) {
      map['bytes'] = Variable<int>(bytes);
    }
    return map;
  }

  ImagesCompanion toCompanion(bool nullToAbsent) {
    return ImagesCompanion(
      id: Value(id),
      qukiId: Value(qukiId),
      filename: Value(filename),
      localPath: localPath == null && nullToAbsent
          ? const Value.absent()
          : Value(localPath),
      bytes:
          bytes == null && nullToAbsent ? const Value.absent() : Value(bytes),
    );
  }

  factory ImageRecord.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ImageRecord(
      id: serializer.fromJson<String>(json['id']),
      qukiId: serializer.fromJson<String>(json['qukiId']),
      filename: serializer.fromJson<String>(json['filename']),
      localPath: serializer.fromJson<String?>(json['localPath']),
      bytes: serializer.fromJson<int?>(json['bytes']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'qukiId': serializer.toJson<String>(qukiId),
      'filename': serializer.toJson<String>(filename),
      'localPath': serializer.toJson<String?>(localPath),
      'bytes': serializer.toJson<int?>(bytes),
    };
  }

  ImageRecord copyWith(
          {String? id,
          String? qukiId,
          String? filename,
          Value<String?> localPath = const Value.absent(),
          Value<int?> bytes = const Value.absent()}) =>
      ImageRecord(
        id: id ?? this.id,
        qukiId: qukiId ?? this.qukiId,
        filename: filename ?? this.filename,
        localPath: localPath.present ? localPath.value : this.localPath,
        bytes: bytes.present ? bytes.value : this.bytes,
      );
  ImageRecord copyWithCompanion(ImagesCompanion data) {
    return ImageRecord(
      id: data.id.present ? data.id.value : this.id,
      qukiId: data.qukiId.present ? data.qukiId.value : this.qukiId,
      filename: data.filename.present ? data.filename.value : this.filename,
      localPath: data.localPath.present ? data.localPath.value : this.localPath,
      bytes: data.bytes.present ? data.bytes.value : this.bytes,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ImageRecord(')
          ..write('id: $id, ')
          ..write('qukiId: $qukiId, ')
          ..write('filename: $filename, ')
          ..write('localPath: $localPath, ')
          ..write('bytes: $bytes')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, qukiId, filename, localPath, bytes);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ImageRecord &&
          other.id == this.id &&
          other.qukiId == this.qukiId &&
          other.filename == this.filename &&
          other.localPath == this.localPath &&
          other.bytes == this.bytes);
}

class ImagesCompanion extends UpdateCompanion<ImageRecord> {
  final Value<String> id;
  final Value<String> qukiId;
  final Value<String> filename;
  final Value<String?> localPath;
  final Value<int?> bytes;
  final Value<int> rowid;
  const ImagesCompanion({
    this.id = const Value.absent(),
    this.qukiId = const Value.absent(),
    this.filename = const Value.absent(),
    this.localPath = const Value.absent(),
    this.bytes = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ImagesCompanion.insert({
    required String id,
    required String qukiId,
    required String filename,
    this.localPath = const Value.absent(),
    this.bytes = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        qukiId = Value(qukiId),
        filename = Value(filename);
  static Insertable<ImageRecord> custom({
    Expression<String>? id,
    Expression<String>? qukiId,
    Expression<String>? filename,
    Expression<String>? localPath,
    Expression<int>? bytes,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (qukiId != null) 'quki_id': qukiId,
      if (filename != null) 'filename': filename,
      if (localPath != null) 'local_path': localPath,
      if (bytes != null) 'bytes': bytes,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ImagesCompanion copyWith(
      {Value<String>? id,
      Value<String>? qukiId,
      Value<String>? filename,
      Value<String?>? localPath,
      Value<int?>? bytes,
      Value<int>? rowid}) {
    return ImagesCompanion(
      id: id ?? this.id,
      qukiId: qukiId ?? this.qukiId,
      filename: filename ?? this.filename,
      localPath: localPath ?? this.localPath,
      bytes: bytes ?? this.bytes,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (qukiId.present) {
      map['quki_id'] = Variable<String>(qukiId.value);
    }
    if (filename.present) {
      map['filename'] = Variable<String>(filename.value);
    }
    if (localPath.present) {
      map['local_path'] = Variable<String>(localPath.value);
    }
    if (bytes.present) {
      map['bytes'] = Variable<int>(bytes.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ImagesCompanion(')
          ..write('id: $id, ')
          ..write('qukiId: $qukiId, ')
          ..write('filename: $filename, ')
          ..write('localPath: $localPath, ')
          ..write('bytes: $bytes, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $QukisTable qukis = $QukisTable(this);
  late final $ImagesTable images = $ImagesTable(this);
  late final QukisDao qukisDao = QukisDao(this as AppDatabase);
  late final ImagesDao imagesDao = ImagesDao(this as AppDatabase);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [qukis, images];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules(
        [
          WritePropagation(
            on: TableUpdateQuery.onTableName('qukis',
                limitUpdateKind: UpdateKind.delete),
            result: [
              TableUpdate('images', kind: UpdateKind.delete),
            ],
          ),
        ],
      );
}

typedef $$QukisTableCreateCompanionBuilder = QukisCompanion Function({
  required String id,
  Value<String> body,
  required DateTime createdAt,
  required DateTime modifiedAt,
  Value<DateTime?> deletedAt,
  Value<int> rowid,
});
typedef $$QukisTableUpdateCompanionBuilder = QukisCompanion Function({
  Value<String> id,
  Value<String> body,
  Value<DateTime> createdAt,
  Value<DateTime> modifiedAt,
  Value<DateTime?> deletedAt,
  Value<int> rowid,
});

final class $$QukisTableReferences
    extends BaseReferences<_$AppDatabase, $QukisTable, Quki> {
  $$QukisTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$ImagesTable, List<ImageRecord>> _imagesRefsTable(
          _$AppDatabase db) =>
      MultiTypedResultKey.fromTable(db.images,
          aliasName: $_aliasNameGenerator(db.qukis.id, db.images.qukiId));

  $$ImagesTableProcessedTableManager get imagesRefs {
    final manager = $$ImagesTableTableManager($_db, $_db.images)
        .filter((f) => f.qukiId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_imagesRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }
}

class $$QukisTableFilterComposer extends Composer<_$AppDatabase, $QukisTable> {
  $$QukisTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get body => $composableBuilder(
      column: $table.body, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get modifiedAt => $composableBuilder(
      column: $table.modifiedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
      column: $table.deletedAt, builder: (column) => ColumnFilters(column));

  Expression<bool> imagesRefs(
      Expression<bool> Function($$ImagesTableFilterComposer f) f) {
    final $$ImagesTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.images,
        getReferencedColumn: (t) => t.qukiId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ImagesTableFilterComposer(
              $db: $db,
              $table: $db.images,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$QukisTableOrderingComposer
    extends Composer<_$AppDatabase, $QukisTable> {
  $$QukisTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get body => $composableBuilder(
      column: $table.body, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get modifiedAt => $composableBuilder(
      column: $table.modifiedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
      column: $table.deletedAt, builder: (column) => ColumnOrderings(column));
}

class $$QukisTableAnnotationComposer
    extends Composer<_$AppDatabase, $QukisTable> {
  $$QukisTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get body =>
      $composableBuilder(column: $table.body, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get modifiedAt => $composableBuilder(
      column: $table.modifiedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  Expression<T> imagesRefs<T extends Object>(
      Expression<T> Function($$ImagesTableAnnotationComposer a) f) {
    final $$ImagesTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.images,
        getReferencedColumn: (t) => t.qukiId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ImagesTableAnnotationComposer(
              $db: $db,
              $table: $db.images,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$QukisTableTableManager extends RootTableManager<
    _$AppDatabase,
    $QukisTable,
    Quki,
    $$QukisTableFilterComposer,
    $$QukisTableOrderingComposer,
    $$QukisTableAnnotationComposer,
    $$QukisTableCreateCompanionBuilder,
    $$QukisTableUpdateCompanionBuilder,
    (Quki, $$QukisTableReferences),
    Quki,
    PrefetchHooks Function({bool imagesRefs})> {
  $$QukisTableTableManager(_$AppDatabase db, $QukisTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$QukisTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$QukisTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$QukisTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> body = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> modifiedAt = const Value.absent(),
            Value<DateTime?> deletedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              QukisCompanion(
            id: id,
            body: body,
            createdAt: createdAt,
            modifiedAt: modifiedAt,
            deletedAt: deletedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            Value<String> body = const Value.absent(),
            required DateTime createdAt,
            required DateTime modifiedAt,
            Value<DateTime?> deletedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              QukisCompanion.insert(
            id: id,
            body: body,
            createdAt: createdAt,
            modifiedAt: modifiedAt,
            deletedAt: deletedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) =>
                  (e.readTable(table), $$QukisTableReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: ({imagesRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (imagesRefs) db.images],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (imagesRefs)
                    await $_getPrefetchedData<Quki, $QukisTable, ImageRecord>(
                        currentTable: table,
                        referencedTable:
                            $$QukisTableReferences._imagesRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$QukisTableReferences(db, table, p0).imagesRefs,
                        referencedItemsForCurrentItem: (item,
                                referencedItems) =>
                            referencedItems.where((e) => e.qukiId == item.id),
                        typedResults: items)
                ];
              },
            );
          },
        ));
}

typedef $$QukisTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $QukisTable,
    Quki,
    $$QukisTableFilterComposer,
    $$QukisTableOrderingComposer,
    $$QukisTableAnnotationComposer,
    $$QukisTableCreateCompanionBuilder,
    $$QukisTableUpdateCompanionBuilder,
    (Quki, $$QukisTableReferences),
    Quki,
    PrefetchHooks Function({bool imagesRefs})>;
typedef $$ImagesTableCreateCompanionBuilder = ImagesCompanion Function({
  required String id,
  required String qukiId,
  required String filename,
  Value<String?> localPath,
  Value<int?> bytes,
  Value<int> rowid,
});
typedef $$ImagesTableUpdateCompanionBuilder = ImagesCompanion Function({
  Value<String> id,
  Value<String> qukiId,
  Value<String> filename,
  Value<String?> localPath,
  Value<int?> bytes,
  Value<int> rowid,
});

final class $$ImagesTableReferences
    extends BaseReferences<_$AppDatabase, $ImagesTable, ImageRecord> {
  $$ImagesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $QukisTable _qukiIdTable(_$AppDatabase db) =>
      db.qukis.createAlias($_aliasNameGenerator(db.images.qukiId, db.qukis.id));

  $$QukisTableProcessedTableManager get qukiId {
    final $_column = $_itemColumn<String>('quki_id')!;

    final manager = $$QukisTableTableManager($_db, $_db.qukis)
        .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_qukiIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }
}

class $$ImagesTableFilterComposer
    extends Composer<_$AppDatabase, $ImagesTable> {
  $$ImagesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get filename => $composableBuilder(
      column: $table.filename, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get localPath => $composableBuilder(
      column: $table.localPath, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get bytes => $composableBuilder(
      column: $table.bytes, builder: (column) => ColumnFilters(column));

  $$QukisTableFilterComposer get qukiId {
    final $$QukisTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.qukiId,
        referencedTable: $db.qukis,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$QukisTableFilterComposer(
              $db: $db,
              $table: $db.qukis,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$ImagesTableOrderingComposer
    extends Composer<_$AppDatabase, $ImagesTable> {
  $$ImagesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get filename => $composableBuilder(
      column: $table.filename, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get localPath => $composableBuilder(
      column: $table.localPath, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get bytes => $composableBuilder(
      column: $table.bytes, builder: (column) => ColumnOrderings(column));

  $$QukisTableOrderingComposer get qukiId {
    final $$QukisTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.qukiId,
        referencedTable: $db.qukis,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$QukisTableOrderingComposer(
              $db: $db,
              $table: $db.qukis,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$ImagesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ImagesTable> {
  $$ImagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get filename =>
      $composableBuilder(column: $table.filename, builder: (column) => column);

  GeneratedColumn<String> get localPath =>
      $composableBuilder(column: $table.localPath, builder: (column) => column);

  GeneratedColumn<int> get bytes =>
      $composableBuilder(column: $table.bytes, builder: (column) => column);

  $$QukisTableAnnotationComposer get qukiId {
    final $$QukisTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.qukiId,
        referencedTable: $db.qukis,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$QukisTableAnnotationComposer(
              $db: $db,
              $table: $db.qukis,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$ImagesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $ImagesTable,
    ImageRecord,
    $$ImagesTableFilterComposer,
    $$ImagesTableOrderingComposer,
    $$ImagesTableAnnotationComposer,
    $$ImagesTableCreateCompanionBuilder,
    $$ImagesTableUpdateCompanionBuilder,
    (ImageRecord, $$ImagesTableReferences),
    ImageRecord,
    PrefetchHooks Function({bool qukiId})> {
  $$ImagesTableTableManager(_$AppDatabase db, $ImagesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ImagesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ImagesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ImagesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> qukiId = const Value.absent(),
            Value<String> filename = const Value.absent(),
            Value<String?> localPath = const Value.absent(),
            Value<int?> bytes = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ImagesCompanion(
            id: id,
            qukiId: qukiId,
            filename: filename,
            localPath: localPath,
            bytes: bytes,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String qukiId,
            required String filename,
            Value<String?> localPath = const Value.absent(),
            Value<int?> bytes = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ImagesCompanion.insert(
            id: id,
            qukiId: qukiId,
            filename: filename,
            localPath: localPath,
            bytes: bytes,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) =>
                  (e.readTable(table), $$ImagesTableReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: ({qukiId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins: <
                  T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic>>(state) {
                if (qukiId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.qukiId,
                    referencedTable: $$ImagesTableReferences._qukiIdTable(db),
                    referencedColumn:
                        $$ImagesTableReferences._qukiIdTable(db).id,
                  ) as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ));
}

typedef $$ImagesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $ImagesTable,
    ImageRecord,
    $$ImagesTableFilterComposer,
    $$ImagesTableOrderingComposer,
    $$ImagesTableAnnotationComposer,
    $$ImagesTableCreateCompanionBuilder,
    $$ImagesTableUpdateCompanionBuilder,
    (ImageRecord, $$ImagesTableReferences),
    ImageRecord,
    PrefetchHooks Function({bool qukiId})>;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$QukisTableTableManager get qukis =>
      $$QukisTableTableManager(_db, _db.qukis);
  $$ImagesTableTableManager get images =>
      $$ImagesTableTableManager(_db, _db.images);
}

mixin _$QukisDaoMixin on DatabaseAccessor<AppDatabase> {
  $QukisTable get qukis => attachedDatabase.qukis;
  QukisDaoManager get managers => QukisDaoManager(this);
}

class QukisDaoManager {
  final _$QukisDaoMixin _db;
  QukisDaoManager(this._db);
  $$QukisTableTableManager get qukis =>
      $$QukisTableTableManager(_db.attachedDatabase, _db.qukis);
}

mixin _$ImagesDaoMixin on DatabaseAccessor<AppDatabase> {
  $QukisTable get qukis => attachedDatabase.qukis;
  $ImagesTable get images => attachedDatabase.images;
  ImagesDaoManager get managers => ImagesDaoManager(this);
}

class ImagesDaoManager {
  final _$ImagesDaoMixin _db;
  ImagesDaoManager(this._db);
  $$QukisTableTableManager get qukis =>
      $$QukisTableTableManager(_db.attachedDatabase, _db.qukis);
  $$ImagesTableTableManager get images =>
      $$ImagesTableTableManager(_db.attachedDatabase, _db.images);
}
