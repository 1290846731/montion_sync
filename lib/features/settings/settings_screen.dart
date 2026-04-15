import 'package:flutter/material.dart';

import '../../i18n/app_i18n.dart';
import '../../services/app_services.dart';
import '../../storage/kv_store.dart';
import 'strava_auth_screen.dart';

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
  final _stravaClientId = TextEditingController();
  final _stravaClientSecret = TextEditingController();

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
    _stravaClientId.dispose();
    _stravaClientSecret.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final kv = widget.services.kvStore;

    _igpsportUsername.text =
        (await kv.getSecureString(Keys.igpsportUsername)) ?? '';
    _igpsportPassword.text =
        (await kv.getSecureString(Keys.igpsportPassword)) ?? '';
    _igpsportAccessToken.text =
        (await kv.getSecureString(Keys.igpsportAccessToken)) ?? '';

    _onelapUsername.text =
        (await kv.getSecureString(Keys.onelapUsername)) ?? '';
    _onelapPassword.text =
        (await kv.getSecureString(Keys.onelapPassword)) ?? '';
    _onelapCookie.text = (await kv.getSecureString(Keys.onelapCookie)) ?? '';

    _intervalsApiKey.text =
        (await kv.getSecureString(Keys.intervalsApiKey)) ?? '';

    _stravaClientId.text =
        (await kv.getSecureString(Keys.stravaClientId)) ?? '';
    _stravaClientSecret.text =
        (await kv.getSecureString(Keys.stravaClientSecret)) ?? '';
    final syncTarget = (kv.getString(Keys.syncTarget) ?? 'strava')
        .toLowerCase();

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
    await kv.setSecureString(
      Keys.igpsportUsername,
      _igpsportUsername.text.trim(),
    );
    await kv.setSecureString(Keys.igpsportPassword, _igpsportPassword.text);
    await kv.setSecureString(
      Keys.igpsportAccessToken,
      _igpsportAccessToken.text.trim(),
    );
    if (!mounted) return;
    final s = AppI18n.s(context);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(s.igpsportSaved)));
  }

  Future<void> _saveOneLap() async {
    final kv = widget.services.kvStore;
    await kv.setSecureString(Keys.onelapUsername, _onelapUsername.text.trim());
    await kv.setSecureString(Keys.onelapPassword, _onelapPassword.text);
    await kv.setSecureString(Keys.onelapCookie, _onelapCookie.text.trim());
    if (!mounted) return;
    final s = AppI18n.s(context);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(s.onelapSaved)));
  }

  Future<void> _disconnectStrava() async {
    final kv = widget.services.kvStore;
    await kv.setSecureString(Keys.stravaAccessToken, '');
    await kv.setSecureString(Keys.stravaRefreshToken, '');
    await kv.setSecureString(Keys.stravaExpiresAt, '');
    final stravaConfigured = await widget.services.stravaClient.isConfigured();
    if (!mounted) return;
    setState(() {
      _stravaConfigured = stravaConfigured;
    });
  }

  Future<void> _saveStravaClient() async {
    final kv = widget.services.kvStore;
    await kv.setSecureString(Keys.stravaClientId, _stravaClientId.text.trim());
    await kv.setSecureString(
      Keys.stravaClientSecret,
      _stravaClientSecret.text.trim(),
    );
    final stravaConfigured = await widget.services.stravaClient.isConfigured();
    if (!mounted) return;
    setState(() => _stravaConfigured = stravaConfigured);
    final s = AppI18n.s(context);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(s.stravaClientSaved)));
  }

  Future<void> _connectStrava() async {
    final url = await widget.services.stravaClient.buildAuthorizeUrl(
      forcePrompt: true,
    );

    if (!mounted) return;
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (context) => StravaAuthScreen(authUrl: url)),
    );

    if (code == null || code.isEmpty) {
      if (!mounted) return;
      throw StateError(AppI18n.s(context).errNoAuthCode);
    }

    await widget.services.stravaClient.exchangeCode(code);
    final stravaConfigured = await widget.services.stravaClient.isConfigured();

    if (!mounted) return;
    setState(() {
      _stravaConfigured = stravaConfigured;
    });
    final s = AppI18n.s(context);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(s.stravaAuthDone)));
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (!mounted) return;
      final s = AppI18n.s(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(s.errorText(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveIntervals() async {
    final kv = widget.services.kvStore;
    await kv.setSecureString(
      Keys.intervalsApiKey,
      _intervalsApiKey.text.trim(),
    );
    if (!mounted) return;
    final s = AppI18n.s(context);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(s.intervalsSaved)));
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
    final controller = AppI18n.controllerOf(context);
    final s = controller.strings;

    return Scaffold(
      appBar: AppBar(
        title: Text(s.settingsTitle),
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
                Text(
                  s.settingsAccountsAndSync,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                Card(
                  color: scheme.surfaceContainerHighest,
                  child: ListTile(
                    leading: const Icon(Icons.language),
                    title: Text(s.languageTitle),
                    trailing: DropdownButton<AppLanguage>(
                      value: controller.language,
                      items: [
                        DropdownMenuItem(
                          value: AppLanguage.zh,
                          child: Text(s.languageZh),
                        ),
                        DropdownMenuItem(
                          value: AppLanguage.en,
                          child: Text(s.languageEn),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        controller.setLanguage(value);
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  color: scheme.surfaceContainerHighest,
                  child: ExpansionTile(
                    leading: const Icon(Icons.tune),
                    title: Text(s.syncSettingsTitle),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    children: [
                      RadioGroup<String>(
                        groupValue: _syncTarget,
                        onChanged: (value) {
                          if (_busy) return;
                          _onSyncTargetChanged(value);
                        },
                        child: Column(
                          children: [
                            RadioListTile<String>(
                              value: 'strava',
                              title: Text(s.syncToStrava),
                            ),
                            RadioListTile<String>(
                              value: 'intervals',
                              title: Text(s.syncToIntervals),
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
                    title: Text(s.stravaTitle(_stravaConfigured)),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    children: [
                      Text(s.stravaHint(_stravaConfigured)),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _stravaClientId,
                        decoration: InputDecoration(labelText: s.stravaClientId),
                        enabled: !_busy,
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _stravaClientSecret,
                        decoration:
                            InputDecoration(labelText: s.stravaClientSecret),
                        obscureText: true,
                        enabled: !_busy,
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: _busy ? null : () => _run(_saveStravaClient),
                        child: Text(s.save),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          if (_stravaConfigured) ...[
                            FilledButton.tonal(
                              onPressed: _busy
                                  ? null
                                  : () => _run(_disconnectStrava),
                              child: const Text('解绑 (Disconnect)'),
                            ),
                            const SizedBox(width: 8),
                          ],
                          FilledButton.tonal(
                            onPressed: _busy
                                ? null
                                : () => _run(_connectStrava),
                            child: Text(
                              _stravaConfigured
                                  ? s.stravaAuthActionReconnect
                                  : s.stravaAuthActionConnect,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  color: scheme.surfaceContainerHighest,
                  child: ExpansionTile(
                    leading: const Icon(Icons.insights),
                    title: Text(s.intervalsTitle),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    children: [
                      TextField(
                        controller: _intervalsApiKey,
                        decoration: InputDecoration(
                          labelText: s.intervalsApiKey,
                        ),
                        obscureText: true,
                        enabled: !_busy,
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: _busy ? null : () => _run(_saveIntervals),
                        child: Text(s.save),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  s.settingsThirdParty,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                Card(
                  color: scheme.surfaceContainerHighest,
                  child: ExpansionTile(
                    leading: const Icon(Icons.directions_bike),
                    title: Text(s.igpsportTitle),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    children: [
                      TextField(
                        controller: _igpsportUsername,
                        decoration: InputDecoration(labelText: s.username),
                        enabled: !_busy,
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _igpsportPassword,
                        decoration: InputDecoration(labelText: s.password),
                        obscureText: true,
                        enabled: !_busy,
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _igpsportAccessToken,
                        decoration: InputDecoration(
                          labelText: s.accessTokenOptional,
                        ),
                        enabled: !_busy,
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: _busy ? null : () => _run(_saveIgpsport),
                        child: Text(s.save),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  color: scheme.surfaceContainerHighest,
                  child: ExpansionTile(
                    leading: const Icon(Icons.sports_motorsports),
                    title: Text(s.oneLapTitle),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    children: [
                      TextField(
                        controller: _onelapCookie,
                        decoration: InputDecoration(
                          labelText: s.cookieRecommended,
                        ),
                        minLines: 2,
                        maxLines: 4,
                        enabled: !_busy,
                      ),
                      const SizedBox(height: 8),
                      Divider(color: scheme.outlineVariant),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _onelapUsername,
                        decoration: InputDecoration(
                          labelText: s.usernameOptional,
                        ),
                        enabled: !_busy,
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _onelapPassword,
                        decoration: InputDecoration(
                          labelText: s.passwordOptional,
                        ),
                        obscureText: true,
                        enabled: !_busy,
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: _busy ? null : () => _run(_saveOneLap),
                        child: Text(s.save),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  s.accountLocalOnlyHint,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }
}
