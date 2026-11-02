package com.subscheck.subscheck

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Callable
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {

    companion object {
        private const val TAG = "SubsCheckMain"
        private const val CHANNEL = "subscheck/native"
        private const val REQ_NOTIF = 9001
    }

    private val pool = Executors.newSingleThreadExecutor { r ->
        Thread(r, "subscheck-native").apply { isDaemon = true }
    }

    private var pending: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val km = KernelManager.get(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            runAsync(call, result)
        }
    }

    private fun runAsync(call: MethodCall, result: MethodChannel.Result) {
        pool.execute {
            val out: Map<String, Any?> = try {
                dispatch(call)
            } catch (e: Throwable) {
                Log.e(TAG, "method " + call.method + " failed", e)
                runOnUiThread { result.error("native_error", e.message ?: e.toString(), null) }
                return@execute
            }
            runOnUiThread { result.success(out) }
        }
    }

    private fun dispatch(call: MethodCall): Map<String, Any?> {
        val km = KernelManager.get(this)
        return when (call.method) {
            "info" -> km.info()

            "prepare" -> {
                val template = call.argument<String>("template") ?: ""
                val r = HashMap<String, Any?>(km.prepare(template))
                r["granted"] = hasNotificationPermission()
                r
            }

            "start" -> {
                requestNotificationPermissionIfNeeded()
                val r = HashMap<String, Any?>(km.start())
                km.startForegroundService()
                r
            }

            "stop" -> {
                km.stop()
                km.stopForegroundService()
                km.statusMap()
            }

            "restart" -> {
                val r = HashMap<String, Any?>(km.restart())
                km.startForegroundService()
                r
            }

            "status" -> km.statusMap()

            "log" -> {
                val n = call.argument<Int>("limit") ?: 300
                mapOf("text" to km.stdoutTail(n))
            }

            "clearResults" -> {
                km.clearResults()
                mapOf("ok" to true)
            }

            "writeConfig" -> {
                val text = call.argument<String>("text") ?: ""
                km.rewriteConfig(text)
                mapOf("ok" to true, "path" to km.configFile.absolutePath)
            }

            "readConfig" -> {
                val f = km.configFile
                mapOf("text" to (if (f.exists()) f.readText() else ""), "path" to f.absolutePath)
            }

            "setPort" -> {
                val port = call.argument<Int>("port") ?: 8199
                km.listenPort = port
                mapOf("ok" to true, "port" to km.listenPort)
            }

            "setHost" -> {
                val host = call.argument<String>("host") ?: "127.0.0.1"
                km.listenHost = host
                mapOf("ok" to true, "host" to km.listenHost)
            }

            "saveExport" -> {
                val name = call.argument<String>("name") ?: "export.yaml"
                val content = call.argument<String>("content") ?: ""
                val f = km.saveExport(name, content)
                mapOf("path" to f.absolutePath, "size" to f.length())
            }

            "openUrl" -> {
                val url = call.argument<String>("url") ?: ""
                openExternally(url)
            }

            "downloadApk" -> {
                val url = call.argument<String>("url") ?: ""
                val name = call.argument<String>("name") ?: "subscheck-update.apk"
                ApkDownloader.start(this, url, name)
                ApkDownloader.status()
            }

            "downloadStatus" -> ApkDownloader.status()

            "notifyPermission" -> mapOf("granted" to hasNotificationPermission())

            "requestNotifyPermission" -> {
                requestNotificationPermissionIfNeeded()
                mapOf("granted" to hasNotificationPermission())
            }

            else -> throw IllegalArgumentException("unknown method " + call.method)
        }
    }

    /**
     * 用系统浏览器打开链接。优先 ACTION_VIEW，个别 ROM 没有浏览器时退到 ACTION_SEND
     * （用户可自行挑一个能处理 URL 的应用），都失败则回报给 Dart 侧提示。
     */
    private fun openExternally(rawUrl: String): Map<String, Any?> {
        if (rawUrl.isEmpty()) return mapOf("ok" to false, "error" to "链接为空")
        val uri = android.net.Uri.parse(rawUrl)
        return try {
            val view = Intent(Intent.ACTION_VIEW, uri).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(view)
            mapOf("ok" to true)
        } catch (e1: Exception) {
            try {
                val send = Intent(Intent.ACTION_SEND).apply {
                    type = "text/plain"
                    putExtra(Intent.EXTRA_TEXT, rawUrl)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                startActivity(send)
                mapOf("ok" to true)
            } catch (e2: Exception) {
                Log.w(TAG, "open url failed: " + e2.message)
                mapOf("ok" to false, "error" to (e2.message ?: e2.toString()))
            }
        }
    }

    private fun hasNotificationPermission(): Boolean {
        if (Build.VERSION.SDK_INT < 33) return true
        return checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
    }

    private fun requestNotificationPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT < 33) return
        if (hasNotificationPermission()) return
        runOnUiThread {
            try {
                requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQ_NOTIF)
            } catch (e: Exception) {
                Log.w(TAG, "request permission: " + e.message)
            }
        }
    }

    override fun onDestroy() {
        try { pool.shutdown() } catch (e: Exception) { }
        super.onDestroy()
    }
}
