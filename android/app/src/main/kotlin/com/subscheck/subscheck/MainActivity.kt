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
        private const val REQ_SAVE = 9004
        private const val PREFS = "subscheck"
        private const val KEY_DISCLAIMER = "disclaimer_seen"
        private const val KEY_UPDATE_SKIP = "update_skip_version"
        private const val KEY_AUTO_UPDATE = "auto_check_update"
    }

    private val pool = Executors.newSingleThreadExecutor { r ->
        Thread(r, "subscheck-native").apply { isDaemon = true }
    }

    private var pending: MethodChannel.Result? = null
    private var channel: MethodChannel? = null

    // 系统「保存到…」对话框（ACTION_CREATE_DOCUMENT）是异步返回的，
    // 这里记住待写的内容和待回的 MethodChannel 结果，等 onActivityResult 再兑现。
    private var pendingSaveResult: MethodChannel.Result? = null
    private var pendingSaveName: String = ""
    private var pendingSaveContent: String = ""

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val km = KernelManager.get(this)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        ch.setMethodCallHandler { call, result -> runAsync(call, result) }
        channel = ch
    }

    private fun runAsync(call: MethodCall, result: MethodChannel.Result) {
        // 「另存为…」要等系统保存对话框返回，不能放进工作线程同步兑现。
        if (call.method == "saveExportAs") {
            val name = call.argument<String>("name") ?: "export.yaml"
            val content = call.argument<String>("content") ?: ""
            launchSaveDocument(name, content, result)
            return
        }
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

            "installStatus" -> mapOf(
                "allowed" to ApkDownloader.isInstallAllowed(this),
                "hasCached" to ApkDownloader.hasCachedApk(this)
            )

            "installNow" -> {
                // 先走「上次卡在权限上」的续装；标记可能因进程重建而丢失，再从缓存兜底。
                val ok = ApkDownloader.resumeIfPending(this) || ApkDownloader.installCached(this)
                val out = HashMap<String, Any?>(ApkDownloader.status())
                out["relaunched"] = ok
                out["allowed"] = ApkDownloader.isInstallAllowed(this)
                out
            }

            // 用户显式点「继续安装」时的兜底：不判权限，直接交给系统安装器裁决。
            "installForce" -> mapOf(
                "relaunched" to ApkDownloader.forceInstallCached(this),
                "allowed" to ApkDownloader.isInstallAllowed(this)
            )

            // 分享用：把内容写到一份真实存在的缓存副本并返回绝对路径。
            // 自定义目录（SAF）下 saveExport 返回的是展示用的拼接路径，磁盘上没有这个文件，
            // 直接交给分享面板会 FileNotFoundException。
            "shareCopy" -> {
                val name = call.argument<String>("name") ?: "export.yaml"
                val content = call.argument<String>("content") ?: ""
                val dir = java.io.File(cacheDir, "share")
                if (!dir.exists()) dir.mkdirs()
                val f = java.io.File(dir, name.replace('/', '_').replace('\\', '_'))
                f.writeText(content)
                mapOf("path" to f.absolutePath, "bytes" to f.length(), "name" to name)
            }

            // 部分国产 ROM 会在息屏后冻结后台进程，导致前台服务里的内核被掐，
            // 这里只做「引导用户去系统里放行」，不尝试代改。
            "batteryStatus" -> mapOf("ignoring" to isIgnoringBattery())

            "requestBattery" -> {
                runOnUiThread { openBatterySettings() }
                mapOf("ignoring" to isIgnoringBattery())
            }

            "disclaimerSeen" -> mapOf("seen" to prefs().getBoolean(KEY_DISCLAIMER, false))

            "setDisclaimerSeen" -> {
                prefs().edit().putBoolean(KEY_DISCLAIMER, true).apply()
                mapOf("ok" to true)
            }

            // 启动自动检查更新时用："不再提示此版本"记下被忽略的版本号，
            // 下次启动只有当远端版本比它更新时才会再弹。
            "updateSkip" -> mapOf(
                "version" to prefs().getString(KEY_UPDATE_SKIP, "").orEmpty(),
                "auto" to prefs().getBoolean(KEY_AUTO_UPDATE, true)
            )

            "setAutoUpdate" -> {
                val on = call.argument<Boolean>("on") ?: true
                prefs().edit().putBoolean(KEY_AUTO_UPDATE, on).apply()
                if (on) prefs().edit().remove(KEY_UPDATE_SKIP).apply()
                mapOf("ok" to true, "auto" to on)
            }

            "setUpdateSkip" -> {
                val v = call.argument<String>("version") ?: ""
                prefs().edit().putString(KEY_UPDATE_SKIP, v).apply()
                mapOf("ok" to true, "version" to v)
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

    /**
     * 拉系统「保存到…」对话框（SAF ACTION_CREATE_DOCUMENT）。
     * 与 ACTION_OPEN_DOCUMENT_TREE 不同，这里用户可以自己挑文件名和目标位置，
     * 默认目录是「下载」，选完把内容写进返回的 URI。
     */
    private fun launchSaveDocument(name: String, content: String, result: MethodChannel.Result) {
        if (pendingSaveResult != null) {
            result.error("busy", "另一个保存对话框还开着", null)
            return
        }
        pendingSaveResult = result
        pendingSaveName = name
        pendingSaveContent = content
        runOnUiThread {
            try {
                val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = ExportStore.mimeFor(name)
                    putExtra(Intent.EXTRA_TITLE, name)
                    addFlags(
                        Intent.FLAG_GRANT_READ_URI_PERMISSION or
                            Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                            Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
                    )
                }
                startActivityForResult(intent, REQ_SAVE)
            } catch (e: Exception) {
                Log.w(TAG, "launch save document: " + e.message)
                finishPendingSave(
                    mapOf(
                        "ok" to false,
                        "canceled" to true,
                        "error" to ("系统没有可用的保存对话框：" + (e.message ?: ""))
                    )
                )
            }
        }
    }

    /** 兑现挂起的「另存为」结果；只能调一次。 */
    private fun finishPendingSave(payload: Map<String, Any?>) {
        val r = pendingSaveResult ?: return
        pendingSaveResult = null
        val content = pendingSaveContent
        val name = pendingSaveName
        pendingSaveContent = ""
        pendingSaveName = ""
        runOnUiThread { r.success(payload) }
        Log.i(TAG, "save as finished: " + name + " -> " + payload["path"])
        if (content.isEmpty()) Log.w(TAG, "save as: empty content")
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
        if (requestCode == REQ_SAVE) {
            handleSaveDocumentResult(resultCode, data)
            return
        }
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

    /** 「另存为」对话框返回：把内容写进用户挑的文档 URI（新建或覆盖同名文档）。 */
    private fun handleSaveDocumentResult(resultCode: Int, data: Intent?) {
        val uri = data?.data
        if (resultCode != RESULT_OK || uri == null) {
            finishPendingSave(mapOf("ok" to false, "canceled" to true))
            return
        }
        val name = pendingSaveName
        val content = pendingSaveContent
        val bytes = content.toByteArray(Charsets.UTF_8)
        try {
            // "wt" 先截断再写，避免旧内容比新内容长时留下尾巴。
            contentResolver.openOutputStream(uri, "wt")?.use { it.write(bytes); it.flush() }
                ?: throw java.io.IOException("无法打开所选位置")
        } catch (e: Exception) {
            Log.w(TAG, "write document: " + e.message)
            try {
                contentResolver.openOutputStream(uri)?.use { it.write(bytes); it.flush() }
            } catch (e2: Exception) {
                Log.w(TAG, "write document(retry): " + e2.message)
                finishPendingSave(
                    mapOf("ok" to false, "error" to ("写入失败：" + (e2.message ?: e2.toString())))
                )
                return
            }
        }
        val shown = ExportStore.friendlyLabelFor(this, uri)
        finishPendingSave(
            mapOf(
                "ok" to true,
                "path" to shown,
                "size" to bytes.size.toLong(),
                "name" to name
            )
        )
    }

    private fun prefs() = getSharedPreferences(PREFS, MODE_PRIVATE)

    private fun isIgnoringBattery(): Boolean {
        if (Build.VERSION.SDK_INT < 23) return true
        return try {
            val pm = getSystemService(POWER_SERVICE) as android.os.PowerManager
            pm.isIgnoringBatteryOptimizations(packageName)
        } catch (e: Throwable) {
            Log.w(TAG, "battery status: " + e.message)
            true
        }
    }

    /**
     * 拉系统「忽略电池优化」白名单。优先直接弹本应用的授权框，
     * 个别 ROM 不认这个 action，退到电池优化列表页让用户自己找。
     */
    private fun openBatterySettings() {
        if (Build.VERSION.SDK_INT < 23) return
        try {
            val direct = Intent(android.provider.Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                data = android.net.Uri.parse("package:" + packageName)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(direct)
            return
        } catch (e: Exception) {
            Log.w(TAG, "request ignore battery: " + e.message)
        }
        try {
            val list = Intent(android.provider.Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(list)
        } catch (e: Exception) {
            Log.w(TAG, "battery settings: " + e.message)
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
