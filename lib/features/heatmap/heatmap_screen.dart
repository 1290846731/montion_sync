import 'dart:io';

import 'package:flutter/material.dart';
import 'package:amap_map/amap_map.dart';
import 'package:fit_sdk/fit_sdk.dart' as fit;
import 'package:path_provider/path_provider.dart';
import 'package:xml/xml.dart';
import 'package:x_amap_base/x_amap_base.dart';
import '../../services/app_services.dart';
import '../../sources/igpsport_source.dart';
import '../../storage/kv_store.dart';

enum HeatmapSource { strava, igpsport }

class HeatmapScreen extends StatefulWidget {
  const HeatmapScreen({super.key, required this.services});
  final AppServices services;
  @override
  State<HeatmapScreen> createState() => _HeatmapScreenState();
}

class _HeatmapScreenState extends State<HeatmapScreen> {
  final int _minYear = 2010;
  int _year = DateTime.now().year;
  HeatmapSource _source = HeatmapSource.strava;
  bool _loading = false;
  String? _loadError;
  List<List<List<double>>> _routes = const [];
  bool _mapReady = false;
  final Key _mapKey = UniqueKey();
  AMapController? _amapController;
  static const AMapApiKey _amapKeys = AMapApiKey(androidKey: 'fa1e0dca85328840c53cc33522854cf3', iosKey: '');
  static const AMapPrivacyStatement _amapPrivacy = AMapPrivacyStatement(
    hasContains: true,
    hasShow: true,
    hasAgree: true,
  );

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _init() async {
    final raw = widget.services.kvStore.getString(Keys.heatmapSource) ?? 'strava';
    final source = raw.toLowerCase() == 'igpsport' ? HeatmapSource.igpsport : HeatmapSource.strava;
    if (!mounted) return;
    setState(() => _source = source);
    await _loadFromSource();
  }

  Future<void> _loadFromSource() async {
    if (_source == HeatmapSource.igpsport) {
      return _loadFromIgpsport();
    }
    return _loadFromStrava();
  }

