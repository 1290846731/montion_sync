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

  bool _loading = true;
  bool _stravaConfigured = false;

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

    final stravaConfigured = await widget.services.stravaClient.isConfigured();

    if (!mounted) return;
    setState(() {
      _loading = false;
      _stravaConfigured = stravaConfigured;
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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('账号配置', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        ExpansionTile(
          title: Text(_stravaConfigured ? 'Strava (已授权)' : 'Strava (未授权)'),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Text(_stravaConfigured ? '已完成授权，如需重新授权请点击下方按钮。' : '尚未授权，点击下方按钮直接授权。'),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: _connectStrava,
              child: Text(_stravaConfigured ? '重新授权' : '去授权'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ExpansionTile(
          title: const Text('IGPSPORT 迹驰'),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            TextField(
              controller: _igpsportUsername,
              decoration: const InputDecoration(labelText: '用户名'),
            ),
            TextField(
              controller: _igpsportPassword,
              decoration: const InputDecoration(labelText: '密码'),
              obscureText: true,
            ),
            TextField(
              controller: _igpsportAccessToken,
              decoration: const InputDecoration(labelText: 'Access Token（可选）'),
            ),
            const SizedBox(height: 12),
            FilledButton(onPressed: _saveIgpsport, child: const Text('保存')),
          ],
        ),
        const SizedBox(height: 8),
        ExpansionTile(
          title: const Text('顽鹿 OneLap'),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            TextField(
              controller: _onelapCookie,
              decoration: const InputDecoration(labelText: 'Cookie（推荐）'),
              minLines: 2,
              maxLines: 4,
            ),
            const SizedBox(height: 8),
            const Divider(),
            TextField(
              controller: _onelapUsername,
              decoration: const InputDecoration(labelText: '用户名（可选）'),
            ),
            TextField(
              controller: _onelapPassword,
              decoration: const InputDecoration(labelText: '密码（可选）'),
              obscureText: true,
            ),
            const SizedBox(height: 12),
            FilledButton(onPressed: _saveOneLap, child: const Text('保存')),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          '说明：账号信息保存在本机，重新进入应用无需重复输入。',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

