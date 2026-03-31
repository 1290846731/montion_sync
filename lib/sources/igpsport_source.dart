import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';

import '../models/activity.dart';
import '../storage/kv_store.dart';
import '../utils/parsing.dart';
import 'source_adapter.dart';

enum IGPSportExportType { fit, gpx }

class IGPSportSource implements SourceAdapter {
  IGPSportSource({required Dio dio, required KvStore kvStore}) : _kvStore = kvStore {
    _cookieJar = CookieJar();
    _client = Dio(dio.options);
    _client.interceptors.add(CookieManager(_cookieJar));
  }

  late final CookieJar _cookieJar;
  late final Dio _client;
  final KvStore _kvStore;
  final Set<IGPSportExportType> _warmedExportTypes = <IGPSportExportType>{};

  @override
  String get name => 'igpsport';

  @override
  String get displayName => 'IGPSPORT 迹驰';

  static const _apiRoot = 'https://prod.zh.igpsport.com';

  @override
  Future<bool> isConfigured() async {
    final token = await _kvStore.getSecureString(Keys.igpsportAccessToken);
    final username = await _kvStore.getSecureString(Keys.igpsportUsername);
    final password = await _kvStore.getSecureString(Keys.igpsportPassword);
    return (token != null && token.isNotEmpty) ||
        ((username != null && username.isNotEmpty) && (password != null && password.isNotEmpty));
  }

  @override
  Future<void> authenticate() async {
    final existing = await _kvStore.getSecureString(Keys.igpsportAccessToken);
    if (existing != null && existing.isNotEmpty) return;

    final username = await _kvStore.getSecureString(Keys.igpsportUsername);
    final password = await _kvStore.getSecureString(Keys.igpsportPassword);
    if (username == null || password == null || username.isEmpty || password.isEmpty) {
      throw StateError('IGPSPORT 账号未配置');
    }

    final response = await _client.post<Map<String, dynamic>>(
      '$_apiRoot/service/auth/account/login',
      data: {
        'username': username,
        'password': password,
        'appId': 'igpsport-web',
      },
      options: Options(
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json, text/plain, */*',
          'Origin': 'https://app.zh.igpsport.com',
          'Referer': 'https://app.zh.igpsport.com/',
        },
      ),
    );
    final payload = response.data;
    if (payload == null) {
      throw StateError('IGPSPORT 登录返回为空');
    }
    if (payload['code'] != 0) {
      throw StateError('IGPSPORT 登录失败: ${payload['message'] ?? payload}');
    }
    final token = (payload['data'] as Map?)?['access_token']?.toString();
    if (token == null || token.isEmpty) {
      throw StateError('IGPSPORT 未返回 access_token');
    }
    await _kvStore.setSecureString(Keys.igpsportAccessToken, token);
  }

  Future<String> _accessToken() async {
    await authenticate();
    final token = await _kvStore.getSecureString(Keys.igpsportAccessToken);
    if (token == null || token.isEmpty) {
      throw StateError('IGPSPORT access_token 为空');
    }
    return token;
  }

  @override
  Future<List<Activity>> listActivities({DateTime? since, DateTime? until, int? limit}) async {
    return listActivitiesForExport(
      exportType: IGPSportExportType.fit,
      since: since,
      until: until,
      limit: limit,
    );
  }

  Future<List<Activity>> listActivitiesForExport({
    required IGPSportExportType exportType,
    DateTime? since,
    DateTime? until,
    int? limit,
    int pageSize = 20,
    int? maxPages,
  }) async {
    final token = await _accessToken();

    final activities = <Activity>[];
    var page = 1;
    final end = until?.toUtc() ?? DateTime.now().toUtc();

    while (true) {
      final params = <String, dynamic>{
        'pageNo': page,
        'pageSize': pageSize,
        'reqType': exportType == IGPSportExportType.gpx ? 1 : 0,
        'sort': 1,
      };

      if (since != null || until != null) {
        final begin = (since?.toUtc() ?? DateTime.utc(2000, 1, 1));
        params['beginTime'] = '${begin.year.toString().padLeft(4, '0')}-${begin.month.toString().padLeft(2, '0')}-${begin.day.toString().padLeft(2, '0')}';
        params['endTime'] = '${end.year.toString().padLeft(4, '0')}-${end.month.toString().padLeft(2, '0')}-${end.day.toString().padLeft(2, '0')}';
      }

      final response = await _client.get<Map<String, dynamic>>(
        '$_apiRoot/service/web-gateway/web-analyze/activity/queryMyActivity',
        queryParameters: params,
        options: Options(
          headers: {
            'Accept': 'application/json, text/plain, */*',
            'Authorization': 'Bearer $token',
            'Origin': 'https://app.zh.igpsport.com',
            'Referer': 'https://app.zh.igpsport.com/',
            'timezone': 'Asia/Shanghai',
            'qiwu-app-version': '1.0.0',
          },
        ),
      );
      final payload = response.data;
      if (payload == null) {
        throw StateError('IGPSPORT 列表返回为空');
      }
      if (payload['code'] != 0) {
        throw StateError('IGPSPORT 列表失败: ${payload['message'] ?? payload}');
      }
      final data = (payload['data'] as Map?) ?? {};
      final rows = (data['rows'] as List?) ?? const [];
      if (rows.isEmpty) break;

