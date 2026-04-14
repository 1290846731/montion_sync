import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:amap_map/amap_map.dart';
import 'package:fit_sdk/fit_sdk.dart' as fit;
import 'package:gal/gal.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:xml/xml.dart';
import 'package:x_amap_base/x_amap_base.dart';

import '../../i18n/app_i18n.dart';
import '../../core/payment/iap_service.dart';
import '../../services/app_services.dart';
import '../../sources/igpsport_source.dart';
import '../../storage/kv_store.dart';
import '../../utils/storage_utils.dart';

enum HeatmapSource { strava, igpsport, onelap }

class HeatmapScreen extends StatefulWidget {
  const HeatmapScreen({
    super.key,
    required this.services,
    required this.selectedTabIndex,
    this.tabIndex = 1,
  });
  final AppServices services;
  final ValueListenable<int> selectedTabIndex;
  final int tabIndex;
  @override
  State<HeatmapScreen> createState() => _HeatmapScreenState();
}

class _HeatmapScreenState extends State<HeatmapScreen> with WidgetsBindingObserver {
  static final Uint8List _transparentPng1x1 = Uint8List.fromList(<int>[
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
    0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
    0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
    0x42, 0x60, 0x82,
  ]);
  static final BitmapDescriptor _transparentBitmap = BitmapDescriptor.fromBytes(_transparentPng1x1);

  final int _minYear = 2010;
  int _year = DateTime.now().year;
  HeatmapSource _source = HeatmapSource.strava;
  bool _loading = false;
  bool _exporting = false;
  String? _loadError;
  List<List<List<double>>> _routes = const [];
  bool _mapReady = false;
  final Key _mapKey = UniqueKey();
  final GlobalKey _exportKey = GlobalKey();
  AMapController? _amapController;
  bool _isActiveTab = false;
  bool _checkingLocationPermission = false;
  bool _awaitingLocationPermissionFromSettings = false;
  LatLng? _lastUserLocation;
  bool _centerOnUserLocationWhenAvailable = false;
  MyLocationStyleOptions _myLocationStyle = MyLocationStyleOptions(false);
  static const AMapApiKey _amapKeys = AMapApiKey(androidKey: 'fa1e0dca85328840c53cc33522854cf3', iosKey: '43c277d17d9481607a7ddd3745dec466');
  static const AMapPrivacyStatement _amapPrivacy = AMapPrivacyStatement(
    hasContains: true,
    hasShow: true,
    hasAgree: true,
  );
  static const String _subscriptionProductId = 'com.mj.stravasync.p2';
  final IapService _iapService = IapService();
  bool _purchasing = false;

  String _sourceLabel(HeatmapSource s) {
    return switch (s) {
      HeatmapSource.strava => 'Strava',
      HeatmapSource.igpsport => 'IGPSPORT',
      HeatmapSource.onelap => 'OneLap',
    };
  }

  String _sourceKey(HeatmapSource s) {
    return switch (s) {
      HeatmapSource.strava => 'strava',
      HeatmapSource.igpsport => 'igpsport',
      HeatmapSource.onelap => 'onelap',
    };
  }

  IconData _sourceIcon(HeatmapSource s) {
    return switch (s) {
      HeatmapSource.strava => Icons.directions_bike_outlined,
      HeatmapSource.igpsport => Icons.route_outlined,
      HeatmapSource.onelap => Icons.pedal_bike_outlined,
    };
  }

  String _sourceSubtitle(AppStrings strings, HeatmapSource source) {
    return switch (source) {
      HeatmapSource.strava => strings.language == AppLanguage.zh ? '通过 Strava API 拉取轨迹' : 'Fetch routes via Strava API',
      HeatmapSource.igpsport => strings.language == AppLanguage.zh ? '从 IGPSPORT 下载 GPX/FIT 解析' : 'Download & parse GPX/FIT from IGPSPORT',
      HeatmapSource.onelap => strings.language == AppLanguage.zh ? '从 顽鹿 OneLap 下载 FIT 解析' : 'Download & parse FIT from OneLap',
    };
  }

