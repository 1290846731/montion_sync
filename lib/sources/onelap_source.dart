import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import '../models/activity.dart';
import '../storage/kv_store.dart';
import '../utils/parsing.dart';
import 'source_adapter.dart';

class OneLapSource implements SourceAdapter {
  OneLapSource({required Dio dio, required KvStore kvStore})
      : _dio = dio,
        _kvStore = kvStore;

  final Dio _dio;
  final KvStore _kvStore;

  @override
  String get name => 'onelap';

  @override
  String get displayName => '顽鹿 OneLap';

  static const _signKey = 'fe9f8382418fcdeb136461cac6acae7b';

  @override
  Future<bool> isConfigured() async {
    final cookie = await _kvStore.getSecureString(Keys.onelapCookie);
    final username = await _kvStore.getSecureString(Keys.onelapUsername);
    final password = await _kvStore.getSecureString(Keys.onelapPassword);
    return (cookie != null && cookie.isNotEmpty) ||
        ((username != null && username.isNotEmpty) && (password != null && password.isNotEmpty));
  }

  @override
  Future<void> authenticate() async {
    final cookie = await _kvStore.getSecureString(Keys.onelapCookie);
    if (cookie != null && cookie.isNotEmpty) return;

    final username = await _kvStore.getSecureString(Keys.onelapUsername);
    final password = await _kvStore.getSecureString(Keys.onelapPassword);
    if (username == null || password == null || username.isEmpty || password.isEmpty) {
      throw StateError('OneLap 账号未配置');
    }

    final passwordMd5 = md5.convert(utf8.encode(password)).toString();
    final nonce = _randomHex(16);
    final timestamp = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
    final signatureRaw =
        'account=$username&nonce=$nonce&password=$passwordMd5&timestamp=$timestamp&key=$_signKey';
    final sign = md5.convert(utf8.encode(signatureRaw)).toString();

    final response = await _dio.post<Map<String, dynamic>>(
      'https://www.onelap.cn/api/login',
      data: {
        'account': username,
        'password': passwordMd5,
      },
      options: Options(
        headers: {
          'Accept': 'application/json, text/plain, */*',
          'Origin': 'https://u.onelap.cn',
          'Referer': 'https://u.onelap.cn/analysis',
          'nonce': nonce,
          'timestamp': timestamp,
          'sign': sign,
        },
      ),
    );
    final payload = response.data;
    if (payload == null) {
      throw StateError('OneLap 登录返回为空');
    }
    if (payload['code'] != 200) {
      throw StateError('OneLap 登录失败: ${payload['error'] ?? payload['msg'] ?? payload}');
    }

    final data = payload['data'];
    Map<String, dynamic>? first;
    if (data is List && data.isNotEmpty && data.first is Map) {
      first = Map<String, dynamic>.from(data.first as Map);
    } else if (data is Map) {
      first = Map<String, dynamic>.from(data);
    }
    if (first == null) {
      throw StateError('OneLap 登录未返回 token 数据');
    }

    final token = first['token']?.toString();
    final refreshToken = first['refresh_token']?.toString();
    final uid = (first['userinfo'] as Map?)?['uid']?.toString();

    final pieces = <String>[];
    if (token != null && token.isNotEmpty) pieces.add('XSRF-TOKEN=$token');
    if (refreshToken != null && refreshToken.isNotEmpty) pieces.add('OTOKEN=$refreshToken');
    if (uid != null && uid.isNotEmpty) pieces.add('ouid=$uid');
    final cookieString = pieces.join('; ');
    if (cookieString.isEmpty) {
      throw StateError('OneLap 登录未返回可用 Cookie');
    }
    await _kvStore.setSecureString(Keys.onelapCookie, cookieString);
  }

  Future<_CookieContext> _cookieContext() async {
    await authenticate();
    final cookie = await _kvStore.getSecureString(Keys.onelapCookie);
    if (cookie == null || cookie.isEmpty) {
      throw StateError('OneLap Cookie 为空');
    }
    final cookies = _parseCookieString(cookie);
    return _CookieContext(cookieHeader: cookie, xsrfToken: cookies['XSRF-TOKEN']);
  }

