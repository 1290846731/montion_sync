import 'dart:io';
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'features/settings/settings_screen.dart';
import 'features/sync/sync_screen.dart';
import 'features/heatmap/heatmap_screen.dart';
import 'i18n/app_i18n.dart';
import 'services/app_services.dart';
import 'services/fit_file_handler.dart';
import 'storage/kv_store.dart';

class StravaSyncApp extends StatefulWidget {
  const StravaSyncApp({super.key, required this.services});

  final AppServices services;

  @override
  State<StravaSyncApp> createState() => _StravaSyncAppState();
}

class _StravaSyncAppState extends State<StravaSyncApp> {
  late final AppLanguageController _languageController = AppLanguageController(kvStore: widget.services.kvStore);

  @override
  void dispose() {
    _languageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final seed = Colors.deepOrange;
    return AppI18n(
      notifier: _languageController,
      child: AnimatedBuilder(
        animation: _languageController,
        builder: (context, _) => MaterialApp(
          title: _languageController.strings.appTitle,
          locale: _languageController.locale,
          supportedLocales: const [Locale('zh'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
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
          home: _Home(services: widget.services),
        ),
      ),
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
  final Set<int> _builtTabs = <int>{0};

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
      final s = AppI18n.s(context);
      final target = (widget.services.kvStore.getString(Keys.syncTarget) ?? 'strava').toLowerCase();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            record.status == 'success' ? s.syncSuccessTip(target) : s.uploadDone(record.status),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final s = AppI18n.s(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.uploadFailed(s.errorText(e)))),
      );
    } finally {
      if (mounted) {
        setState(() => _isUploadingShared = false);
      }
    }
  }

  Widget _tabAt(int index) {
    if (!_builtTabs.contains(index) && index != _index) return const SizedBox.shrink();
    _builtTabs.add(index);
    return switch (index) {
      0 => SyncScreen(services: widget.services),
      1 => HeatmapScreen(services: widget.services),
      _ => SettingsScreen(services: widget.services),
    };
  }

  @override
  Widget build(BuildContext context) {
    final s = AppI18n.s(context);

    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          _tabAt(0),
          _tabAt(1),
          _tabAt(2),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() {
          _builtTabs.add(value);
          _index = value;
        }),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.sync), label: s.navSync),
          NavigationDestination(icon: const Icon(Icons.map), label: s.navHeatmap),
          NavigationDestination(icon: const Icon(Icons.settings), label: s.navSettings),
        ],
      ),
    );
  }
}
