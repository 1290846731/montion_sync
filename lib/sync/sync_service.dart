import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:fit_sdk/fit_sdk.dart' as fit;
import 'package:xml/xml.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/activity.dart';
import '../sources/source_registry.dart';
import '../storage/kv_store.dart';
import '../storage/sync_db.dart';
import '../strava/strava_client.dart';
import '../utils/file_hash.dart';

enum SyncTarget {
  strava,
  intervals,
}

class SyncService {
  SyncService({
    required KvStore kvStore,
    required SyncDb syncDb,
    required SourceRegistry sourceRegistry,
    required StravaClient stravaClient,
    required Dio dio,
  })  : _kvStore = kvStore,
        _syncDb = syncDb,
        _sourceRegistry = sourceRegistry,
        _stravaClient = stravaClient,
        _dio = dio;

  final KvStore _kvStore;
  final SyncDb _syncDb;
  final SourceRegistry _sourceRegistry;
  final StravaClient _stravaClient;
  final Dio _dio;

  SyncTarget _currentTarget() {
    final raw = (_kvStore.getString(Keys.syncTarget) ?? 'strava').toLowerCase();
    return raw == 'intervals' ? SyncTarget.intervals : SyncTarget.strava;
  }

  Future<String> _loadIntervalsApiKey() async {
    final key = await _kvStore.getSecureString(Keys.intervalsApiKey);
    if (key == null || key.trim().isEmpty) {
      throw StateError('Intervals.icu 未配置 API_KEY');
    }
    return key.trim();
  }

  Future<SyncRecord> reSyncRecord(SyncRecord record) async {
    if (record.source.startsWith('manual.')) {
      throw StateError('手动导入的文件无法在此处直接重新同步');
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
      target: record.target == 'intervals' ? SyncTarget.intervals : SyncTarget.strava,
      sourceName: sourceName,
      sourceActivity: activity,
      outputRoot: outputRoot,
    );
  }

