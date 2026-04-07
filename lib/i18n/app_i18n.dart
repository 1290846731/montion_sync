import 'package:flutter/widgets.dart';

import '../storage/kv_store.dart';

enum AppLanguage { zh, en }

class AppLanguageController extends ChangeNotifier {
  AppLanguageController({required KvStore kvStore})
      : _kvStore = kvStore,
        _language = _read(kvStore);

  final KvStore _kvStore;
  AppLanguage _language;

  AppLanguage get language => _language;

  Locale get locale => _language == AppLanguage.en ? const Locale('en') : const Locale('zh');

  AppStrings get strings => AppStrings(_language);

  Future<void> setLanguage(AppLanguage lang) async {
    if (lang == _language) return;
    _language = lang;
    notifyListeners();
    await _kvStore.setString(Keys.appLanguage, _language == AppLanguage.en ? 'en' : 'zh');
  }

  static AppLanguage _read(KvStore kvStore) {
    final raw = (kvStore.getString(Keys.appLanguage) ?? 'zh').toLowerCase();
    return raw.startsWith('en') ? AppLanguage.en : AppLanguage.zh;
  }
}

class AppI18n extends InheritedNotifier<AppLanguageController> {
  const AppI18n({super.key, required super.notifier, required super.child});

  static AppLanguageController controllerOf(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppI18n>();
    final notifier = scope?.notifier;
    if (notifier == null) {
      throw StateError('AppI18n not found in widget tree');
    }
    return notifier;
  }

  static AppStrings s(BuildContext context) => controllerOf(context).strings;
}

class AppStrings {
  const AppStrings(this.language);

  final AppLanguage language;

  bool get _zh => language == AppLanguage.zh;

  String get appTitle => _zh ? 'Strava 同步' : 'Strava Sync';

  String get navSync => _zh ? '同步' : 'Sync';
  String get navHeatmap => _zh ? '热力图' : 'Heatmap';
  String get navSettings => _zh ? '设置' : 'Settings';

  String get languageTitle => _zh ? '语言' : 'Language';
  String get languageZh => '中文';
  String get languageEn => 'English';

  String get save => _zh ? '保存' : 'Save';
  String get refresh => _zh ? '刷新' : 'Refresh';
  String get close => _zh ? '关闭' : 'Close';
  String get details => _zh ? '详情' : 'Details';

  String get heatmapTitle => _zh ? '热力图' : 'Heatmap';
  String get heatmapSettingsTitle => _zh ? '热力图设置' : 'Heatmap Settings';
  String get dataSource => _zh ? '数据来源' : 'Data Source';
  String get year => _zh ? '年份' : 'Year';
  String routesCount(int count) => _zh ? '轨迹：$count 条' : 'Routes: $count';
  String get routesEmpty => _zh ? '暂无轨迹' : 'No routes';
  String fetchFrom(String sourceLabel) => _zh ? '从 $sourceLabel 获取' : 'Fetch from $sourceLabel';
  String get tooltipSaveToAlbum => _zh ? '保存到相册' : 'Save to Photos';
  String tooltipFetchFrom(String sourceLabel) => _zh ? '从 $sourceLabel 获取' : 'Fetch from $sourceLabel';
  String get tooltipCenterToRoutes => _zh ? '定位到轨迹' : 'Center on route';
  String get saveFailedNotReady => _zh ? '保存失败：画面未就绪' : 'Save failed: view not ready';
  String get saveFailedImageGen => _zh ? '保存失败：生成图片失败' : 'Save failed: failed to render image';
  String get saveFailedNoAlbumPerm => _zh ? '保存失败：没有相册权限' : 'Save failed: no Photos permission';
  String get savedToAlbum => _zh ? '已保存到相册' : 'Saved to Photos';
  String saveFailed(String message) => _zh ? '保存失败：$message' : 'Save failed: $message';

  String get errNeedBindStrava => _zh ? '请先绑定 Strava' : 'Please connect Strava first';
  String get errNeedConfigIgpsport => _zh ? '请先配置 IGPSPORT 账号' : 'Please configure IGPSPORT first';
  String get errNeedConfigOnelap => _zh ? '请先配置 OneLap 账号' : 'Please configure OneLap first';

  String get settingsTitle => _zh ? '设置' : 'Settings';
  String get settingsAccountsAndSync => _zh ? '账号与同步' : 'Accounts & Sync';
  String get settingsThirdParty => _zh ? '第三方账号' : 'Third-party Accounts';
  String get syncSettingsTitle => _zh ? '同步设置' : 'Sync Settings';
  String get syncToStrava => _zh ? '同步到 Strava' : 'Sync to Strava';
  String get syncToIntervals => _zh ? '只同步到 Intervals.icu' : 'Sync only to Intervals.icu';

  String stravaTitle(bool configured) => _zh ? (configured ? 'Strava（已授权）' : 'Strava（未授权）') : (configured ? 'Strava (Connected)' : 'Strava (Not connected)');
  String stravaHint(bool configured) => _zh
      ? (configured ? '已完成授权，如需重新授权请点击下方按钮。' : '尚未授权，点击下方按钮开始授权。')
      : (configured ? 'Connected. Tap below to reconnect if needed.' : 'Not connected. Tap below to connect.');
  String get stravaAuthActionReconnect => _zh ? '重新授权' : 'Reconnect';
  String get stravaAuthActionConnect => _zh ? '去授权' : 'Connect';
  String get stravaAuthDone => _zh ? 'Strava 授权完成' : 'Strava authorization completed';
  String get errNoAuthCode => _zh ? '未获取到 code' : 'Missing authorization code';

