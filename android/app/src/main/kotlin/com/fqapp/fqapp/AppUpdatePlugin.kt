package com.fqapp.fqapp

import android.content.Context
import android.content.Intent
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * App 内自动更新的安装桥。Dart 侧把新版 APK 下载到缓存目录后，经此通道
 * 用 FileProvider 把文件以内容 URI 临时授权给系统包安装器并调起安装界面。
 * 两个 APK 由同一把 release 证书签发，系统按覆盖安装处理；安装确认始终
 * 由用户在系统界面完成（Android 不允许普通应用静默安装）。
 */
class AppUpdatePlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private var channel: MethodChannel? = null
    private var appContext: Context? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "fqapp/app_update").also {
            it.setMethodCallHandler(this)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        appContext = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "installApk") {
            result.notImplemented()
            return
        }
        val path = call.argument<String>("path")
        val context = appContext
        if (path.isNullOrEmpty() || context == null) {
            result.success(false)
            return
        }
        result.success(
            try {
                val uri = FileProvider.getUriForFile(
                    context,
                    "${context.packageName}.fileprovider",
                    File(path),
                )
                val intent = Intent(Intent.ACTION_VIEW).apply {
                    setDataAndType(uri, "application/vnd.android.package-archive")
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
                context.startActivity(intent)
                true
            } catch (_: Exception) {
                false
            },
        )
    }
}
