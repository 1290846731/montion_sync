import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class KvStore {
  KvStore({required this.prefs, required this.secureStorage});

  final SharedPreferences prefs;
  final FlutterSecureStorage secureStorage;

  Future<void> setString(String key, String? value) async {
    if (value == null || value.isEmpty) {
      await prefs.remove(key);
      return;
    }
    await prefs.setString(key, value);
  }

  String? getString(String key) => prefs.getString(key);

  Future<void> setSecureString(String key, String? value) async {
    if (value == null || value.isEmpty) {
      await secureStorage.delete(key: key);
      return;
    }
    await secureStorage.write(key: key, value: value);
  }

  Future<String?> getSecureString(String key) => secureStorage.read(key: key);
}

abstract class Keys {
  static const appLanguage = 'app.language';

  static const igpsportUsername = 'igpsport.username';
  static const igpsportPassword = 'igpsport.password';
  static const igpsportAccessToken = 'igpsport.access_token';

  static const onelapUsername = 'onelap.username';
  static const onelapPassword = 'onelap.password';
  static const onelapCookie = 'onelap.cookie';

  static const intervalsApiKey = 'intervals.api_key';
  static const syncTarget = 'sync.target';

  // static const stravaClientId = 'strava.client_id';
  // static const stravaClientSecret = 'strava.client_secret';
  static const stravaAccessToken = 'strava.access_token';
  static const stravaRefreshToken = 'strava.refresh_token';
  static const stravaExpiresAt = 'strava.expires_at';

  static const heatmapSource = 'heatmap.source';

  static const lastSyncAtPrefix = 'sync.last_at.';
}
