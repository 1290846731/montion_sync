import 'dart:io';
import 'package:flutter/material.dart';
import 'dart:async';

import 'features/settings/settings_screen.dart';
import 'features/sync/sync_screen.dart';
import 'features/heatmap/heatmap_screen.dart';
import 'services/app_services.dart';
import 'services/fit_file_handler.dart';
import 'storage/kv_store.dart';

class StravaSyncApp extends StatelessWidget {
  const StravaSyncApp({super.key, required this.services});

  final AppServices services;

  @override
  Widget build(BuildContext context) {
    final seed = Colors.deepOrange;
    return MaterialApp(
      title: 'Strava Sync',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.light),
        useMaterial3: true,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        appBarTheme: const AppBarTheme(
          centerTitle: false,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
        snackBarTheme: const SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          showCloseIcon: true,
        ),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark),
        useMaterial3: true,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        appBarTheme: const AppBarTheme(
          centerTitle: false,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
        snackBarTheme: const SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          showCloseIcon: true,
        ),
      ),
      themeMode: ThemeMode.system,
      home: _Home(services: services),
    );
  }
}

class _Home extends StatefulWidget {
  const _Home({required this.services});

  final AppServices services;

  @override
  State<_Home> createState() => _HomeState();
}

class _HomeState extends State<_Home> {
  int _index = 0;
  bool _isUploadingShared = false;
  StreamSubscription<String>? _fitFileSub;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      FitFileHandler.instance.init();
      _fitFileSub = FitFileHandler.instance.fileStream.listen((path) {
        if (path.isNotEmpty) {
          _uploadSharedFile(path);
        }
      });
    });
  }

  @override
  void dispose() {
    _fitFileSub?.cancel();
    super.dispose();
  }

  Future<void> _uploadSharedFile(String path) async {
    if (_isUploadingShared) return;
    setState(() => _isUploadingShared = true);

    try {
      final record = await widget.services.syncService.uploadLocalFile(
        file: File(path),
        sourceLabel: 'shared_file',
      );
      if (!mounted) return;
      final target = (widget.services.kvStore.getString(Keys.syncTarget) ?? 'strava').toLowerCase();
      final tip = target == 'intervals' ? '同步ICU成功' : '同步到Strava成功';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            record.status == 'success' ? tip : '外部文件上传完成：${record.status}',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('外部文件上传失败：$e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isUploadingShared = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      SyncScreen(services: widget.services),
      HeatmapScreen(services: widget.services),
      SettingsScreen(services: widget.services),
    ];

    return Scaffold(
      body: screens[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.sync), label: '同步'),
          NavigationDestination(icon: Icon(Icons.map), label: '热力图'),
          NavigationDestination(icon: Icon(Icons.settings), label: '设置'),
        ],
      ),
    );
  }
}
