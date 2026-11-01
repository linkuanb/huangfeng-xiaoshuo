import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fqapp/services/app_update_service.dart';

void main() {
  // AppUpdateService.currentVersionCode 是静态值（没有 package_info 依赖），
  // 与 AboutPage.versionText 一样必须和 pubspec 保持同步，否则自动更新
  // 会永远认为「已是最新」。
  test('currentVersionCode matches pubspec.yaml build number', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(
      r'^version:\s*\d+\.\d+\.\d+\+(\d+)\s*$',
      multiLine: true,
    ).firstMatch(pubspec);
    expect(match, isNotNull, reason: 'pubspec.yaml must declare a version');
    expect(AppUpdateService.currentVersionCode, int.parse(match!.group(1)!));
  });

  group('AppUpdateInfo.tryParse', () {
    test('parses the version.json shape the publish job writes', () {
      final info = AppUpdateInfo.tryParse(
        '{"version":"1.0.134","versionCode":139,'
        '"commit":"c986a7cfee12dfc5c4ee02bc39619980913f75d2",'
        '"assets":{"arm64-v8a":"huangfeng-arm64-v8a.apk",'
        '"armeabi-v7a":"huangfeng-armeabi-v7a.apk"}}',
      );
      expect(info, isNotNull);
      expect(info!.version, '1.0.134');
      expect(info.versionCode, 139);
      expect(info.assets['arm64-v8a'], 'huangfeng-arm64-v8a.apk');
      expect(info.assets['armeabi-v7a'], 'huangfeng-armeabi-v7a.apk');
    });

    test('rejects malformed payloads instead of throwing', () {
      expect(AppUpdateInfo.tryParse('not json'), isNull);
      expect(AppUpdateInfo.tryParse('{}'), isNull);
      expect(AppUpdateInfo.tryParse('[1,2,3]'), isNull);
      expect(
        AppUpdateInfo.tryParse(
          '{"version":"1.0.134","versionCode":"139","commit":"x","assets":{}}',
        ),
        isNull,
        reason: 'versionCode must be an int, not a string',
      );
      expect(
        AppUpdateInfo.tryParse(
          '{"version":"1.0.134","versionCode":139,"commit":"x"}',
        ),
        isNull,
        reason: 'assets is required to locate the APK per ABI',
      );
    });
  });
}
