import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import '../models/activity.dart';

class SyncRecord {
  SyncRecord({
    required this.source,
    required this.sourceId,
    required this.status,
    required this.uploadedAt,
    this.stravaActivityId,
    this.message,
    this.activityName,
    this.activityTime,
    this.activity,
  });

  final String source;
  final String sourceId;
  final String status;
  final DateTime uploadedAt;
  final String? stravaActivityId;
  final String? message;
  final String? activityName;
  final DateTime? activityTime;
  final Activity? activity;
}

class SyncDb {
  SyncDb._(this._db);

  final Database _db;

  static Future<SyncDb> open() async {
    final dir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(dir.path, 'sync_state.db');
    final db = await openDatabase(
      dbPath,
      version: 3,
      onCreate: (db, version) async {
        await db.execute(
          'CREATE TABLE synced('
          'source TEXT NOT NULL, '
          'source_id TEXT NOT NULL, '
          'status TEXT NOT NULL, '
          'uploaded_at INTEGER NOT NULL, '
          'strava_activity_id TEXT, '
          'message TEXT, '
          'activity_name TEXT, '
          'activity_time INTEGER, '
          'activity_data TEXT, '
          'PRIMARY KEY(source, source_id)'
          ')',
        );
        await db.execute(
          'CREATE INDEX idx_synced_uploaded_at ON synced(uploaded_at)',
        );
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE synced ADD COLUMN activity_name TEXT;');
          await db.execute('ALTER TABLE synced ADD COLUMN activity_time INTEGER;');
        }
        if (oldVersion < 3) {
          await db.execute('ALTER TABLE synced ADD COLUMN activity_data TEXT;');
        }
      },
    );
    return SyncDb._(db);
  }

  Future<bool> hasSynced(String source, String sourceId) async {
    final rows = await _db.query(
      'synced',
      columns: ['source'],
      where: 'source = ? AND source_id = ? AND status = ?',
      whereArgs: [source, sourceId, 'success'],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<void> setRecord(SyncRecord record) async {
    await _db.insert(
      'synced',
      {
        'source': record.source,
        'source_id': record.sourceId,
        'status': record.status,
        'uploaded_at': record.uploadedAt.millisecondsSinceEpoch,
        'strava_activity_id': record.stravaActivityId,
        'message': record.message,
        'activity_name': record.activityName,
        'activity_time': record.activityTime?.millisecondsSinceEpoch,
        'activity_data': record.activity != null ? jsonEncode(record.activity!.toJson()) : null,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<SyncRecord>> latest({int limit = 50}) async {
    final rows = await _db.query(
      'synced',
      orderBy: 'uploaded_at DESC',
      limit: limit,
    );
    return rows
        .map((row) => SyncRecord(
              source: row['source'] as String,
              sourceId: row['source_id'] as String,
              status: row['status'] as String,
              uploadedAt: DateTime.fromMillisecondsSinceEpoch(
                  row['uploaded_at'] as int),
              stravaActivityId: row['strava_activity_id'] as String?,
              message: row['message'] as String?,
              activityName: row['activity_name'] as String?,
              activityTime: row['activity_time'] != null
                  ? DateTime.fromMillisecondsSinceEpoch(
                      row['activity_time'] as int)
                  : null,
              activity: row['activity_data'] != null
                  ? Activity.fromJson(jsonDecode(row['activity_data'] as String))
                  : null,
            ))
        .toList();
  }

  Future<void> close() => _db.close();
}

