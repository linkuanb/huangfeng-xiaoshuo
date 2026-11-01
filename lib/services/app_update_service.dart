import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// App 内自动更新：从仓库滚动 Release（tag 恒为 `latest`）拉取
/// `version.json`，比当前版本新时下载对应 ABI 的 APK 并调起系统安装器。
/// 两个包由同一把 release 证书签发，覆盖安装才成立；Android 不允许静默
/// 安装，最后一步一定由用户在系统界面确认。服务端发布流程见
/// .github/workflows/android-apk.yml 的 publish 作业。
class AppUpdateInfo {
  const AppUpdateInfo({
    required this.version,
    required this.versionCode,
    required this.commit,
    required this.assets,
  });

  final String version;
  final int versionCode;
  final String commit;

  /// ABI -> APK 文件名，例如 arm64-v8a -> huangfeng-arm64-v8a.apk。
  final Map<String, String> assets;

  static AppUpdateInfo? tryParse(String body) {
    try {
      final json = jsonDecode(body);
      if (json is! Map<String, dynamic>) return null;
      final version = json['version'];
      final versionCode = json['versionCode'];
      final commit = json['commit'];
      final assets = json['assets'];
      if (version is! String || version.isEmpty) return null;
      if (versionCode is! int) return null;
      if (commit is! String) return null;
      if (assets is! Map<String, dynamic>) return null;
      return AppUpdateInfo(
        version: version,
        versionCode: versionCode,
        commit: commit,
        assets: assets.map((key, value) => MapEntry(key, '$value')),
      );
    } catch (_) {
      return null;
    }
  }
}

class AppUpdateService {
  AppUpdateService({http.Client? client}) : _client = client ?? http.Client();

  /// 与 pubspec.yaml 的 `+build` 同步（没有 package_info 依赖，版本号是
  /// 静态值）；test/app_update_service_test.dart 会在两者漂移时失败。
  static const currentVersionCode = 138;

  /// 滚动 Release 的固定下载地址。可用
  /// `--dart-define=FQAPP_UPDATE_URL=...` 覆盖以便联调。
  static const versionJsonUrl = String.fromEnvironment(
    'FQAPP_UPDATE_URL',
    defaultValue:
        'https://github.com/linkuanb/huangfeng-xiaoshuo/releases/latest/download/version.json',
  );

  static const _channel = MethodChannel('fqapp/app_update');

  final http.Client _client;

  static String get _downloadBase =>
      versionJsonUrl.replaceFirst(RegExp(r'version\.json$'), '');

  /// 启动时的静默检查：任何失败（断网、解析失败、已最新、当前 ABI 无包）
  /// 都返回 null，绝不打扰启动流程。
  Future<AppUpdateInfo?> check() async {
    try {
      return await fetchUpdate();
    } catch (_) {
      return null;
    }
  }

  /// 拉取 version.json。已是最新或当前 ABI 没有对应安装包时返回 null；
  /// 网络/解析异常上抛，由调用方决定怎么提示（手动检查需要区分
  /// 「已最新」与「检查失败」）。
  Future<AppUpdateInfo?> fetchUpdate() async {
    if (!Platform.isAndroid) return null;
    final response = await _client
        .get(Uri.parse(versionJsonUrl))
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw StateError('HTTP ${response.statusCode}');
    }
    final info = AppUpdateInfo.tryParse(utf8.decode(response.bodyBytes));
    if (info == null) throw const FormatException('无法解析版本信息');
    if (info.versionCode <= currentVersionCode) return null;
    return apkAssetName(info) == null ? null : info;
  }

  /// 当前进程 ABI 对应的 APK 文件名；不支持的 ABI（x86 模拟器等）为 null。
  static String? apkAssetName(AppUpdateInfo info) {
    final key = switch (ffi.Abi.current()) {
      ffi.Abi.androidArm64 => 'arm64-v8a',
      ffi.Abi.androidArm => 'armeabi-v7a',
      _ => null,
    };
    return key == null ? null : info.assets[key];
  }

  static String apkUrl(AppUpdateInfo info) =>
      '$_downloadBase${apkAssetName(info)}';

  /// 流式下载 APK 到应用缓存目录并汇报进度（总长未知时回调 null）。
  Future<File> download(
    AppUpdateInfo info, {
    void Function(double? progress)? onProgress,
  }) async {
    final request = http.Request('GET', Uri.parse(apkUrl(info)));
    final response = await _client
        .send(request)
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw StateError('下载失败（HTTP ${response.statusCode}）');
    }
    final file = File(
      '${(await getTemporaryDirectory()).path}/update_apks/${apkAssetName(info)}',
    );
    await file.parent.create(recursive: true);
    final sink = file.openWrite();
    final total = response.contentLength;
    var received = 0;
    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(
          total == null || total <= 0 ? null : received / total,
        );
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
    return file;
  }

  /// 经原生通道用 FileProvider 把 APK 授权给系统安装器并调起安装界面。
  Future<bool> install(File apk) async {
    if (!Platform.isAndroid) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('installApk', {
        'path': apk.path,
      });
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }
}
