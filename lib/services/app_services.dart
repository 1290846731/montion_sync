import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../storage/kv_store.dart';
import '../storage/sync_db.dart';
import '../strava/strava_client.dart';
import '../sync/sync_service.dart';
import '../sources/igpsport_source.dart';
import '../sources/onelap_source.dart';
import '../sources/source_registry.dart';

class AppServices {
  AppServices._({
    required this.kvStore,
    required this.syncDb,
    required this.dio,
    required this.stravaClient,
    required this.sourceRegistry,
    required this.syncService,
  });

  final KvStore kvStore;
  final SyncDb syncDb;
  final Dio dio;
  final StravaClient stravaClient;
  final SourceRegistry sourceRegistry;
  final SyncService syncService;

  static Future<AppServices> bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    const secureStorage = FlutterSecureStorage();

    final kvStore = KvStore(prefs: prefs, secureStorage: secureStorage);
    final syncDb = await SyncDb.open();

    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 120),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36',
        },
      ),
    );

    final stravaClient = StravaClient(dio: dio, kvStore: kvStore);

    final sourceRegistry = SourceRegistry(
      sources: [
        IGPSportSource(dio: dio, kvStore: kvStore),
        OneLapSource(dio: dio, kvStore: kvStore),
      ],
    );

    final syncService = SyncService(
      kvStore: kvStore,
      syncDb: syncDb,
      sourceRegistry: sourceRegistry,
      stravaClient: stravaClient,
    );

    return AppServices._(
      kvStore: kvStore,
      syncDb: syncDb,
      dio: dio,
      stravaClient: stravaClient,
      sourceRegistry: sourceRegistry,
      syncService: syncService,
    );
  }
}