  Future<void> _setSource(HeatmapSource s) async {
    setState(() {
      _source = s;
      _routes = const [];
      _loadError = null;
    });
    await widget.services.kvStore.setString(Keys.heatmapSource, _sourceKey(s));
  }

  Future<void> _exportHeatmap() async {
    if (_exporting) return;
    final messenger = ScaffoldMessenger.of(context);
    final strings = AppI18n.s(context);
    final pixelRatio = MediaQuery.devicePixelRatioOf(context).clamp(1.0, 3.0);
    setState(() => _exporting = true);
    try {
      await Future<void>.delayed(const Duration(milliseconds: 16));
      await WidgetsBinding.instance.endOfFrame;

      final boundary = _exportKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        if (!mounted) return;
        messenger.showSnackBar(SnackBar(content: Text(strings.saveFailedNotReady)));
        return;
      }

      final image = await boundary.toImage(pixelRatio: pixelRatio);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        if (!mounted) return;
        messenger.showSnackBar(SnackBar(content: Text(strings.saveFailedImageGen)));
        return;
      }

      final bytes = byteData.buffer.asUint8List();
      final dir = await getApplicationDocumentsDirectory();
      final outDir = Directory(p.join(dir.path, 'exports', 'heatmaps'));
      if (!outDir.existsSync()) outDir.createSync(recursive: true);

      final ts = DateTime.now().millisecondsSinceEpoch;
      final filename = 'heatmap_${_sourceKey(_source)}_${_year}_$ts.png';
      final file = File(p.join(outDir.path, filename));
      await file.writeAsBytes(bytes, flush: true);

      final albumName = 'MotionSync';
      var hasAccess = await Gal.hasAccess(toAlbum: true);
      if (!hasAccess) {
        await Gal.requestAccess(toAlbum: true);
        hasAccess = await Gal.hasAccess(toAlbum: true);
      }
      if (!hasAccess) {
        if (!mounted) return;
        messenger.showSnackBar(SnackBar(content: Text(strings.saveFailedNoAlbumPerm)));
        return;
      }

