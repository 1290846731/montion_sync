import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/activity.dart';
import '../sources/source_registry.dart';
import '../storage/kv_store.dart';
import '../storage/sync_db.dart';
import '../strava/strava_client.dart';
import '../utils/file_hash.dart';

class SyncService {
  SyncService({
    required KvStore kvStore,
    required SyncDb syncDb,
    required SourceRegistry sourceRegistry,
    required StravaClient stravaClient,
  })  : _kvStore = kvStore,
        _syncDb = syncDb,
        _sourceRegistry = sourceRegistry,
        _stravaClient = stravaClient;

  final KvStore _kvStore;
  final SyncDb _syncDb;
  final SourceRegistry _sourceRegistry;
  final StravaClient _stravaClient;

  Future<SyncRecord> reSyncRecord(SyncRecord record) async {
    if (record.source.startsWith('manual.')) {
      throw StateError('手动导入的文件无法在此处直接重新同步');
    }

    if (!await _stravaClient.isConfigured()) {
      throw StateError('Strava 未配置 client_id/client_secret');
    }

    final sourceName = record.source;
    final source = _sourceRegistry.byName(sourceName);
    if (!await source.isConfigured()) {
      throw StateError('${source.displayName} 未配置账号');
    }

    // 为了获取完整的 Activity 数据（例如 OneLap 的 durl），我们拉取最近列表并匹配
    final activities = await source.listActivities(limit: 50);
    final activity = activities.where((a) => a.sourceId == record.sourceId).firstOrNull;

    if (activity == null) {
      throw StateError('在最近的数据中未找到该活动，无法重新同步');
    }

    final outputRoot = await _ensureDownloadDir();
    return await _syncOne(
      sourceName: sourceName,
      sourceActivity: activity,
      outputRoot: outputRoot,
    );
  }

  Future<List<SyncRecord>> syncToStrava({
    required String sourceName,
    DateTime? since,
    int? limit,
    bool ignoreSince = false,
  }) async {
    if (!await _stravaClient.isConfigured()) {
      throw StateError('Strava 未配置 client_id/client_secret');
    }

    final source = _sourceRegistry.byName(sourceName);
    if (!await source.isConfigured()) {
      throw StateError('${source.displayName} 未配置账号');
    }

    final effectiveSince = ignoreSince ? null : (since ?? await _loadLastSyncAt(sourceName));
    final until = DateTime.now().toUtc();

    final outputRoot = await _ensureDownloadDir();

    final activities = await source.listActivities(
      since: effectiveSince,
      until: until,
      limit: limit,
    );

    final results = <SyncRecord>[];

    for (final activity in activities) {
      final already = await _syncDb.hasSynced(activity.source, activity.sourceId);
      if (already) continue;

      final record = await _syncOne(
        sourceName: sourceName,
        sourceActivity: activity,
        outputRoot: outputRoot,
      );
      results.add(record);
    }

    await _saveLastSyncAt(sourceName, until);
    return results;
  }

  Future<SyncRecord> _syncOne({
    required String sourceName,
    required Activity sourceActivity,
    required Directory outputRoot,
  }) async {
    try {
      final source = _sourceRegistry.byName(sourceName);
      final fit = await source.downloadFit(activity: sourceActivity, outputDir: outputRoot);
      final externalId = '${sourceActivity.source}:${sourceActivity.sourceId}.fit';
      final stravaActivityId = await _stravaClient.uploadActivityFile(
        file: fit,
        activity: sourceActivity,
        externalId: externalId,
      );

      final record = SyncRecord(
        source: sourceActivity.source,
        sourceId: sourceActivity.sourceId,
        status: 'success',
        uploadedAt: DateTime.now(),
        stravaActivityId: stravaActivityId.isEmpty ? null : stravaActivityId,
        activityName: sourceActivity.name,
        activityTime: sourceActivity.startTime,
        activity: sourceActivity,
      );
      await _syncDb.setRecord(record);
      return record;
    } catch (e) {
      final text = e.toString();
      final status = text.toLowerCase().contains('duplicate') ? 'duplicate' : 'failed';
      final record = SyncRecord(
        source: sourceActivity.source,
        sourceId: sourceActivity.sourceId,
        status: status,
        uploadedAt: DateTime.now(),
        message: text,
        activityName: sourceActivity.name,
        activityTime: sourceActivity.startTime,
        activity: sourceActivity,
      );
      await _syncDb.setRecord(record);
      return record;
    }
  }

  Future<Directory> _ensureDownloadDir() async {
    final dir = await getApplicationDocumentsDirectory();
    final downloads = Directory('${dir.path}/downloads');
    if (!downloads.existsSync()) {
      downloads.createSync(recursive: true);
    }
    return downloads;
  }

  Future<SyncRecord> uploadLocalFile({
    required File file,
    required String sourceLabel,
  }) async {
    if (!await _stravaClient.isConfigured()) {
      throw StateError('Strava 未配置 client_id/client_secret');
    }

    final hash = await sha1File(file);
    final source = 'manual.$sourceLabel';
    final base = p.basenameWithoutExtension(file.path);
    final ext = p.extension(file.path);
    final activity = Activity(
      source: source,
      sourceId: hash,
      name: base.isEmpty ? 'Imported' : base,
      sportType: null,
      startTime: null,
      raw: const {},
    );

    final already = await _syncDb.hasSynced(source, hash);
    if (already) {
      final record = SyncRecord(
        source: source,
        sourceId: hash,
        status: 'duplicate',
        uploadedAt: DateTime.now(),
        message: '本机记录已上传过该文件',
        activityName: activity.name,
        activity: activity,
      );
      await _syncDb.setRecord(record);
      return record;
    }

    final externalId = '$source:$hash$ext';
    try {
      final stravaActivityId = await _stravaClient.uploadActivityFile(
        file: file,
        activity: activity,
        externalId: externalId,
      );
      final record = SyncRecord(
        source: source,
        sourceId: hash,
        status: 'success',
        uploadedAt: DateTime.now(),
        stravaActivityId: stravaActivityId.isEmpty ? null : stravaActivityId,
        activityName: activity.name,
        activity: activity,
      );
      await _syncDb.setRecord(record);
      return record;
    } catch (e) {
      final text = e.toString();
      final status = text.toLowerCase().contains('duplicate') ? 'duplicate' : 'failed';
      final record = SyncRecord(
        source: source,
        sourceId: hash,
        status: status,
        uploadedAt: DateTime.now(),
        message: text,
        activityName: activity.name,
        activity: activity,
      );
      await _syncDb.setRecord(record);
      return record;
    }
  }

  Future<DateTime?> _loadLastSyncAt(String sourceName) async {
    final raw = _kvStore.getString('${Keys.lastSyncAtPrefix}$sourceName');
    final epoch = int.tryParse(raw ?? '');
    if (epoch == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(epoch, isUtc: true);
  }

  Future<void> _saveLastSyncAt(String sourceName, DateTime time) async {
    await _kvStore.setString(
      '${Keys.lastSyncAtPrefix}$sourceName',
      time.toUtc().millisecondsSinceEpoch.toString(),
    );
  }
}
