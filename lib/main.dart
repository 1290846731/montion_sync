import 'package:flutter/material.dart';
import 'package:amap_map/amap_map.dart';
import 'package:mmkv/mmkv.dart';
import 'package:x_amap_base/x_amap_base.dart';

import 'app.dart';
import 'services/app_services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const privacy = AMapPrivacyStatement(
    hasContains: true,
    hasShow: true,
    hasAgree: true,
  );
  AMapInitializer.updatePrivacyAgree(privacy);
  final services = await AppServices.bootstrap();
  await MMKV.initialize();
  runApp(StravaSyncApp(services: services));
}
