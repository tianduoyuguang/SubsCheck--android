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
        private const val REQ_STORAGE = 9002
        const val REQ_TREE = 9003
    }

    private val pool = Executors.newSingleThreadExecutor { r ->
        Thread(r, "subscheck-native").apply { isDaemon = true }
    }

    private var pending: MethodChannel.Result? = null
    private var channel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val km = KernelManager.get(this)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        ch.setMethodCallHandler { call, result -> runAsync(call, result) }
        channel = ch
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
                km.saveExport(name, content)
            }

            "exportInfo" -> ExportStore.info(this)

            "setExportMode" -> {
                val mode = call.argument<String>("mode") ?: ExportStore.MODE_PRIVATE
                ExportStore.setMode(this, mode)
                if (mode == ExportStore.MODE_DOWNLOAD) requestStoragePermissionIfNeeded()
                ExportStore.info(this)
            }

            "setExportTree" -> {
                val raw = call.argument<String>("uri") ?: ""
                if (raw.isNotEmpty()) ExportStore.setTree(this, android.net.Uri.parse(raw))
                ExportStore.info(this)
            }

            "pickExportDir" -> {
                runOnUiThread { launchTreePicker() }
                mapOf("ok" to true)
            }

            "clearExportTree" -> {
                ExportStore.setTree(this, android.net.Uri.parse(""))
                ExportStore.setMode(this, ExportStore.MODE_PRIVATE)
                ExportStore.info(this)
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

            // 「安装未知应用」授权：跳到系统设置页，或查询当前是否已允许。
            // startActivity 必须回主线程，dispatch 是在工作线程池里跑的。
            "installPermission" -> {
                runOnUiThread {
                    try {
                        val out = ApkDownloader.requestPermission(this)
                        runOnUiThread { channel?.invokeMethod("installPermissionOpened", out) }
                    } catch (e: Exception) {
                        Log.w(TAG, "install permission: " + e.message)
                    }
                }
                val out = HashMap<String, Any?>(ApkDownloader.status())
                out["ok"] = true
                out["allowed"] = ApkDownloader.isInstallAllowed(this)
                out
            }

            "installStatus" -> mapOf("allowed" to ApkDownloader.isInstallAllowed(this))

            "installNow" -> {
                val ok = ApkDownloader.resumeIfPending(this)
                val out = HashMap<String, Any?>(ApkDownloader.status())
                out["relaunched"] = ok
                out
            }

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

    private fun launchTreePicker() {
        try {
            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                addFlags(
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or
                        Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                        Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                        Intent.FLAG_GRANT_PREFIX_URI_PERMISSION
                )
            }
            startActivityForResult(intent, REQ_TREE)
        } catch (e: Exception) {
            Log.w(TAG, "launch tree picker: " + e.message)
            // 个别 ROM 没有 DocumentsUI，退回到公共 Download 目录
            ExportStore.setMode(this, ExportStore.MODE_DOWNLOAD)
            runOnUiThread { channel?.invokeMethod("exportDirChanged", ExportStore.info(this)) }
        }
    }

    private fun requestStoragePermissionIfNeeded() {
        if (Build.VERSION.SDK_INT < 23) return
        if (ExportStore.hasStoragePermission(this)) return
        runOnUiThread {
            try {
                requestPermissions(
                    arrayOf(
                        Manifest.permission.WRITE_EXTERNAL_STORAGE,
                        Manifest.permission.READ_EXTERNAL_STORAGE
                    ), REQ_STORAGE
                )
            } catch (e: Exception) {
                Log.w(TAG, "request storage permission: " + e.message)
            }
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQ_STORAGE) {
            val granted = ExportStore.hasStoragePermission(this)
            Log.i(TAG, "storage permission granted=" + granted)
        }
    }

    /**
     * 处理系统文件夹选择器（SAF）返回的目录。用户取消时 treeUri 为空，
     * 此时保持原设置不动，避免把已选目录清掉。
     */
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQ_TREE) return
        val uri = data?.data
        if (resultCode != RESULT_OK || uri == null) return
        try {
            contentResolver.takePersistableUriPermission(
                uri, Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            )
        } catch (e: Exception) {
            Log.w(TAG, "takePersistableUriPermission: " + e.message)
        }
        ExportStore.setTree(this, uri)
        Log.i(TAG, "export dir -> " + ExportStore.displayPath(this))
        channel?.invokeMethod("exportDirChanged", ExportStore.info(this))
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

    /**
     * 用户可能去系统设置里开了「安装未知应用」再回来：此时自动续上被挡住的安装，
     * 免得用户还要再点一次下载。App 从前台以外回到前台才会走到这里。
     */
    override fun onResume() {
        super.onResume()
        try {
            if (ApkDownloader.resumeIfPending(this)) {
                Log.i(TAG, "install resumed after permission return")
            }
        } catch (e: Exception) {
            Log.w(TAG, "resume install: " + e.message)
        }
    }

    override fun onDestroy() {
        try { pool.shutdown() } catch (e: Exception) { }
        super.onDestroy()
    }
}