  Future<void> _loadFromStrava() async {
    if (_loading) return;
    if (!await widget.services.stravaClient.isConfigured()) {
      if (!mounted) return;
      setState(() {
        _loadError = '请先绑定strava';
        _routes = const [];
      });
      return;
    }

    setState(() {
      _loading = true;
      _loadError = null;
    });

    try {
      final after = DateTime(_year, 1, 1);
      final before = DateTime(_year + 1, 1, 1);
      const perPage = 50;
      const maxPages = 6;
      final routes = <List<List<double>>>[];
      for (var page = 1; page <= maxPages; page += 1) {
        final pageResult = await widget.services.stravaClient.listRideSummariesPage(
          after: after,
          before: before,
          page: page,
          perPage: perPage,
        );
        if (pageResult.activityCount == 0) break;
        final pageRoutes = await _fetchStravaRoutes(pageResult.rides);
        routes.addAll(pageRoutes);
        if (pageResult.activityCount < perPage) break;
      }

      if (!mounted) return;
      setState(() {
        _routes = routes;
      });
      _centerToRoutes();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.toString();
        _routes = const [];
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<List<List<List<double>>>> _fetchStravaRoutes(List<({String id, String? summaryPolyline})> rides) async {
    if (rides.isEmpty) return const [];
    const concurrency = 4;
    final routes = <List<List<double>>>[];
    var i = 0;

    Future<void> worker() async {
      while (true) {
        final current = i;
        i += 1;
        if (current >= rides.length) return;
        final ride = rides[current];
        final pts = await widget.services.stravaClient.getActivityRoutePoints(
          activityId: ride.id,
          summaryPolyline: ride.summaryPolyline,
        );
        if (pts.length >= 2) {
          routes.add(pts);
        }
      }
    }

    await Future.wait(List.generate(concurrency, (_) => worker()));
    return routes;
  }

  Future<void> _loadFromIgpsport() async {
    if (_loading) return;
    final source = widget.services.sourceRegistry.byName('igpsport');
    if (!await source.isConfigured()) {
      if (!mounted) return;
      setState(() {
        _loadError = '请先配置 IGPSPORT 账号';
        _routes = const [];
      });
      return;
    }

    setState(() {
      _loading = true;
      _loadError = null;
    });

    try {
      final after = DateTime(_year, 1, 1);
      final before = DateTime(_year + 1, 1, 1);
      final igpsport = source as IGPSportSource;
      final activities = await igpsport.listActivitiesForExport(
        exportType: IGPSportExportType.gpx,
        since: after,
        until: before,
        maxPages: 20,
      );

      final outputDir = await getTemporaryDirectory();
      final routes = <List<List<double>>>[];

      for (final activity in activities) {
        var pts = const <List<double>>[];
        try {
          final gpx = await igpsport.downloadGpx(activity: activity, outputDir: outputDir);
          pts = await _parseGpxRoute(gpx);
        } catch (_) {}

        if (pts.length < 2) {
          try {
            final fitFile = await igpsport.downloadFit(activity: activity, outputDir: outputDir);
            pts = await _parseFitRoute(fitFile);
          } catch (_) {}
        }

        if (pts.length >= 2) {
          routes.add(pts);
        }
      }

      if (!mounted) return;
      setState(() => _routes = routes);
      _centerToRoutes();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.toString();
        _routes = const [];
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<List<List<double>>> _parseGpxRoute(File file) async {
    final text = await file.readAsString();
    final doc = XmlDocument.parse(text);
    final points = <List<double>>[];
    for (final trkpt in doc.findAllElements('trkpt')) {
      final latStr = trkpt.getAttribute('lat');
      final lonStr = trkpt.getAttribute('lon');
      if (latStr == null || lonStr == null) continue;
      final lat = double.tryParse(latStr);
      final lon = double.tryParse(lonStr);
      if (lat == null || lon == null) continue;
      points.add([lat, lon]);
    }
    return points;
  }

  Future<List<List<double>>> _parseFitRoute(File file) async {
    final bytes = await file.readAsBytes();
    final decoder = fit.Decode();
    final points = <List<double>>[];

    decoder.onMesg = (mesg) {
      if (mesg.name.toLowerCase() != 'record') return;
      final latRaw = mesg.getFieldValue(0);
      final lonRaw = mesg.getFieldValue(1);
      if (latRaw is! num || lonRaw is! num) return;

      final lat = _fitMaybeToDegrees(latRaw);
      final lon = _fitMaybeToDegrees(lonRaw);
      if (lat.isNaN || lon.isNaN) return;
      if (lat.abs() > 90 || lon.abs() > 180) return;
      points.add([lat, lon]);
    };

    decoder.read(bytes);

    if (points.length <= 3000) return points;
    final step = (points.length / 3000).ceil();
    final sampled = <List<double>>[];
    for (var i = 0; i < points.length; i += step) {
      sampled.add(points[i]);
    }
    return sampled;
  }

  double _fitMaybeToDegrees(num v) {
    final d = v.toDouble();
    if (d.abs() <= 180) return d;
    return d * (180.0 / 2147483648.0);
  }

  void _centerToRoutes() {
    if (!_mapReady) return;
    if (_routes.isEmpty) return;
    final first = _routes.first;
    final mid = first[first.length ~/ 2];
    try {
      final target = LatLng(mid[0], mid[1]);
      _amapController?.moveCamera(
        CameraUpdate.newCameraPosition(CameraPosition(target: target, zoom: 11)),
      );
    } catch (_) {}
  }

  Set<Polyline> _buildPolylines() {
    if (_routes.isEmpty) return const {};
    final color = const Color(0xFFFF5A00).withValues(alpha: 0.2);
    return _routes
        .where((pts) => pts.length >= 2)
        .map(
          (pts) => Polyline(
            width: 5,
            color: color,
            points: pts.map((p) => LatLng(p[0], p[1])).toList(),
          ),
        )
        .toSet();
  }

  @override
  Widget build(BuildContext context) {
    AMapInitializer.init(context, apiKey: _amapKeys);
    AMapInitializer.updatePrivacyAgree(_amapPrivacy);
    final nowYear = DateTime.now().year;
    final years = <int>[
      for (var y = nowYear; y >= _minYear; y -= 1) y,
    ];

    final sourceLabel = _source == HeatmapSource.igpsport ? 'IGPSPORT' : 'Strava';
    return Scaffold(
      appBar: AppBar(
        title: const Text('骑行热力图'),
        actions: [
          PopupMenuButton<HeatmapSource>(
            initialValue: _source,
            itemBuilder: (_) => const [
              PopupMenuItem(value: HeatmapSource.strava, child: Text('Strava')),
              PopupMenuItem(value: HeatmapSource.igpsport, child: Text('IGPSPORT')),
            ],
            onSelected: (s) async {
              setState(() => _source = s);
              await widget.services.kvStore.setString(
                Keys.heatmapSource,
                s == HeatmapSource.igpsport ? 'igpsport' : 'strava',
              );
              await _loadFromSource();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Center(child: Text(sourceLabel)),
            ),
          ),
          PopupMenuButton<int>(
            initialValue: _year,
            itemBuilder: (_) => [
              for (final y in years) PopupMenuItem<int>(value: y, child: Text('$y')),
            ],
            onSelected: (y) {
              setState(() => _year = y);
              _loadFromSource();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Center(child: Text('$_year')),
            ),
          ),
          IconButton(
            onPressed: _loading ? null : _loadFromSource,
            icon: const Icon(Icons.refresh),
            tooltip: '从 $sourceLabel 获取',
          ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
        ],
      ),
      body: Stack(
        children: [
          AMapWidget(
            key: _mapKey,
            initialCameraPosition: const CameraPosition(
              target: LatLng(30, 120),
              zoom: 11,
            ),
            mapType: MapType.night,
            onMapCreated: (c) {
              _amapController = c;
              _mapReady = true;
              _centerToRoutes();
            },
            polylines: _buildPolylines(),
          ),
          if (_loadError != null)
            Center(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(_loadError!),
                ),
              ),
            )
          else if (!_loading && _routes.isEmpty)
            const Center(
              child: Card(
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('暂无轨迹'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