  Future<List<SyncRecord>> syncNow({
    required String sourceName,
    DateTime? since,
    int? limit,
    bool ignoreSince = false,
  }) async {
    final target = _currentTarget();
    if (target == SyncTarget.strava && !await _stravaClient.isConfigured()) {
      throw StateError('请先绑定strava');
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
      final already = await _syncDb.hasSynced(
        activity.source,
        activity.sourceId,
        target: target.name,
      );
      if (already) continue;

      final record = await _syncOne(
        target: target,
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
    required SyncTarget target,
    required String sourceName,
    required Activity sourceActivity,
    required Directory outputRoot,
  }) async {
    try {
      final source = _sourceRegistry.byName(sourceName);
      final fit = await source.downloadFit(activity: sourceActivity, outputDir: outputRoot);
      List<List<double>> route = const [];
      try {
        route = await _parseFitRoute(fit);
      } catch (_) {
        route = const [];
      }
      final externalId = '${sourceActivity.source}:${sourceActivity.sourceId}.fit';
      final remoteId = switch (target) {
        SyncTarget.strava => await _uploadToStrava(file: fit, activity: sourceActivity, externalId: externalId),
        SyncTarget.intervals =>
          await _uploadToIntervals(file: fit, activity: sourceActivity, externalId: externalId),
      };

      final record = SyncRecord(
        source: sourceActivity.source,
        sourceId: sourceActivity.sourceId,
        target: target.name,
        status: 'success',
        uploadedAt: DateTime.now(),
        stravaActivityId: remoteId.isEmpty ? null : remoteId,
        activityName: sourceActivity.name,
        activityTime: sourceActivity.startTime,
        route: route.isEmpty ? null : route,
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
        target: target.name,
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

  Future<String> _uploadToStrava({
    required File file,
    required Activity activity,
    required String externalId,
  }) async {
    if (!await _stravaClient.isConfigured()) {
      throw StateError('请先绑定strava');
    }
    return await _stravaClient.uploadActivityFile(
      file: file,
      activity: activity,
      externalId: externalId,
    );
  }

  Future<String> _uploadToIntervals({
    required File file,
    required Activity activity,
    required String externalId,
  }) async {
    final apiKey = await _loadIntervalsApiKey();
    final auth = base64Encode(utf8.encode('API_KEY:$apiKey'));

    final Response<Map<String, dynamic>> response;
    try {
      response = await _dio.post<Map<String, dynamic>>(
        'https://intervals.icu/api/v1/athlete/0/activities',
        queryParameters: {
          if (activity.name.isNotEmpty) 'name': activity.name,
          'external_id': externalId,
        },
        data: FormData.fromMap({
          'file': await MultipartFile.fromFile(file.path),
        }),
        options: Options(
          headers: {
            'Authorization': 'Basic $auth',
          },
        ),
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 409) {
        throw StateError('duplicate');
      }
      rethrow;
    }
    final data = response.data;
    final id = data?['id']?.toString() ?? '';
    return id.isEmpty ? '' : 'intervals:$id';
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
    final target = _currentTarget();
    if (target == SyncTarget.strava && !await _stravaClient.isConfigured()) {
      throw StateError('请先绑定strava');
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

    final already = await _syncDb.hasSynced(source, hash, target: target.name);
    if (already) {
      final record = SyncRecord(
        source: source,
        sourceId: hash,
        target: target.name,
        status: 'duplicate',
        uploadedAt: DateTime.now(),
        message: '本机记录已上传过该文件',
        activityName: activity.name,
        activity: activity,
      );
      await _syncDb.setRecord(record);
      return record;
    }

    List<List<double>>? route;
    final lowerExt = ext.toLowerCase();
    if (lowerExt == '.gpx') {
      route = await _parseGpxRoute(file);
    } else if (lowerExt == '.fit') {
      try {
        final pts = await _parseFitRoute(file);
        route = pts.isEmpty ? null : pts;
      } catch (_) {
        route = null;
      }
    }

    final externalId = '$source:$hash$ext';
    try {
      final remoteId = switch (target) {
        SyncTarget.strava => await _uploadToStrava(file: file, activity: activity, externalId: externalId),
        SyncTarget.intervals =>
          await _uploadToIntervals(file: file, activity: activity, externalId: externalId),
      };
      final record = SyncRecord(
        source: source,
        sourceId: hash,
        target: target.name,
        status: 'success',
        uploadedAt: DateTime.now(),
        stravaActivityId: remoteId.isEmpty ? null : remoteId,
        activityName: activity.name,
        route: route,
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
        target: target.name,
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

  Future<List<List<double>>> _parseGpxRoute(File file) async {
    final text = await file.readAsString();
    final doc = XmlDocument.parse(text);
    final points = <List<double>>[];
    for (final trkpt in doc.findAllElements('trkpt')) {
      final latStr = trkpt.getAttribute('lat');
      final lonStr = trkpt.getAttribute('lon');
      if (latStr == null || lonStr == null) continue;
      final lat = double.tryParse(latStr);
      final lon = double.tryParse(lonStr);
      if (lat == null || lon == null) continue;
      points.add([lat, lon]);
    }
    return points;
  }

  Future<List<List<double>>> _parseFitRoute(File file) async {
    final bytes = await file.readAsBytes();
    final decoder = fit.Decode();
    final points = <List<double>>[];

    decoder.onMesg = (mesg) {
      if (mesg.name.toLowerCase() != 'record') return;
      final latRaw = mesg.getFieldValue(0);
      final lonRaw = mesg.getFieldValue(1);
      if (latRaw is! num || lonRaw is! num) return;

      final lat = _fitMaybeToDegrees(latRaw);
      final lon = _fitMaybeToDegrees(lonRaw);
      if (lat.isNaN || lon.isNaN) return;
      if (lat.abs() > 90 || lon.abs() > 180) return;
      points.add([lat, lon]);
    };

    decoder.read(bytes);

    if (points.length <= 3000) return points;
    final step = (points.length / 3000).ceil();
    final sampled = <List<double>>[];
    for (var i = 0; i < points.length; i += step) {
      sampled.add(points[i]);
    }
    return sampled;
  }

  double _fitMaybeToDegrees(num v) {
    final d = v.toDouble();
    if (d.abs() <= 180) return d;
    return d * (180.0 / 2147483648.0);
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
