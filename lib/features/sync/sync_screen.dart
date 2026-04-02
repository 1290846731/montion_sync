import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import '../../services/app_services.dart';
import '../../storage/kv_store.dart';
import '../../storage/sync_db.dart';

class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key, required this.services});

  final AppServices services;

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  String? _sourceName;
  bool _syncing = false;
  int _latestLimit = 1;
  List<SyncRecord> _latest = const [];

  String _currentTarget() {
    final target = (widget.services.kvStore.getString(Keys.syncTarget) ?? 'strava').toLowerCase();
    return target == 'intervals' ? 'intervals' : 'strava';
  }

  String _successTip(String target) {
    return target == 'intervals' ? '同步ICU成功' : '同步到Strava成功';
  }

  @override
  void initState() {
    super.initState();
    final sources = widget.services.sourceRegistry.all;
    _sourceName = sources.isNotEmpty ? sources.first.name : null;
    _refreshLatest();
  }

  Future<void> _refreshLatest() async {
    final rows = await widget.services.syncDb.latest(limit: 50);
    if (!mounted) return;
    setState(() => _latest = rows);
  }

  Future<void> _syncNow() async {
    final sourceName = _sourceName;
    if (sourceName == null) return;
    setState(() => _syncing = true);
    try {
      final target = _currentTarget();
      final results = await widget.services.syncService.syncNow(sourceName: sourceName);
      await _refreshLatest();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${_successTip(target)}：${results.length} 条')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('批量同步失败：$e')),
      );
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _syncLatestN() async {
    final sourceName = _sourceName;
    if (sourceName == null) return;
    setState(() => _syncing = true);
    try {
      final target = _currentTarget();
      final results = await widget.services.syncService.syncNow(
        sourceName: sourceName,
        limit: _latestLimit,
        ignoreSince: true,
      );
      await _refreshLatest();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${_successTip(target)}：${results.length} 条')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('拉取同步失败：$e')),
      );
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _reSyncRecord(SyncRecord record) async {
    setState(() => _syncing = true);
    try {
      final newRecord = await widget.services.syncService.reSyncRecord(record);
      await _refreshLatest();
      if (!mounted) return;
      if (newRecord.status == 'success') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_successTip(newRecord.target))),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('重新同步完成：${newRecord.status}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('重新同步失败：$e')),
      );
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _importAndUpload(String label) async {
    setState(() => _syncing = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        type: FileType.custom,
        allowedExtensions: const ['fit', 'gpx', 'tcx'],
      );
      final path = result?.files.single.path;
      if (path == null || path.isEmpty) {
        throw StateError('未选择文件（或系统未返回路径）');
      }
      final record = await widget.services.syncService.uploadLocalFile(
        file: File(path),
        sourceLabel: label,
      );
      await _refreshLatest();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            record.status == 'success' ? _successTip(record.target) : '上传完成：${record.status}',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('上传失败：$e')),
      );
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sources = widget.services.sourceRegistry.all;
    final target = (widget.services.kvStore.getString(Keys.syncTarget) ?? 'strava').toLowerCase();
    final title = target == 'intervals' ? '同步到 Intervals.icu' : '同步到 Strava';
    final manualLabel = target == 'intervals' ? '选择本地 .fit/.gpx 同步到 Intervals.icu' : '选择本地 .fit/.gpx 同步到 Strava';
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (_syncing)
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
      body: RefreshIndicator(
        onRefresh: _refreshLatest,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              color: scheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('快速操作', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _sourceName,
                      items: [
                        for (final s in sources) DropdownMenuItem(value: s.name, child: Text(s.displayName)),
                      ],
                      onChanged: _syncing ? null : (value) => setState(() => _sourceName = value),
                      decoration: const InputDecoration(labelText: '数据源'),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _syncing ? null : _syncNow,
                      icon: const Icon(Icons.sync),
                      label: const Text('批量开始同步'),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Text('拉取最新', style: Theme.of(context).textTheme.labelLarge),
                        const SizedBox(width: 8),
                        DropdownButton<int>(
                          value: _latestLimit,
                          items: List.generate(10, (i) => i + 1)
                              .map((n) => DropdownMenuItem(value: n, child: Text('$n')))
                              .toList(),
                          onChanged: _syncing
                              ? null
                              : (val) {
                                  if (val != null) setState(() => _latestLimit = val);
                                },
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.tonalIcon(
                            onPressed: _syncing ? null : _syncLatestN,
                            icon: const Icon(Icons.download),
                            label: const Text('同步'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('手动导入文件'),
                      subtitle: Text(manualLabel),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _syncing ? null : () => _importAndUpload('local_fit'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: Text('最近记录', style: Theme.of(context).textTheme.titleMedium)),
                IconButton(
                  tooltip: '刷新',
                  onPressed: _syncing ? null : _refreshLatest,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            if (_latest.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('暂无记录', style: Theme.of(context).textTheme.bodyMedium),
              )
            else
              ..._latest.map((record) {
                final activityTime = record.activity?.startTime ?? record.activityTime;
                final timeStr = activityTime != null
                    ? '${activityTime.year}-${activityTime.month.toString().padLeft(2, '0')}-${activityTime.day.toString().padLeft(2, '0')} ${activityTime.hour.toString().padLeft(2, '0')}:${activityTime.minute.toString().padLeft(2, '0')}'
                    : '未知时间';
                final nameStr = record.activity?.name ?? record.activityName ?? '未知运动';
                final sourceStr = record.source;

                final canResync = !record.source.startsWith('manual.');
                final statusText = record.status == 'success'
                    ? '成功'
                    : record.status == 'duplicate'
                        ? '重复'
                        : '失败';
                final statusColor = record.status == 'success'
                    ? scheme.primary
                    : record.status == 'duplicate'
                        ? scheme.tertiary
                        : scheme.error;

                return Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Card(
                    child: ListTile(
                      title: Text(
                        '$sourceStr · $nameStr',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        '$timeStr${record.stravaActivityId == null ? '' : '\nStrava: ${record.stravaActivityId}'}',
                      ),
                      isThreeLine: record.stravaActivityId != null,
                      leading: CircleAvatar(
                        backgroundColor: statusColor.withValues(alpha: 0.15),
                        foregroundColor: statusColor,
                        child: Text(statusText),
                      ),
                      trailing: canResync
                          ? IconButton(
                              icon: const Icon(Icons.sync),
                              tooltip: '再次同步',
                              onPressed: _syncing ? null : () => _reSyncRecord(record),
                            )
                          : null,
                      onTap: record.message == null
                          ? null
                          : () {
                              showDialog<void>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text('详情'),
                                  content: Text(record.message!),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭')),
                                  ],
                                ),
                              );
                            },
                    ),
                  ),
                );
              }),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