      for (final item in rows) {
        if (item is! Map) continue;
        final sourceId = item['rideId']?.toString();
        if (sourceId == null || sourceId.isEmpty) continue;
        final start = parseDateTime(item['startDateTime'] ?? item['startTime'] ?? item['startTimeString'] ?? item['createdTime']);
        final activity = Activity(
          source: name,
          sourceId: sourceId,
          name: (item['title']?.toString().trim().isNotEmpty ?? false) ? item['title'].toString() : 'IGPSPORT-$sourceId',
          sportType: _sportType(item['exerciseType'] ?? item['sportType']),
          startTime: start,
          raw: Map<String, dynamic>.from(item),
        );
        if (since != null && activity.startTime != null && activity.startTime!.isBefore(since.toUtc())) {
          continue;
        }
        if (until != null && activity.startTime != null && activity.startTime!.isAfter(until.toUtc())) {
          continue;
        }
        activities.add(activity);
        if (limit != null && activities.length >= limit) {
          return activities;
        }
      }

      final totalPage = int.tryParse(data['totalPage']?.toString() ?? '') ?? 1;
      if (page >= totalPage) break;
      if (maxPages != null && page >= maxPages) break;
      page += 1;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }

    return activities;
  }

  @override
  Future<File> downloadFit({required Activity activity, required Directory outputDir}) async {
    return _downloadRouteFile(
      activity: activity,
      outputDir: outputDir,
      exportType: IGPSportExportType.fit,
    );
  }

  Future<File> downloadGpx({required Activity activity, required Directory outputDir}) async {
    return _downloadRouteFile(
      activity: activity,
      outputDir: outputDir,
      exportType: IGPSportExportType.gpx,
    );
  }

  Future<void> _warmupExportType(IGPSportExportType exportType, {DateTime? since, DateTime? until}) async {
    if (_warmedExportTypes.contains(exportType)) return;
    _warmedExportTypes.add(exportType);

    try {
      await listActivitiesForExport(
        exportType: exportType,
        since: since,
        until: until,
        limit: 1,
        pageSize: 1,
        maxPages: 1,
      );
    } catch (_) {}
  }

  Future<File> _downloadRouteFile({
    required Activity activity,
    required Directory outputDir,
    required IGPSportExportType exportType,
  }) async {
    final token = await _accessToken();
    final dir = Directory('${outputDir.path}/$name');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    final ext = exportType == IGPSportExportType.gpx ? 'gpx' : 'fit';
    final path = File('${dir.path}/${safeFilename(activity.sourceId)}.$ext');
    if (path.existsSync() && path.lengthSync() > 100) {
      return path;
    }

    await _warmupExportType(exportType);

    final response = await _client.get<Map<String, dynamic>>(
      '$_apiRoot/service/web-gateway/web-analyze/activity/getDownloadUrl/${activity.sourceId}',
      options: Options(
        headers: {
          'Accept': 'application/json, text/plain, */*',
          'Authorization': 'Bearer $token',
          'Origin': 'https://app.zh.igpsport.com',
          'Referer': 'https://app.zh.igpsport.com/',
          'timezone': 'Asia/Shanghai',
          'qiwu-app-version': '1.0.0',
        },
      ),
    );
    final payload = response.data;
    if (payload == null) {
      throw StateError('IGPSPORT 下载URL返回为空');
    }
    if (payload['code'] != 0) {
      throw StateError('IGPSPORT 下载URL失败: ${payload['message'] ?? payload}');
    }
    final downloadUrl = payload['data']?.toString();
    if (downloadUrl == null || downloadUrl.isEmpty) {
      throw StateError('IGPSPORT 下载URL缺失');
    }

    final bytes = await _client.get<List<int>>(
      downloadUrl,
      options: Options(
        responseType: ResponseType.bytes,
        validateStatus: (status) => status != null && status < 500,
      ),
    );
    if (bytes.statusCode != 200 || bytes.data == null) {
      throw StateError('IGPSPORT 下载失败: HTTP ${bytes.statusCode}');
    }
    await path.writeAsBytes(bytes.data!, flush: true);
    if (path.lengthSync() < 100) {
      throw StateError('IGPSPORT 下载文件过小');
    }
    return path;
  }
}

String? _sportType(dynamic value) {
  final mapping = <int, String>{
    0: 'cycling',
    1: 'running',
    2: 'walking',
    3: 'hiking',
    4: 'swimming',
    6: 'indoor_cycling',
  };
  final asInt = int.tryParse(value?.toString() ?? '');
  if (asInt == null) return null;
  return mapping[asInt];
}
