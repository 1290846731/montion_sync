import 'package:flutter/material.dart';
import 'package:amap_map/amap_map.dart';
import 'package:x_amap_base/x_amap_base.dart';
import '../../services/app_services.dart';

class HeatmapScreen extends StatefulWidget {
  const HeatmapScreen({super.key, required this.services});
  final AppServices services;
  @override
  State<HeatmapScreen> createState() => _HeatmapScreenState();
}

class _HeatmapScreenState extends State<HeatmapScreen> {
  final int _minYear = 2010;
  int _year = DateTime.now().year;
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
    _loadFromStrava();
  }

  @override
  void dispose() {
    super.dispose();
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
        final pageResult = await widget.services.stravaClient.listRideRoutesPage(
          after: after,
          before: before,
          page: page,
          perPage: perPage,
        );
        if (pageResult.activityCount == 0) break;
        routes.addAll(pageResult.routes);
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
    final color = const Color(0xFFFF5A00).withValues(alpha: 0.15);
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('骑行热力图'),
        actions: [
          PopupMenuButton<int>(
            initialValue: _year,
            itemBuilder: (_) => [
              for (final y in years) PopupMenuItem<int>(value: y, child: Text('$y')),
            ],
            onSelected: (y) {
              setState(() => _year = y);
              _loadFromStrava();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Center(child: Text('$_year')),
            ),
          ),
          IconButton(
            onPressed: _loading ? null : _loadFromStrava,
            icon: const Icon(Icons.refresh),
            tooltip: '从 Strava 获取',
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