  @override
  Future<List<Activity>> listActivities({DateTime? since, DateTime? until, int? limit}) async {
    final ctx = await _cookieContext();
    final response = await _dio.get<Map<String, dynamic>>(
      'https://u.onelap.cn/analysis/list',
      options: Options(
        headers: {
          'Accept': 'application/json, text/plain, */*',
          'Origin': 'https://u.onelap.cn',
          'Referer': 'https://u.onelap.cn/analysis',
          'Cookie': ctx.cookieHeader,
          if (ctx.xsrfToken != null) 'X-XSRF-TOKEN': ctx.xsrfToken!,
        },
      ),
    );
    final payload = response.data;
    if (payload == null) {
      throw StateError('OneLap 列表返回为空');
    }
    final items = payload['data'];
    if (items is! List) {
      throw StateError('OneLap 列表格式错误: $payload');
    }

    final results = <Activity>[];
    final reversed = items.reversed.toList(growable: false);
    for (final item in reversed) {
      if (item is! Map) continue;
      final sourceId = (item['fileKey'] ?? item['created_at'] ?? item['id'])?.toString();
      if (sourceId == null || sourceId.isEmpty) continue;
      final start = parseDateTime(item['created_at'] ?? item['date']);
      final activity = Activity(
        source: name,
        sourceId: sourceId,
        name: (item['name']?.toString().trim().isNotEmpty ?? false)
            ? item['name'].toString()
            : '${item['date'] ?? 'onelap'} ride',
        sportType: 'cycling',
        startTime: start,
        raw: Map<String, dynamic>.from(item),
      );
      if (since != null && activity.startTime != null && activity.startTime!.isBefore(since.toUtc())) continue;
      if (until != null && activity.startTime != null && activity.startTime!.isAfter(until.toUtc())) continue;
      results.add(activity);
      if (limit != null && results.length >= limit) break;
    }
    return results;
  }

  @override
  Future<File> downloadFit({required Activity activity, required Directory outputDir}) async {
    final ctx = await _cookieContext();
    final dir = Directory('${outputDir.path}/$name');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final path = File('${dir.path}/${safeFilename(activity.sourceId)}.fit');
    if (path.existsSync() && path.lengthSync() > 100) return path;

    final rawUrl = activity.raw['durl']?.toString();
    if (rawUrl == null || rawUrl.isEmpty) {
      throw StateError('OneLap 活动缺少 durl');
    }
    final downloadUrl = _maybeRelativeUrl('https://u.onelap.cn', rawUrl);

    Response<List<int>> response = await _dio.get<List<int>>(
      downloadUrl,
      options: Options(
        responseType: ResponseType.bytes,
        validateStatus: (status) => status != null,
        headers: {
          'Cookie': ctx.cookieHeader,
          if (ctx.xsrfToken != null) 'X-XSRF-TOKEN': ctx.xsrfToken!,
        },
      ),
    );

    final contentType = response.headers.value('content-type')?.toLowerCase() ?? '';
    if (response.statusCode != null && response.statusCode! >= 400 || contentType.contains('text/html')) {
      response = await _dio.post<List<int>>(
        downloadUrl,
        options: Options(
          responseType: ResponseType.bytes,
          validateStatus: (status) => status != null,
          headers: {
            'Cookie': ctx.cookieHeader,
            if (ctx.xsrfToken != null) 'X-XSRF-TOKEN': ctx.xsrfToken!,
          },
        ),
      );
    }

    if (response.statusCode != 200 || response.data == null) {
      throw StateError('OneLap 下载失败: HTTP ${response.statusCode}');
    }
    await path.writeAsBytes(response.data!, flush: true);
    if (path.lengthSync() < 100) {
      throw StateError('OneLap 下载FIT过小');
    }
    return path;
  }
}

class _CookieContext {
  _CookieContext({required this.cookieHeader, required this.xsrfToken});

  final String cookieHeader;
  final String? xsrfToken;
}

String _randomHex(int length) {
  const chars = '0123456789abcdef';
  final rand = Random.secure();
  final buffer = StringBuffer();
  for (var i = 0; i < length; i += 1) {
    buffer.write(chars[rand.nextInt(chars.length)]);
  }
  return buffer.toString();
}

Map<String, String> _parseCookieString(String cookie) {
  final map = <String, String>{};
  for (final chunk in cookie.split(';')) {
    final idx = chunk.indexOf('=');
    if (idx <= 0) continue;
    final k = chunk.substring(0, idx).trim();
    final v = chunk.substring(idx + 1).trim();
    if (k.isNotEmpty) map[k] = v;
  }
  return map;
}

String _maybeRelativeUrl(String base, String value) {
  if (value.startsWith('http://') || value.startsWith('https://')) return value;
  if (value.startsWith('/')) return '${base.replaceAll(RegExp(r'/$'), '')}$value';
  return '${base.replaceAll(RegExp(r'/$'), '')}/$value';
}
