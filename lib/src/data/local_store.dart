import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/vodovod_models.dart';

class LocalVodovodStore {
  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    final path = p.join(await getDatabasesPath(), 'vodovod_mobile_flutter.db');
    _db = await openDatabase(
      path,
      version: 5,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE inkasanti (
            idink INTEGER PRIMARY KEY,
            payload TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE ocitavanja (
            id INTEGER PRIMARY KEY,
            ocitano TEXT NOT NULL,
            is_synced INTEGER NOT NULL,
            payload TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE stanja_brojila (
            id INTEGER PRIMARY KEY,
            payload TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE meta (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
          )
        ''');
        await _createNapomeneTable(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createNapomeneTable(db);
        }
        if (oldVersion < 3) {
          await _migrateNapomeneQueue(db);
        }
      },
    );
    return _db!;
  }

  Future<void> _createNapomeneTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS napomene (
        local_id INTEGER PRIMARY KEY,
        payload TEXT NOT NULL
      )
    ''');
  }

  Future<void> _migrateNapomeneQueue(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS napomene_new (
        local_id INTEGER PRIMARY KEY,
        payload TEXT NOT NULL
      )
    ''');
    await db.execute('''
      INSERT OR REPLACE INTO napomene_new (local_id, payload)
      SELECT local_id, payload FROM napomene
    ''');
    await db.execute('DROP TABLE IF EXISTS napomene');
    await db.execute('ALTER TABLE napomene_new RENAME TO napomene');
  }

  Future<void> saveInkasanti(List<InkasantiModel> items) async {
    final db = await database;
    final batch = db.batch();
    batch.delete('inkasanti');
    for (final item in items) {
      batch.insert('inkasanti', {
        'idink': item.idink,
        'payload': jsonEncode(item.toJson()),
      });
    }
    await batch.commit(noResult: true);
  }

  Future<List<InkasantiModel>> loadInkasanti() async {
    final db = await database;
    final rows = await db.query('inkasanti');
    return rows
        .map((row) => InkasantiModel.fromJson(_decode(row['payload'])))
        .toList();
  }

  Future<void> saveAktivnoOcitavanje(OcitavanjeGlavnoModel model) async {
    final db = await database;
    await db.insert('meta', {
      'key': 'aktivno_ocitavanje',
      'value': jsonEncode(model.toJson()),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<OcitavanjeGlavnoModel?> loadAktivnoOcitavanje() async {
    final db = await database;
    final rows = await db.query(
      'meta',
      where: 'key = ?',
      whereArgs: ['aktivno_ocitavanje'],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return OcitavanjeGlavnoModel.fromJson(
      jsonDecode(rows.first['value'] as String) as Map<String, dynamic>,
    );
  }

  Future<void> saveMetaValue(String key, String value) async {
    final db = await database;
    await db.insert('meta', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<String?> loadMetaValue(String key) async {
    final db = await database;
    final rows = await db.query(
      'meta',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<void> deleteMetaValue(String key) async {
    final db = await database;
    await db.delete('meta', where: 'key = ?', whereArgs: [key]);
  }

  Future<void> saveStanjaBrojila(List<StanjeBrojilaModel> items) async {
    final db = await database;
    final batch = db.batch();
    batch.delete('stanja_brojila');
    for (final item in items) {
      batch.insert('stanja_brojila', {
        'id': item.id,
        'payload': jsonEncode(item.toJson()),
      });
    }
    await batch.commit(noResult: true);
  }

  Future<List<StanjeBrojilaModel>> loadStanjaBrojila() async {
    final db = await database;
    final rows = await db.query('stanja_brojila');
    return rows
        .map((row) => StanjeBrojilaModel.fromJson(_decode(row['payload'])))
        .toList();
  }

  Future<void> saveOcitavanja(List<OcitavanjeModel> items) async {
    await mergeOcitavanjaForActiveImport(items);
  }

  Future<void> replaceOcitavanja(List<OcitavanjeModel> items) async {
    final db = await database;
    final batch = db.batch();
    batch.delete('ocitavanja');
    for (final item in items) {
      batch.insert('ocitavanja', _rowForOcitavanjeImport(item));
    }
    await batch.commit(noResult: true);
  }

  Future<void> mergeOcitavanjaForActiveImport(
    List<OcitavanjeModel> items,
  ) async {
    final db = await database;
    final unsynced = (await loadUnsyncedOcitavanja())
        .where(_isLocalPendingUpload)
        .toList();
    final unsyncedById = {for (final item in unsynced) item.id: item};
    final merged = items.map((item) => unsyncedById[item.id] ?? item).toList();

    final batch = db.batch();
    batch.delete('ocitavanja');
    for (final item in merged) {
      final isPending = unsyncedById.containsKey(item.id);
      batch.insert(
        'ocitavanja',
        isPending ? _rowForOcitavanje(item) : _rowForOcitavanjeImport(item),
      );
    }
    await batch.commit(noResult: true);
  }

  Future<int> maxLocalOcitavanjeGlavnoId() async {
    final items = await loadOcitavanja();
    if (items.isEmpty) return -1;
    return items
        .map((item) => item.ocitavanjeGlavnoId)
        .reduce((a, b) => a > b ? a : b);
  }

  Future<List<OcitavanjeModel>> loadOcitavanja() async {
    final db = await database;
    final rows = await db.query('ocitavanja');
    return rows
        .map((row) => OcitavanjeModel.fromJson(_decode(row['payload'])))
        .toList();
  }

  Future<List<OcitavanjeModel>> loadUnsyncedOcitavanja() async {
    final db = await database;
    final rows = await db.query('ocitavanja', where: 'is_synced = 0');
    return rows
        .map((row) => OcitavanjeModel.fromJson(_decode(row['payload'])))
        .where(_isLocalPendingUpload)
        .toList();
  }

  Future<void> updateOcitavanje(OcitavanjeModel item) async {
    final db = await database;
    await db.insert(
      'ocitavanja',
      _rowForOcitavanje(item),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> saveNapomena(NapomenaDraft item) async {
    final db = await database;
    await db.insert('napomene', {
      'local_id': item.localId,
      'payload': jsonEncode(item.toJson()),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<NapomenaDraft>> loadUnsyncedNapomene() async {
    final db = await database;
    final rows = await db.query('napomene', orderBy: 'local_id DESC');
    return rows
        .map((row) => NapomenaDraft.fromJson(_decode(row['payload'])))
        .toList();
  }

  Future<void> deleteNapomena(int localId) async {
    final db = await database;
    await db.delete('napomene', where: 'local_id = ?', whereArgs: [localId]);
  }

  Map<String, Object?> _rowForOcitavanje(OcitavanjeModel item) {
    return {
      'id': item.id,
      'ocitano': item.ocitano.toUpperCase(),
      'is_synced': item.isSynced ? 1 : 0,
      'payload': jsonEncode(item.toJson()),
    };
  }

  Map<String, Object?> _rowForOcitavanjeImport(OcitavanjeModel item) {
    final synced = item.copyWith(isSynced: true);
    return {
      'id': synced.id,
      'ocitano': synced.ocitano.toUpperCase(),
      'is_synced': 1,
      'payload': jsonEncode(synced.toJson()),
    };
  }

  bool _isLocalPendingUpload(OcitavanjeModel item) {
    if (item.isSynced) return false;
    return item.latitude.trim().isNotEmpty || item.longitude.trim().isNotEmpty;
  }

  Map<String, dynamic> _decode(Object? payload) {
    return jsonDecode(payload as String) as Map<String, dynamic>;
  }
}
