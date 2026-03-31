import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';
import 'package:xml/xml.dart';

import '../models/activity.dart';
import '../storage/kv_store.dart';

class StravaClient {
  StravaClient({required Dio dio, required KvStore kvStore})
      : _dio = dio,
        _kvStore = kvStore;

  final Dio _dio;
  final KvStore _kvStore;

  static const redirectUri = 'stravasync://localhost/oauth';

  static const _clientId = '216639';
  static const _clientSecret = '7ec5fd013eeaff4bc2899dc48ee2b845d01b56ef';

  Future<bool> isConfigured() async {
    // 既然已经内置了，所以总是认为已经配置（或者我们可以检查是否获取了 Access Token）
    final token = await _kvStore.getSecureString(Keys.stravaAccessToken);
    return token != null && token.isNotEmpty;
  }

  Future<String> buildAuthorizeUrl({bool forcePrompt = false}) async {
    final prompt = forcePrompt ? 'force' : 'auto';
    final uri = Uri.https(
      'www.strava.com',
      '/oauth/authorize',
      {
        'client_id': _clientId,
        'redirect_uri': redirectUri,
        'response_type': 'code',
        'approval_prompt': prompt,
        'scope': 'activity:read_all,activity:write',
      },
    );
    return uri.toString();
  }

  Future<void> exchangeCode(String code) async {
    final response = await _dio.post<Map<String, dynamic>>(
      'https://www.strava.com/oauth/token',
      data: FormData.fromMap({
        'client_id': _clientId,
        'client_secret': _clientSecret,
        'code': code,
        'grant_type': 'authorization_code',
      }),
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
    final payload = response.data;
    if (payload == null) {
      throw StateError('Strava token 返回为空');
    }
    await _persistTokenPayload(payload);
  }

  Future<String> uploadActivityFile({
    required File file,
    required Activity activity,
    required String externalId,
  }) async {
    final token = await _ensureAccessToken();
    final result = await _uploadWithToken(
      token: token,
      file: file,
      activity: activity,
      externalId: externalId,
    );
    if (result.statusCode == 401) {
      final refreshed = await _refreshAccessToken();
      final retried = await _uploadWithToken(
        token: refreshed,
        file: file,
        activity: activity,
        externalId: externalId,
      );
      if (retried.statusCode != 201) {
        throw StravaException(_extractError(retried));
      }
      return await _pollUpload(
        token: refreshed,
        uploadId: retried.data?['id']?.toString(),
      );
    }

    if (result.statusCode != 201) {
      throw StravaException(_extractError(result));
    }
    return await _pollUpload(
      token: token,
      uploadId: result.data?['id']?.toString(),
    );
  }

  Future<List<List<double>>> getActivityLatLngStream({required String activityId}) async {
    final token = await _ensureAccessToken();
    final result = await _getStreamsWithToken(token: token, activityId: activityId);
    if (result.statusCode == 401) {
      final refreshed = await _refreshAccessToken();
      final retried = await _getStreamsWithToken(token: refreshed, activityId: activityId);
      if (retried.statusCode != 200) {
        throw StravaException(_extractError(retried));
      }
      return _extractLatLng(retried.data);
    }
    if (result.statusCode != 200) {
      throw StravaException(_extractError(result));
    }
    return _extractLatLng(result.data);
  }

  Future<({int activityCount, List<List<List<double>>> routes})> listRideRoutesPage({
    DateTime? after,
    DateTime? before,
    int page = 1,
    int perPage = 50,
  }) async {
    final token = await _ensureAccessToken();
    final result = await _getAthleteActivitiesWithToken(
      token: token,
      after: after,
      before: before,
      page: page,
      perPage: perPage,
    );
    if (result.statusCode == 401) {
      final refreshed = await _refreshAccessToken();
      final retried = await _getAthleteActivitiesWithToken(
        token: refreshed,
        after: after,
        before: before,
        page: page,
        perPage: perPage,
      );
      if (retried.statusCode != 200) {
        throw StravaException(_extractError(retried));
      }
      return _extractRideRoutesPage(retried.data);
    }
    if (result.statusCode != 200) {
      throw StravaException(_extractError(result));
    }
    return _extractRideRoutesPage(result.data);
  }

  Future<({int activityCount, List<({String id, String? summaryPolyline})> rides})> listRideSummariesPage({
    DateTime? after,
    DateTime? before,
    int page = 1,
    int perPage = 50,
  }) async {
    final token = await _ensureAccessToken();
    final result = await _getAthleteActivitiesWithToken(
      token: token,
      after: after,
      before: before,
      page: page,
      perPage: perPage,
    );
    if (result.statusCode == 401) {
      final refreshed = await _refreshAccessToken();
      final retried = await _getAthleteActivitiesWithToken(
        token: refreshed,
        after: after,
        before: before,
        page: page,
        perPage: perPage,
      );
      if (retried.statusCode != 200) {
        throw StravaException(_extractError(retried));
      }
      return _extractRideSummariesPage(retried.data);
    }
    if (result.statusCode != 200) {
      throw StravaException(_extractError(result));
    }
    return _extractRideSummariesPage(result.data);
  }

  Future<List<List<double>>> getActivityRoutePoints({
    required String activityId,
    String? summaryPolyline,
  }) async {
    try {
      final gpx = await _tryDownloadActivityGpxPoints(activityId: activityId);
      if (gpx.length >= 2) return gpx;
    } catch (_) {}

    try {
      final stream = await getActivityLatLngStream(activityId: activityId);
      if (stream.length >= 2) return stream;
    } catch (_) {}

    if (summaryPolyline != null && summaryPolyline.isNotEmpty) {
      final pts = _decodePolyline(summaryPolyline);
      if (pts.length >= 2) return pts;
    }
    return const [];
  }

  Future<List<String>> listActivityIds({
    DateTime? after,
    DateTime? before,
    int page = 1,
    int perPage = 50,
  }) async {
    final token = await _ensureAccessToken();
    final result = await _getAthleteActivitiesWithToken(
      token: token,
      after: after,
      before: before,
      page: page,
      perPage: perPage,
    );
    if (result.statusCode == 401) {
      final refreshed = await _refreshAccessToken();
      final retried = await _getAthleteActivitiesWithToken(
        token: refreshed,
        after: after,
        before: before,
        page: page,
        perPage: perPage,
      );
      if (retried.statusCode != 200) {
        throw StravaException(_extractError(retried));
      }
      return _extractActivityIds(retried.data);
    }
    if (result.statusCode != 200) {
      throw StravaException(_extractError(result));
    }
    return _extractActivityIds(result.data);
  }

  Future<Response<dynamic>> _getStreamsWithToken({
    required String token,
    required String activityId,
  }) {
    return _dio.get<dynamic>(
      'https://www.strava.com/api/v3/activities/$activityId/streams',
      queryParameters: {
        'keys': 'latlng',
        'key_by_type': true,
      },
      options: Options(
        headers: {'Authorization': 'Bearer $token'},
        validateStatus: (status) => status != null,
      ),
    );
  }

  List<List<double>> _extractLatLng(dynamic data) {
    if (data is Map<String, dynamic>) {
      final latlng = data['latlng'];
      if (latlng is Map<String, dynamic>) {
        final points = latlng['data'];
        return _extractLatLng(points);
      }
    } else if (data is List) {
      final latlngStream = data.whereType<Map<String, dynamic>>().firstWhere(
            (m) => m['type']?.toString() == 'latlng',
            orElse: () => const {},
          );
      final points = latlngStream['data'];
      return _extractLatLng(points);
    } else if (data is Iterable) {
      return data
          .whereType<List>()
          .where((e) => e.length >= 2)
          .map<List<double>>((e) => [
                (e[0] as num).toDouble(),
                (e[1] as num).toDouble(),
              ])
          .toList();
    }
    return const [];
  }

  ({int activityCount, List<List<List<double>>> routes}) _extractRideRoutesPage(dynamic data) {
    final activities = _extractActivities(data);
    if (activities.isEmpty) return (activityCount: 0, routes: const []);

    final routes = <List<List<double>>>[];
    for (final m in activities) {
      final type = m['type']?.toString();
      if (type != 'Ride' && type != 'EBikeRide') continue;
      final map = m['map'];
      if (map is Map<String, dynamic>) {
        final encoded = map['summary_polyline']?.toString();
        if (encoded != null && encoded.isNotEmpty) {
          final pts = _decodePolyline(encoded);
          if (pts.length >= 2) routes.add(pts);
        }
      }
    }

    return (activityCount: activities.length, routes: routes);
  }

  ({int activityCount, List<({String id, String? summaryPolyline})> rides}) _extractRideSummariesPage(dynamic data) {
    final activities = _extractActivities(data);
    if (activities.isEmpty) return (activityCount: 0, rides: const []);

    final rides = <({String id, String? summaryPolyline})>[];
    for (final m in activities) {
      final type = m['type']?.toString();
      if (type != 'Ride' && type != 'EBikeRide') continue;

      final id = m['id']?.toString();
      if (id == null || id.isEmpty) continue;

      String? summaryPolyline;
      final map = m['map'];
      if (map is Map<String, dynamic>) {
        final encoded = map['summary_polyline']?.toString();
        if (encoded != null && encoded.isNotEmpty) {
          summaryPolyline = encoded;
        }
      }

      rides.add((id: id, summaryPolyline: summaryPolyline));
    }
    return (activityCount: activities.length, rides: rides);
  }

  List<Map<String, dynamic>> _extractActivities(dynamic data) {
    if (data is List) {
      return data.whereType<Map<String, dynamic>>().toList();
    }
    return const [];
  }

  Future<List<List<double>>> _tryDownloadActivityGpxPoints({required String activityId}) async {
    final result = await _downloadActivityGpx(activityId: activityId);
    if (result.statusCode != 200) return const [];
    return _extractGpxLatLng(result.data);
  }

  Future<Response<List<int>>> _downloadActivityGpx({required String activityId}) {
    return _dio.get<List<int>>(
      'https://www.strava.com/activities/$activityId/export_gpx',
      options: Options(
        responseType: ResponseType.bytes,
        followRedirects: false,
        maxRedirects: 0,
        validateStatus: (status) => status != null && status < 400,
      ),
    );
  }

  List<List<double>> _extractGpxLatLng(List<int>? bytes) {
    if (bytes == null || bytes.isEmpty) return const [];
    final text = utf8.decode(bytes, allowMalformed: true);
    if (text.trim().isEmpty) return const [];

    try {
      final doc = XmlDocument.parse(text);
      final points = <List<double>>[];

      for (final e in doc.findAllElements('trkpt')) {
        final lat = double.tryParse(e.getAttribute('lat') ?? '');
        final lon = double.tryParse(e.getAttribute('lon') ?? '');
        if (lat == null || lon == null) continue;
        points.add([lat, lon]);
      }
      if (points.length >= 2) return points;

      for (final e in doc.findAllElements('rtept')) {
        final lat = double.tryParse(e.getAttribute('lat') ?? '');
        final lon = double.tryParse(e.getAttribute('lon') ?? '');
        if (lat == null || lon == null) continue;
        points.add([lat, lon]);
      }

      return points;
    } catch (_) {
      return const [];
    }
  }

  List<List<double>> _decodePolyline(String encoded) {
    var index = 0;
    var lat = 0;
    var lng = 0;
    final points = <List<double>>[];

    while (index < encoded.length) {
      var shift = 0;
      var result = 0;
      while (true) {
        final b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
        if (b < 0x20) break;
      }
      final dlat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lat += dlat;

      shift = 0;
      result = 0;
      while (true) {
        final b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
        if (b < 0x20) break;
      }
      final dlng = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lng += dlng;

      points.add([lat / 1e5, lng / 1e5]);
    }

    return points;
  }

  Future<Response<dynamic>> _getAthleteActivitiesWithToken({
    required String token,
    DateTime? after,
    DateTime? before,
    required int page,
    required int perPage,
  }) {
    return _dio.get<dynamic>(
      'https://www.strava.com/api/v3/athlete/activities',
      queryParameters: {
        if (after != null) 'after': after.toUtc().millisecondsSinceEpoch ~/ 1000,
        if (before != null) 'before': before.toUtc().millisecondsSinceEpoch ~/ 1000,
        'page': page,
        'per_page': perPage,
      },
      options: Options(
        headers: {'Authorization': 'Bearer $token'},
        validateStatus: (status) => status != null,
      ),
    );
  }

  List<String> _extractActivityIds(dynamic data) {
    if (data is List) {
      return data
          .whereType<Map<String, dynamic>>()
          .where((m) {
            final t = m['type']?.toString();
            if (t == null || t.isEmpty) return false;
            return t == 'Ride' || t == 'EBikeRide';
          })
          .map((m) => m['id']?.toString())
          .whereType<String>()
          .where((s) => s.isNotEmpty)
          .toList();
    }
    return const [];
  }

  Future<Response<Map<String, dynamic>>> _uploadWithToken({
    required String token,
    required File file,
    required Activity activity,
    required String externalId,
  }) async {
    final dataType = _dataTypeFor(file);
    final data = <String, dynamic>{
      'data_type': dataType,
      'external_id': externalId,
      'name': activity.name,
    };
    final sportType = _stravaSportType(activity.sportType);
    if (sportType != null) {
      data['sport_type'] = sportType;
    }
    data['file'] = await MultipartFile.fromFile(
      file.path,
      filename: file.uri.pathSegments.last,
      contentType: MediaType('application', 'octet-stream'),
    );

    final formData = FormData.fromMap(data);

    return _dio.post<Map<String, dynamic>>(
      'https://www.strava.com/api/v3/uploads',
      data: formData,
      options: Options(
        headers: {'Authorization': 'Bearer $token'},
        validateStatus: (status) => status != null,
      ),
    );
  }

  Future<String> _pollUpload({required String token, required String? uploadId}) async {
    if (uploadId == null || uploadId.isEmpty) {
      return '';
    }

    var currentToken = token;
    for (var i = 0; i < 15; i += 1) {
      await Future<void>.delayed(const Duration(seconds: 1));
      final status = await _dio.get<Map<String, dynamic>>(
        'https://www.strava.com/api/v3/uploads/$uploadId',
        options: Options(
          headers: {'Authorization': 'Bearer $currentToken'},
          validateStatus: (status) => status != null,
        ),
      );
      if (status.statusCode == 401) {
        currentToken = await _refreshAccessToken();
        continue;
      }
      if (status.statusCode != 200) {
        throw StravaException(_extractError(status));
      }
      final body = status.data ?? {};
      final error = body['error']?.toString();
      final activityId = body['activity_id']?.toString();
      if (error != null && error.isNotEmpty) {
        throw StravaException(error);
      }
      if (activityId != null && activityId.isNotEmpty) {
        return activityId;
      }
    }
    return '';
  }

  Future<String> _ensureAccessToken() async {
    final accessToken = await _kvStore.getSecureString(Keys.stravaAccessToken);
    final refreshToken = await _kvStore.getSecureString(Keys.stravaRefreshToken);
    final expiresAtRaw = await _kvStore.getSecureString(Keys.stravaExpiresAt);

    final expiresAt = int.tryParse(expiresAtRaw ?? '');
    final nowSeconds = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;

    if (accessToken != null &&
        accessToken.isNotEmpty &&
        (expiresAt == null || expiresAt - nowSeconds > 3600)) {
      return accessToken;
    }
    if (accessToken != null && accessToken.isNotEmpty && (refreshToken == null || refreshToken.isEmpty)) {
      return accessToken;
    }
    return _refreshAccessToken();
  }

  Future<String> _refreshAccessToken() async {
    final refreshToken = await _kvStore.getSecureString(Keys.stravaRefreshToken);
    if (refreshToken == null || refreshToken.isEmpty) {
      throw StateError('没有可用的 Refresh Token');
    }

    final response = await _dio.post<Map<String, dynamic>>(
      'https://www.strava.com/oauth/token',
      data: FormData.fromMap({
        'client_id': _clientId,
        'client_secret': _clientSecret,
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
      }),
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
    final payload = response.data;
    if (payload == null) {
      throw StateError('Strava refresh 返回为空');
    }
    await _persistTokenPayload(payload);
    final accessToken = payload['access_token']?.toString();
    if (accessToken == null || accessToken.isEmpty) {
      throw StateError('Strava 未返回 access_token');
    }
    return accessToken;
  }

  Future<void> _persistTokenPayload(Map<String, dynamic> payload) async {
    if (payload['access_token'] case final String token) {
      await _kvStore.setSecureString(Keys.stravaAccessToken, token);
    } else if (payload['access_token'] != null) {
      await _kvStore.setSecureString(Keys.stravaAccessToken, payload['access_token'].toString());
    }

    if (payload['refresh_token'] case final String token) {
      await _kvStore.setSecureString(Keys.stravaRefreshToken, token);
    } else if (payload['refresh_token'] != null) {
      await _kvStore.setSecureString(Keys.stravaRefreshToken, payload['refresh_token'].toString());
    }

    if (payload['expires_at'] != null) {
      await _kvStore.setSecureString(Keys.stravaExpiresAt, payload['expires_at'].toString());
    }
  }

  String _extractError(Response response) {
    final data = response.data;
    if (data is Map) {
      final error = data['error'];
      final message = data['message'];
      final errors = data['errors'];
      if (error != null) return error.toString();
      if (message != null) return message.toString();
      if (errors != null) return errors.toString();
    }
    return 'HTTP ${response.statusCode}: ${response.statusMessage ?? ''}'.trim();
  }
}

class StravaException implements Exception {
  StravaException(this.message);

  final String message;

  @override
  String toString() => message;
}

String _dataTypeFor(File file) {
  final path = file.path.toLowerCase();
  if (path.endsWith('.fit')) return 'fit';
  if (path.endsWith('.gpx')) return 'gpx';
  if (path.endsWith('.tcx')) return 'tcx';
  throw StravaException('不支持的文件类型：$path');
}

String? _stravaSportType(String? sportType) {
  if (sportType == null || sportType.trim().isEmpty) return null;

  switch (sportType.trim().toLowerCase()) {
    case 'cycling':
    case 'ride':
      return 'Ride';
    case 'running':
    case 'run':
      return 'Run';
    case 'trail_run':
      return 'TrailRun';
    case 'walking':
    case 'walk':
      return 'Walk';
    case 'hiking':
    case 'hike':
      return 'Hike';
    case 'swimming':
    case 'swim':
      return 'Swim';
    case 'indoor_cycling':
    case 'virtual_ride':
      return 'VirtualRide';
  }
  return null;
}