      try {
        await Gal.putImage(file.path, album: albumName);
      } on GalException {
        await Gal.putImage(file.path);
      }

      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(strings.savedToAlbum)));
    } on GalException catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(strings.saveFailed(e.type.message))));
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(strings.saveFailed('$e'))));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  List<List<double>> _convertRoutePoints(List<List<double>> pts) {
    if (pts.length < 2) return const [];
    final out = <List<double>>[];
    for (final p in pts) {
      if (p.length < 2) continue;
      final lat = p[0];
      final lon = p[1];
      out.add(_wgs84ToGcj02(lat, lon));
    }
    return out;
  }

  static const double _gcjA = 6378245.0;
  static const double _gcjEe = 0.00669342162296594323;

  bool _isInChina(double lat, double lon) {
    if (lon < 72.004 || lon > 137.8347) return false;
    if (lat < 0.8293 || lat > 55.8271) return false;
    return true;
  }

  List<double> _wgs84ToGcj02(double lat, double lon) {
    if (!_isInChina(lat, lon)) return [lat, lon];
    var dLat = _transformLat(lon - 105.0, lat - 35.0);
    var dLon = _transformLon(lon - 105.0, lat - 35.0);
    final radLat = lat / 180.0 * pi;
    var magic = sin(radLat);
    magic = 1 - _gcjEe * magic * magic;
    final sqrtMagic = sqrt(magic);
    dLat = (dLat * 180.0) / (((_gcjA * (1 - _gcjEe)) / (magic * sqrtMagic)) * pi);
    dLon = (dLon * 180.0) / ((_gcjA / sqrtMagic) * cos(radLat) * pi);
    return [lat + dLat, lon + dLon];
  }

  double _transformLat(double x, double y) {
    var ret = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * sqrt(x.abs());
    ret += (20.0 * sin(6.0 * x * pi) + 20.0 * sin(2.0 * x * pi)) * 2.0 / 3.0;
    ret += (20.0 * sin(y * pi) + 40.0 * sin(y / 3.0 * pi)) * 2.0 / 3.0;
    ret += (160.0 * sin(y / 12.0 * pi) + 320.0 * sin(y * pi / 30.0)) * 2.0 / 3.0;
    return ret;
  }

  double _transformLon(double x, double y) {
    var ret = 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * sqrt(x.abs());
    ret += (20.0 * sin(6.0 * x * pi) + 20.0 * sin(2.0 * x * pi)) * 2.0 / 3.0;
    ret += (20.0 * sin(x * pi) + 40.0 * sin(x / 3.0 * pi)) * 2.0 / 3.0;
    ret += (150.0 * sin(x / 12.0 * pi) + 300.0 * sin(x / 30.0 * pi)) * 2.0 / 3.0;
    return ret;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.selectedTabIndex.addListener(_onTabIndexChanged);
    _onTabIndexChanged();
    _init();
  }

  @override
  void dispose() {
    widget.selectedTabIndex.removeListener(_onTabIndexChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _awaitingLocationPermissionFromSettings) {
      _awaitingLocationPermissionFromSettings = false;
      _handleMapActivated();
    }
  }

  Future<void> _init() async {
    final raw = widget.services.kvStore.getString(Keys.heatmapSource) ?? 'strava';
    final lower = raw.toLowerCase();
    final source = lower == 'igpsport'
        ? HeatmapSource.igpsport
        : lower == 'onelap'
            ? HeatmapSource.onelap
            : HeatmapSource.strava;
    if (!mounted) return;
    setState(() => _source = source);
  }

  void _onTabIndexChanged() {
    final isActive = widget.selectedTabIndex.value == widget.tabIndex;
    if (isActive == _isActiveTab) return;
    _isActiveTab = isActive;
    if (_isActiveTab) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (!_isActiveTab) return;
        _handleMapActivated();
      });
    }
  }

  Permission _locationPermission() {
    if (Platform.isIOS) return Permission.locationWhenInUse;
    return Permission.location;
  }

  Future<void> _handleMapActivated() async {
    if (_checkingLocationPermission) return;
    _checkingLocationPermission = true;
    try {
      final granted = await _ensureLocationPermission();
      if (!granted) return;
      if (!mounted) return;
      setState(() {
        _myLocationStyle = MyLocationStyleOptions(
          true,
          icon: _transparentBitmap,
          circleFillColor: Colors.transparent,
          circleStrokeColor: Colors.transparent,
          circleStrokeWidth: 0,
        );
      });
      _centerOnUserLocationWhenAvailable = true;
      _centerToUserLocationIfPossible();
    } finally {
      _checkingLocationPermission = false;
    }
  }

  Future<bool> _ensureLocationPermission() async {
    final perm = _locationPermission();
    var status = await perm.status;
    if (status.isGranted) return true;

    if (status.isDenied) {
      status = await perm.request();
      if (status.isGranted) return true;
    }

    if (!mounted) return false;
    await _showLocationPermissionSheet();
    return false;
  }

  Future<void> _showLocationPermissionSheet() async {
    final s = AppI18n.s(context);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(s.locationPermissionTitle, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(s.locationPermissionDesc, style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () async {
                    _awaitingLocationPermissionFromSettings = true;
                    Navigator.of(context).pop();
                    await openAppSettings();
                  },
                  child: Text(s.openSettings),
                ),
                const SizedBox(height: 8),
                FilledButton.tonal(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(s.notNow),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _centerToUserLocationIfPossible() {
    if (!_mapReady) return;
    final target = _lastUserLocation;
    if (target == null) return;
    if (!_centerOnUserLocationWhenAvailable) return;
    _centerOnUserLocationWhenAvailable = false;
    try {
      _amapController?.moveCamera(
        CameraUpdate.newCameraPosition(CameraPosition(target: target, zoom: 13)),
      );
    } catch (_) {}
  }

  Future<void> _loadFromSource() async {
    // final ok = await _ensurePurchasedForSync();
    // if (!ok) return;
    return _loadFromSourceInternal();
  }

  Future<void> _loadFromSourceInternal() async {
    if (_source == HeatmapSource.igpsport) {
      return _loadFromIgpsport();
    }
    if (_source == HeatmapSource.onelap) {
      return _loadFromOnelap();
    }
    return _loadFromStrava();
  }

  Future<bool> _ensurePurchasedForSync() async {
    if (StorageUtils.isSubscription()) return true;
    if (_purchasing) return false;
    if (!mounted) return false;

    _purchasing = true;
    StreamSubscription<BuyState>? buySub;
    StreamSubscription<SubscriptionState>? subStateSub;
    final completer = Completer<bool>();

    try {
      final strings = AppI18n.s(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(strings.language == AppLanguage.zh ? '需要购买后才能同步，正在发起支付…' : 'Purchase required. Starting payment…'),
        ),
      );

      _iapService.init(subscriptionProductIds: const [_subscriptionProductId]);

      buySub = _iapService.purchaseStream.listen((state) {
        if (state.productId != _subscriptionProductId) return;
        if (state is BuyErrorState) {
          if (!completer.isCompleted) completer.complete(false);
        }
      });

      subStateSub = _iapService.subscriptionStream.listen((state) {
        if (state is SubscriptionActiveState) {
          if (!completer.isCompleted) completer.complete(true);
        }
      });

      await _iapService.buyConsumable(_subscriptionProductId);

      final ok = await completer.future.timeout(
        const Duration(minutes: 2),
        onTimeout: () => false,
      );

      if (!mounted) return ok;
      if (ok) {
        StorageUtils.saveSubscriptionStatus('ACTIVE');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(strings.language == AppLanguage.zh ? '购买成功' : 'Purchase successful')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(strings.language == AppLanguage.zh ? '未完成购买，已取消同步' : 'Purchase not completed. Sync canceled.')),
        );
      }

      return ok;
    } finally {
      _purchasing = false;
      await buySub?.cancel();
      await subStateSub?.cancel();
    }
  }

  Future<void> _showControlsSheet() async {
    if (!mounted) return;
    final nowYear = DateTime.now().year;
    final years = <int>[
      for (var y = nowYear; y >= _minYear; y -= 1) y,
    ];

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        final strings = AppI18n.s(context);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.75),
              child: StatefulBuilder(
                builder: (context, setModalState) {
                Widget sourceTile(HeatmapSource source) {
                  final selected = _source == source;
                  final bg = selected ? scheme.secondaryContainer : scheme.surfaceContainerHighest;
                  final fg = selected ? scheme.onSecondaryContainer : scheme.onSurface;
                  return Material(
                    color: bg,
                    child: InkWell(
                      onTap: _loading
                          ? null
                          : () async {
                              await _setSource(source);
                              setModalState(() {});
                            },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        child: Row(
                          children: [
                            Icon(_sourceIcon(source), color: fg),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _sourceLabel(source),
                                    style: Theme.of(context).textTheme.titleMedium?.copyWith(color: fg),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _sourceSubtitle(strings, source),
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: fg.withValues(alpha: 0.8)),
                                  ),
                                ],
                              ),
                            ),
                            if (selected) Icon(Icons.check_circle, color: fg),
                          ],
                        ),
                      ),
                    ),
                  );
                }

                final sourceLabel = _sourceLabel(_source);
                return SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(strings.heatmapSettingsTitle, style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 12),
                      Text(strings.dataSource, style: Theme.of(context).textTheme.labelLarge),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Column(
                          children: [
                            sourceTile(HeatmapSource.strava),
                            Divider(height: 1, color: scheme.outlineVariant),
                            sourceTile(HeatmapSource.igpsport),
                            Divider(height: 1, color: scheme.outlineVariant),
                            sourceTile(HeatmapSource.onelap),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(strings.year, style: Theme.of(context).textTheme.labelLarge),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<int>(
                        key: ValueKey(_year),
                        initialValue: _year,
                        menuMaxHeight: MediaQuery.sizeOf(context).height * 0.45,
                        items: [
                          for (final y in years) DropdownMenuItem<int>(value: y, child: Text('$y')),
                        ],
                        onChanged: _loading
                            ? null
                            : (value) {
                                if (value == null) return;
                                setState(() {
                                  _year = value;
                                  _routes = const [];
                                  _loadError = null;
                                });
                                setModalState(() {});
                              },
                        decoration: const InputDecoration(),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _routes.isEmpty ? strings.routesEmpty : strings.routesCount(_routes.length),
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: _loading
                                ? null
                                : () {
                                    Navigator.of(context).pop();
                                    Future<void>.delayed(const Duration(milliseconds: 1), _loadFromSource);
                                  },
                            icon: const Icon(Icons.refresh),
                            label: Text(strings.fetchFrom(sourceLabel)),
                          ),
                        ],
                      ),
                      if (_loading) ...[
                        const SizedBox(height: 12),
                        const LinearProgressIndicator(),
                      ],
                      if (_loadError != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _loadError!,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.error),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      );
      },
    );
  }

  Future<void> _loadFromStrava() async {
    if (_loading) return;
    if (!await widget.services.stravaClient.isConfigured()) {
      if (!mounted) return;
      final strings = AppI18n.s(context);
      setState(() {
        _loadError = strings.errNeedBindStrava;
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
      final strings = AppI18n.s(context);
      setState(() {
        _loadError = strings.errorText(e);
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
          routes.add(_convertRoutePoints(pts));
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
      final strings = AppI18n.s(context);
      setState(() {
        _loadError = strings.errNeedConfigIgpsport;
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
          routes.add(_convertRoutePoints(pts));
        }
      }

      if (!mounted) return;
      setState(() => _routes = routes);
      _centerToRoutes();
    } catch (e) {
      if (!mounted) return;
      final strings = AppI18n.s(context);
      setState(() {
        _loadError = strings.errorText(e);
        _routes = const [];
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadFromOnelap() async {
    if (_loading) return;
    final source = widget.services.sourceRegistry.byName('onelap');
    if (!await source.isConfigured()) {
      if (!mounted) return;
      final strings = AppI18n.s(context);
      setState(() {
        _loadError = strings.errNeedConfigOnelap;
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
      final activities = await source.listActivities(since: after, until: before, limit: 200);

      final outputDir = await getTemporaryDirectory();
      const concurrency = 3;
      final routes = <List<List<double>>>[];
      var i = 0;

      Future<void> worker() async {
        while (true) {
          final current = i;
          i += 1;
          if (current >= activities.length) return;
          final activity = activities[current];

          try {
            final file = await source.downloadFit(activity: activity, outputDir: outputDir);
            final lower = file.path.toLowerCase();
            final pts = lower.endsWith('.gpx') ? await _parseGpxRoute(file) : await _parseFitRoute(file);
            if (pts.length >= 2) {
              routes.add(_convertRoutePoints(pts));
            }
          } catch (_) {}
        }
      }

      await Future.wait(List.generate(concurrency, (_) => worker()));

      if (!mounted) return;
      setState(() => _routes = routes);
      _centerToRoutes();
    } catch (e) {
      if (!mounted) return;
      final strings = AppI18n.s(context);
      setState(() {
        _loadError = strings.errorText(e);
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

  Set<Polyline> _buildPolylines(AppLanguageController controller) {
    if (_routes.isEmpty) return const {};
    final color = Color(controller.language == AppLanguage.zh ? 0xFFFF5A00 : 0xFFFF00FF).withValues(alpha: 0.3);
    final salt = controller.language == AppLanguage.zh ? 'zh' : 'en';
    final polylines = <Polyline>{};
    for (var i = 0; i < _routes.length; i += 1) {
      final pts = _routes[i];
      if (pts.length < 2) continue;
      final polyline = Polyline(
        width: 5,
        color: color,
        points: pts.map((p) => LatLng(p[0], p[1])).toList(),
      );
      polyline.setIdForCopy('route_${salt}_$i');
      polylines.add(polyline);
    }
    return polylines;
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppI18n.s(context);
    final scheme = Theme.of(context).colorScheme;
    final sourceLabel = _sourceLabel(_source);
    final showMap = _loadError == null || _routes.isNotEmpty || _loading;
    return Scaffold(
      appBar: AppBar(
        title: Text(strings.heatmapTitle),
        actions: [
          IconButton(
            onPressed: _showControlsSheet,
            icon: const Icon(Icons.tune),
            tooltip: strings.tooltipHeatmapSettings,
          ),
          IconButton(
            onPressed: !showMap || _exporting ? null : _exportHeatmap,
            icon: _exporting
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.download_outlined),
            tooltip: strings.tooltipSaveToAlbum,
          ),
          IconButton(
            onPressed: _loading ? null : _loadFromSource,
            icon: const Icon(Icons.refresh),
            tooltip: strings.tooltipFetchFrom(sourceLabel),
          ),
          IconButton(
            onPressed: !showMap || _routes.isEmpty ? null : _centerToRoutes,
            icon: const Icon(Icons.my_location),
            tooltip: strings.tooltipCenterToRoutes,
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
      body: !showMap
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.map_outlined, size: 44, color: scheme.onSurfaceVariant),
                      const SizedBox(height: 12),
                      Text(
                        _loadError ?? strings.heatmapNeedAccountHint,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      const SizedBox(height: 12),
                      FilledButton.tonalIcon(
                        onPressed: _showControlsSheet,
                        icon: const Icon(Icons.tune),
                        label: Text(strings.tooltipHeatmapSettings),
                      ),
                    ],
                  ),
                ),
              ),
            )
          : Stack(
              children: [
                RepaintBoundary(
                  key: _exportKey,
                  child: Stack(
                    children: [
                      Builder(
                        builder: (context) {
                          AMapInitializer.updatePrivacyAgree(_amapPrivacy);
                          AMapInitializer.init(context, apiKey: _amapKeys);
                          final controller = AppI18n.controllerOf(context);
                          return AMapWidget(
                            key: _mapKey,
                            initialCameraPosition: const CameraPosition(
                              target: LatLng(30, 120),
                              zoom: 11,
                            ),
                            mapType: MapType.night,
                            mapLanguage: controller.language == AppLanguage.zh ? MapLanguage.chinese : MapLanguage.english,
                            myLocationStyleOptions: _myLocationStyle,
                            onLocationChanged: (loc) {
                              if (!isLocationValid(loc)) return;
                              _lastUserLocation = loc.latLng;
                              _centerToUserLocationIfPossible();
                            },
                            onMapCreated: (c) {
                              _amapController = c;
                              _mapReady = true;
                              _centerToUserLocationIfPossible();
                              if (_lastUserLocation == null && _routes.isNotEmpty) _centerToRoutes();
                            },
                            polylines: _buildPolylines(controller),
                          );
                        },
                      ),
                      if (!_exporting)
                        Positioned(
                          left: 12,
                          top: 12,
                          child: SafeArea(
                            bottom: false,
                            child: Material(
                              color: scheme.surfaceContainerHighest,
                              elevation: 1,
                              shape: const StadiumBorder(),
                              child: InkWell(
                                customBorder: const StadiumBorder(),
                                onTap: _showControlsSheet,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.tune, size: 18),
                                      const SizedBox(width: 8),
                                      Text(
                                        '$sourceLabel · $_year',
                                        style: Theme.of(context).textTheme.labelLarge,
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: scheme.primaryContainer,
                                          borderRadius: BorderRadius.circular(999),
                                        ),
                                        child: Text(
                                          _routes.isEmpty ? '0' : '${_routes.length}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelMedium
                                              ?.copyWith(color: scheme.onPrimaryContainer),
                                        ),
                                      ),
                                      if (_loading) ...[
                                        const SizedBox(width: 10),
                                        const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
