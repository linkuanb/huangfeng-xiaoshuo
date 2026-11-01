import 'dart:async';

import 'package:flutter/material.dart';

import '../services/app_update_service.dart';

/// 发现新版本时的更新对话框：提示 → 下载（进度条）→ 调起系统安装器。
/// 只在 check/fetchUpdate 返回非空时由调用方弹出（即仅 Android 且有新版）。
Future<void> showAppUpdateDialog(BuildContext context, AppUpdateInfo info) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AppUpdateDialog(info: info),
  );
}

class AppUpdateDialog extends StatefulWidget {
  const AppUpdateDialog({super.key, required this.info});

  final AppUpdateInfo info;

  @override
  State<AppUpdateDialog> createState() => _AppUpdateDialogState();
}

class _AppUpdateDialogState extends State<AppUpdateDialog> {
  final _service = AppUpdateService();

  /// 0..1；null 表示未开始或服务器未给总长度。
  double? _progress;
  bool _downloading = false;
  bool _installing = false;
  String? _error;

  Future<void> _startDownload() async {
    setState(() {
      _downloading = true;
      _error = null;
      _progress = 0;
    });
    try {
      final apk = await _service.download(
        widget.info,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _installing = true;
      });
      final ok = await _service.install(apk);
      if (!mounted || ok) return;
      setState(() {
        _installing = false;
        _error = '无法调起系统安装器，请前往发布页手动更新';
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _downloading = false;
          _error = '下载失败，请检查网络后重试';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final interactive = !_downloading && !_installing;
    return AlertDialog(
      title: Text('发现新版本 ${widget.info.version}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            )
          else if (_installing)
            const Text('安装包已就绪，请在系统界面确认安装。')
          else if (_downloading) ...[
            const Text('正在下载安装包…'),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: _progress),
            if (_progress != null) ...[
              const SizedBox(height: 8),
              Text('${(_progress! * 100).toStringAsFixed(0)}%'),
            ],
          ] else
            const Text('有新版本可用，更新后获得最新内容与修复。'),
        ],
      ),
      actions: [
        if (interactive)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('以后再说'),
          ),
        if (interactive)
          FilledButton(
            onPressed: _startDownload,
            child: Text(_error == null ? '立即更新' : '重试'),
          ),
        if (_installing)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
      ],
    );
  }
}
