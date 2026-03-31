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

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
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
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _syncing ? null : _syncNow,
                      icon: _syncing
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.sync),
                      label: Text(_syncing ? '同步中…' : '批量开始同步'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('拉取最新'),
                  const SizedBox(width: 8),
                  DropdownButton<int>(
                    value: _latestLimit,
                    items: List.generate(10, (i) => i + 1)
                        .map((n) => DropdownMenuItem(value: n, child: Text('$n 条')))
                        .toList(),
                    onChanged: _syncing ? null : (val) {
                      if (val != null) setState(() => _latestLimit = val);
                    },
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: _syncing ? null : _syncLatestN,
                      icon: const Icon(Icons.download),
                      label: const Text('同步指定条数'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text('手动导入', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton.tonal(
                    onPressed: _syncing ? null : () => _importAndUpload('local_fit'),
                    child: Text(manualLabel),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refreshLatest,
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemBuilder: (context, index) {
                final record = _latest[index];
                
                final activityTime = record.activity?.startTime ?? record.activityTime;
                final timeStr = activityTime != null
                    ? '${activityTime.year}-${activityTime.month.toString().padLeft(2, '0')}-${activityTime.day.toString().padLeft(2, '0')} ${activityTime.hour.toString().padLeft(2, '0')}:${activityTime.minute.toString().padLeft(2, '0')}'
                    : '未知时间';
                final nameStr = record.activity?.name ?? record.activityName ?? '未知运动';
                final sourceStr = record.source;

                final title = '$sourceStr - $nameStr';
                final subtitle = '$timeStr\n状态: ${record.status}${record.stravaActivityId == null ? '' : ' → ${record.stravaActivityId}'}';

                final statusIcon = switch (record.status) {
                  'success' => const Icon(Icons.check_circle, color: Colors.green, size: 20),
                  'duplicate' => const Icon(Icons.copy, color: Colors.orange, size: 20),
                  _ => const Icon(Icons.error, color: Colors.red, size: 20),
                };

                final canResync = !record.source.startsWith('manual.');

                return ListTile(
                  title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(subtitle),
                  isThreeLine: true,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      statusIcon,
                      if (canResync) ...[
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.sync),
                          tooltip: '再次同步',
                          onPressed: _syncing ? null : () => _reSyncRecord(record),
                        ),
                      ],
                    ],
                  ),
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
                );
              },
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemCount: _latest.length,
            ),
          ),
        ),
      ],
    );
  }
}