  String get intervalsTitle => 'Intervals.icu';
  String get intervalsApiKey => 'API_KEY';
  String get intervalsSaved => _zh ? '已保存 Intervals.icu 配置' : 'Saved Intervals.icu settings';

  String get igpsportTitle => _zh ? 'IGPSPORT 迹驰' : 'IGPSPORT';
  String get oneLapTitle => _zh ? '顽鹿 OneLap' : 'OneLap';
  String get username => _zh ? '用户名' : 'Username';
  String get password => _zh ? '密码' : 'Password';
  String get usernameOptional => _zh ? '用户名（可选）' : 'Username (optional)';
  String get passwordOptional => _zh ? '密码（可选）' : 'Password (optional)';
  String get accessTokenOptional => _zh ? 'Access Token（可选）' : 'Access Token (optional)';
  String get cookieRecommended => _zh ? 'Cookie（推荐）' : 'Cookie (recommended)';

  String get igpsportSaved => _zh ? '已保存 IGPSPORT 配置' : 'Saved IGPSPORT settings';
  String get onelapSaved => _zh ? '已保存 OneLap 配置' : 'Saved OneLap settings';
  String get accountLocalOnlyHint => _zh ? '账号信息仅保存在本机；重新进入应用无需重复输入。' : 'Credentials are stored locally on this device only.';

  String get syncTitleToStrava => _zh ? '同步到 Strava' : 'Sync to Strava';
  String get syncTitleToIntervals => _zh ? '同步到 Intervals.icu' : 'Sync to Intervals.icu';
  String manualImportLabel(String target) => _zh
      ? (target == 'intervals' ? '选择本地 .fit/.gpx 同步到 Intervals.icu' : '选择本地 .fit/.gpx 同步到 Strava')
      : (target == 'intervals' ? 'Pick local .fit/.gpx and sync to Intervals.icu' : 'Pick local .fit/.gpx and sync to Strava');
  String get quickActions => _zh ? '快速操作' : 'Quick Actions';
  String get batchSyncStart => _zh ? '批量开始同步' : 'Start Batch Sync';
  String get pullLatest => _zh ? '拉取最新' : 'Fetch latest';
  String get sync => _zh ? '同步' : 'Sync';
  String get manualImport => _zh ? '手动导入文件' : 'Import File';
  String get recentRecords => _zh ? '最近记录' : 'Recent Records';
  String get noRecords => _zh ? '暂无记录' : 'No records';
  String get unknownTime => _zh ? '未知时间' : 'Unknown time';
  String get unknownSport => _zh ? '未知运动' : 'Unknown activity';
  String get statusSuccess => _zh ? '成功' : 'OK';
  String get statusDuplicate => _zh ? '重复' : 'Dup';
  String get statusFailed => _zh ? '失败' : 'Fail';
  String get tooltipResync => _zh ? '再次同步' : 'Resync';

  String syncSuccessTip(String target) => target == 'intervals' ? (_zh ? '同步ICU成功' : 'Synced to Intervals.icu') : (_zh ? '同步到Strava成功' : 'Synced to Strava');
  String syncSuccessCount(String target, int count) => '${syncSuccessTip(target)}: $count';

  String batchSyncFailed(String err) => _zh ? '批量同步失败：$err' : 'Batch sync failed: $err';
  String fetchSyncFailed(String err) => _zh ? '拉取同步失败：$err' : 'Fetch & sync failed: $err';
  String resyncDone(String status) => _zh ? '重新同步完成：$status' : 'Resync finished: $status';
  String resyncFailed(String err) => _zh ? '重新同步失败：$err' : 'Resync failed: $err';
  String uploadDone(String status) => _zh ? '上传完成：$status' : 'Upload finished: $status';
  String uploadFailed(String err) => _zh ? '上传失败：$err' : 'Upload failed: $err';
  String get errNoFileSelected => _zh ? '未选择文件（或系统未返回路径）' : 'No file selected (or no path returned)';

  String errorText(Object error) {
    final raw = error.toString();
    if (_zh) return raw;

    if (raw == '请先绑定strava' || raw == '请先绑定 Strava') return errNeedBindStrava;
    if (raw == 'Intervals.icu 未配置 API_KEY') return 'Intervals.icu API_KEY is not configured';
    if (raw == '手动导入的文件无法在此处直接重新同步') return 'Manually imported files cannot be re-synced here';
    if (raw == '在最近的数据中未找到该活动，无法重新同步') return 'Activity not found in recent list; cannot re-sync';
    if (raw == '本机记录已上传过该文件') return 'This file has already been uploaded from this device';

    final m = RegExp(r'^(.*) 未配置账号$').firstMatch(raw);
    if (m != null) {
      final name = m.group(1) ?? '';
      if (name.isNotEmpty) return '$name is not configured';
      return 'Account is not configured';
    }

    if (raw.startsWith('不支持的文件类型：')) {
      final tail = raw.substring('不支持的文件类型：'.length);
      return 'Unsupported file type: $tail';
    }

    if (raw == 'Strava token 返回为空') return 'Strava token response is empty';
    if (raw == '没有可用的 Refresh Token') return 'No refresh token available';
    if (raw == 'Strava refresh 返回为空') return 'Strava refresh response is empty';
    if (raw == 'Strava 未返回 access_token') return 'Strava did not return access_token';

    return raw;
  }
}
