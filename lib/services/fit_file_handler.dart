import 'dart:async';
import 'dart:io';
import 'package:app_links/app_links.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

class FitFileHandler {
  FitFileHandler._();
  static final FitFileHandler instance = FitFileHandler._();

  final _controller = StreamController<String>.broadcast();
  StreamSubscription? _shareStreamSub;
  StreamSubscription? _subscription;
  final MethodChannel _nativeChannel = const MethodChannel('com.mj.stravasync/fitfile');

  bool _initialized = false;

  Stream<String> get fileStream => _controller.stream;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;



    // 检查初始链接
    try {
      var initialLink = await AppLinks().getInitialLinkString();
      if (initialLink != null) {
        _dispatchLinkWithDelay(initialLink, 3);
      }


      // 监听后续的链接
      _subscription = AppLinks().stringLinkStream.listen((String? link) {
        if (link != null) {
          _dispatchLinkWithDelay(link, 1);
        }
      }, onError: (err) {
        _subscription?.cancel();
        debugPrint('Failed to get link: $err');
      });
    } on PlatformException {
      // 处理错误
      debugPrint('Failed to get initial link.');
    }


    _nativeChannel.setMethodCallHandler((call) async {
      if (call.method == 'fileOpened') {
        final path = call.arguments as String?;
        if (path != null && path.isNotEmpty && _acceptPath(path)) {
          final ok = await _checkPermissions();
          if (ok) _controller.add(path);
        }
      }
    });
    try {
      final initial = await _nativeChannel.invokeMethod<List<dynamic>>('getInitialOpenedFiles');
      if (initial != null) {
        for (final e in initial) {
          final p = e?.toString() ?? '';
          if (p.isNotEmpty && _acceptPath(p)) {
            final ok = await _checkPermissions();
            if (ok) _controller.add(p);
          }
        }
      }
    } catch (_) {}

    _shareStreamSub = null;
  }

  static void _dispatchLinkWithDelay(String link, int delaySeconds) {
    Future.delayed(Duration(seconds: delaySeconds), () {
      instance._handleLink(link);
    });
  }

  Future<void> _handleLink(String link) async {
    final resolvedPath = _resolvePathFromLink(link);
    if (resolvedPath == null) return;
    if (!_acceptPath(resolvedPath)) return;
    final ok = await _checkPermissions();
    if (!ok) return;
    _controller.add(resolvedPath);
  }

  String? _resolvePathFromLink(String link) {
    try {
      final l = link.trim();
      if (l.isEmpty) return null;
      if (l.startsWith('/')) return l;
      final uri = Uri.tryParse(l);
      if (uri == null) return l;
      if (uri.scheme == 'file') {
        return uri.toFilePath();
      }
      if (Platform.isAndroid && uri.scheme == 'content') {
        final lowerHost = uri.host.toLowerCase();
        final path = uri.path;
        if (lowerHost.contains('externalstorage') && path.contains('document/')) {
          final encoded = path.split('document/').last;
          final decoded = Uri.decodeComponent(encoded);
          if (decoded.startsWith('primary:')) {
            final tail = decoded.substring('primary:'.length);
            return '/storage/emulated/0/$tail';
          }
        }
        final full = uri.toString();
        if (full.contains('primary%3A')) {
          final after = full.split('primary%3A').last;
          final decodedTail = Uri.decodeComponent(after);
          return '/storage/emulated/0/$decodedTail';
        }
      }
      if (uri.scheme.isEmpty && l.toLowerCase().endsWith('.fit')) {
        return l;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> dispose() async {
    await _shareStreamSub?.cancel();
    await _subscription?.cancel();
    await _controller.close();
  }

  bool _acceptPath(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.fit');
  }

  static Future<bool> _checkPermissions() async {
    if (Platform.isAndroid) {
      // Check Android version
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      final sdkInt = androidInfo.version.sdkInt;

      if (sdkInt >= 30) { // Android 11+
        // For Android 11+, we need MANAGE_EXTERNAL_STORAGE permission
        final status = await Permission.manageExternalStorage.status;
        if (status.isDenied) {
          final result = await Permission.manageExternalStorage.request();
          if (result.isDenied) {
            // If user denied, show a dialog explaining why we need this permission
            return false;
          }
          return result.isGranted;
        }
        return status.isGranted;
      } else if (sdkInt >= 29) { // Android 10
        // For Android 10, we need storage permission
        final status = await Permission.storage.status;
        if (status.isDenied) {
          final result = await Permission.storage.request();
          return result.isGranted;
        }
        return status.isGranted;
      } else { // Android 9 and below
        final status = await Permission.storage.status;
        if (status.isDenied) {
          final result = await Permission.storage.request();
          return result.isGranted;
        }
        return status.isGranted;
      }
    }
    return true;
  }
}
