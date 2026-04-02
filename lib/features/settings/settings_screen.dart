import 'package:flutter/material.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';

import '../../services/app_services.dart';
import '../../storage/kv_store.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.services});

  final AppServices services;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _igpsportUsername = TextEditingController();
  final _igpsportPassword = TextEditingController();
  final _igpsportAccessToken = TextEditingController();

  final _onelapUsername = TextEditingController();
  final _onelapPassword = TextEditingController();
  final _onelapCookie = TextEditingController();

  final _intervalsApiKey = TextEditingController();

  bool _loading = true;
  bool _busy = false;
  bool _stravaConfigured = false;
  String _syncTarget = 'strava';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _igpsportUsername.dispose();
    _igpsportPassword.dispose();
    _igpsportAccessToken.dispose();
    _onelapUsername.dispose();
    _onelapPassword.dispose();
    _onelapCookie.dispose();
    _intervalsApiKey.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final kv = widget.services.kvStore;

    _igpsportUsername.text = (await kv.getSecureString(Keys.igpsportUsername)) ?? '';
    _igpsportPassword.text = (await kv.getSecureString(Keys.igpsportPassword)) ?? '';
    _igpsportAccessToken.text = (await kv.getSecureString(Keys.igpsportAccessToken)) ?? '';

    _onelapUsername.text = (await kv.getSecureString(Keys.onelapUsername)) ?? '';
    _onelapPassword.text = (await kv.getSecureString(Keys.onelapPassword)) ?? '';
    _onelapCookie.text = (await kv.getSecureString(Keys.onelapCookie)) ?? '';

    _intervalsApiKey.text = (await kv.getSecureString(Keys.intervalsApiKey)) ?? '';
    final syncTarget = (kv.getString(Keys.syncTarget) ?? 'strava').toLowerCase();

    final stravaConfigured = await widget.services.stravaClient.isConfigured();

    if (!mounted) return;
    setState(() {
      _loading = false;
      _stravaConfigured = stravaConfigured;
      _syncTarget = syncTarget == 'intervals' ? 'intervals' : 'strava';
    });
  }

  Future<void> _saveIgpsport() async {
    final kv = widget.services.kvStore;
    await kv.setSecureString(Keys.igpsportUsername, _igpsportUsername.text.trim());
    await kv.setSecureString(Keys.igpsportPassword, _igpsportPassword.text);
    await kv.setSecureString(Keys.igpsportAccessToken, _igpsportAccessToken.text.trim());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已保存 IGPSPORT 配置')));
  }

  Future<void> _saveOneLap() async {
    final kv = widget.services.kvStore;
    await kv.setSecureString(Keys.onelapUsername, _onelapUsername.text.trim());
    await kv.setSecureString(Keys.onelapPassword, _onelapPassword.text);
    await kv.setSecureString(Keys.onelapCookie, _onelapCookie.text.trim());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已保存 OneLap 配置')));
  }

  Future<void> _connectStrava() async {
    final url = await widget.services.stravaClient.buildAuthorizeUrl(forcePrompt: true);
    final result = await FlutterWebAuth2.authenticate(
      url: url,
      callbackUrlScheme: 'stravasync',
    );
    final code = Uri.parse(result).queryParameters['code'];
    if (code == null || code.isEmpty) {
      throw StateError('未获取到 code');
    }
    await widget.services.stravaClient.exchangeCode(code);
    final stravaConfigured = await widget.services.stravaClient.isConfigured();
    
    if (!mounted) return;
    setState(() {
      _stravaConfigured = stravaConfigured;
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Strava 授权完成')));
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveIntervals() async {
    final kv = widget.services.kvStore;
    await kv.setSecureString(Keys.intervalsApiKey, _intervalsApiKey.text.trim());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已保存 Intervals.icu 配置')));
  }

  Future<void> _saveSyncTarget(String value) async {
    final v = value == 'intervals' ? 'intervals' : 'strava';
    await widget.services.kvStore.setString(Keys.syncTarget, v);
    if (!mounted) return;
    setState(() => _syncTarget = v);
  }

  void _onSyncTargetChanged(String? value) {
    if (value == null) return;
    _saveSyncTarget(value);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        actions: [
          if (_busy)
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
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('账号与同步', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                Card(
                  color: scheme.surfaceContainerHighest,
                  child: ExpansionTile(
                    leading: const Icon(Icons.tune),
                    title: const Text('同步设置'),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    children: [
                      RadioGroup<String>(
                        groupValue: _syncTarget,
                        onChanged: (value) {
                          if (_busy) return;
                          _onSyncTargetChanged(value);
                        },
                        child: const Column(
                          children: [
                            RadioListTile<String>(
                              value: 'strava',
                              title: Text('同步到 Strava'),
                            ),
                            RadioListTile<String>(
                              value: 'intervals',
                              title: Text('只同步到 Intervals.icu'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  color: scheme.surfaceContainerHighest,
                  child: ExpansionTile(
                    leading: const Icon(Icons.directions_run),
                    title: Text(_stravaConfigured ? 'Strava（已授权）' : 'Strava（未授权）'),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    children: [
                      Text(_stravaConfigured ? '已完成授权，如需重新授权请点击下方按钮。' : '尚未授权，点击下方按钮开始授权。'),
                      const SizedBox(height: 12),
                      FilledButton.tonal(
                        onPressed: _busy ? null : () => _run(_connectStrava),
                        child: Text(_stravaConfigured ? '重新授权' : '去授权'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  color: scheme.surfaceContainerHighest,
                  child: ExpansionTile(
                    leading: const Icon(Icons.insights),
                    title: const Text('Intervals.icu'),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    children: [
                      TextField(
                        controller: _intervalsApiKey,
                        decoration: const InputDecoration(labelText: 'API_KEY'),
                        obscureText: true,
                        enabled: !_busy,
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: _busy ? null : () => _run(_saveIntervals),
                        child: const Text('保存'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text('第三方账号', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                Card(
                  color: scheme.surfaceContainerHighest,
                  child: ExpansionTile(
                    leading: const Icon(Icons.directions_bike),
                    title: const Text('IGPSPORT 迹驰'),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    children: [
                      TextField(
                        controller: _igpsportUsername,
                        decoration: const InputDecoration(labelText: '用户名'),
                        enabled: !_busy,
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _igpsportPassword,
                        decoration: const InputDecoration(labelText: '密码'),
                        obscureText: true,
                        enabled: !_busy,
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _igpsportAccessToken,
                        decoration: const InputDecoration(labelText: 'Access Token（可选）'),
                        enabled: !_busy,
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: _busy ? null : () => _run(_saveIgpsport),
                        child: const Text('保存'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  color: scheme.surfaceContainerHighest,
                  child: ExpansionTile(
                    leading: const Icon(Icons.sports_motorsports),
                    title: const Text('顽鹿 OneLap'),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    children: [
                      TextField(
                        controller: _onelapCookie,
                        decoration: const InputDecoration(labelText: 'Cookie（推荐）'),
                        minLines: 2,
                        maxLines: 4,
                        enabled: !_busy,
                      ),
                      const SizedBox(height: 8),
                      Divider(color: scheme.outlineVariant),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _onelapUsername,
                        decoration: const InputDecoration(labelText: '用户名（可选）'),
                        enabled: !_busy,
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _onelapPassword,
                        decoration: const InputDecoration(labelText: '密码（可选）'),
                        obscureText: true,
                        enabled: !_busy,
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: _busy ? null : () => _run(_saveOneLap),
                        child: const Text('保存'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '账号信息仅保存在本机；重新进入应用无需重复输入。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }
}
