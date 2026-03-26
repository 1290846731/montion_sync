import 'dart:io';

import '../models/activity.dart';

abstract class SourceAdapter {
  String get name;
  String get displayName;

  Future<bool> isConfigured();

  Future<void> authenticate();

  Future<List<Activity>> listActivities({
    DateTime? since,
    DateTime? until,
    int? limit,
  });

  Future<File> downloadFit({
    required Activity activity,
    required Directory outputDir,
  });
}

