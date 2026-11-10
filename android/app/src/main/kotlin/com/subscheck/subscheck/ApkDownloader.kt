package com.subscheck.subscheck

import android.app.DownloadManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.Log
import androidx.core.content.FileProvider
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

/**
 * 更新包下载器：不依赖 DownloadManager（它无法把私有目录的产物交给安装器），
 * 自己用 HttpURLConnection 流式下载到 cacheDir，完成后通过 FileProvider 拉起
 * 系统安装器。全部状态都放进 [status]，供 Flutter 侧轮询进度。
 */
object ApkDownloader {

    private const val TAG = "SubsCheckDownload"
    private const val MAX_BYTES = 300L * 1024 * 1024

    @Volatile private var state: MutableMap<String, Any?> = HashMap()

    fun status(): Map<String, Any?> = HashMap(state)

    @Synchronized
    fun start(ctx: Context, url: String, fileName: String) {
        val running = state["downloading"] == true
        if (running) return
        val safeName = if (fileName.endsWith(".apk")) fileName else "subscheck-update.apk"
        state = HashMap<String, Any?>().apply {
            put("downloading", true)
            put("percent", 0)
            put("received", 0L)
            put("total", 0L)
            put("done", false)
            put("error", null)
            put("path", null)
            put("needPermission", false)
            put("installing", false)
        }
        val app = ctx.applicationContext
        Thread({ run(app, url, safeName) }, "subscheck-download").apply { isDaemon = true }.start()
    }

    private fun set(key: String, value: Any?) {
        synchronized(this) {
            val next = HashMap(state)
            next[key] = value
            state = next
        }
    }

    private fun run(app: Context, url: String, fileName: String) {
        val dir = File(app.cacheDir, "update").apply { mkdirs() }
        // 旧包先清掉，避免磁盘上堆积几十兆。
        dir.listFiles()?.forEach { it.delete() }
        val target = File(dir, fileName)
        try {
            var conn = open(url)
            if (conn.responseCode !in 200..299) {
                val code = conn.responseCode
                conn.disconnect()
                throw IllegalStateException("HTTP " + code)
            }
            val total = conn.contentLengthLong
            if (total > MAX_BYTES) throw IllegalStateException("文件过大: " + total)
            set("total", total)
            var received = 0L
            conn.inputStream.use { input ->
                target.outputStream().use { output ->
                    val buf = ByteArray(64 * 1024)
                    while (true) {
                        val n = input.read(buf)
                        if (n < 0) break
                        output.write(buf, 0, n)
                        received += n
                        if (total > 0) {
                            val pct = (received * 100 / total).toInt()
                            if (pct != state["percent"]) {
                                set("received", received)
                                set("percent", pct)
                            }
                        } else {
                            set("received", received)
                        }
                    }
                }
            }
            conn.disconnect()
            if (target.length() < 1024) throw IllegalStateException("下载内容为空")
            set("path", target.absolutePath)
            set("percent", 100)
            set("downloading", false)
            // 先尝试安装再置 done：这样 Flutter 侧一旦看到 done，needPermission
            // 就已经是最终值，不会先弹一句「下载完成」再卡住。
            install(app, target)
            set("done", true)
        } catch (e: Exception) {
            Log.w(TAG, "download failed: " + e.message)
            set("downloading", false)
            set("done", false)
            set("error", e.message ?: e.toString())
        }
    }

    private fun open(url: String): HttpURLConnection {
        var current = url
        var hops = 0
        while (hops++ < 5) {
            val conn = URL(current).openConnection() as HttpURLConnection
            conn.connectTimeout = 15000
            conn.readTimeout = 30000
            conn.instanceFollowRedirects = false
            conn.setRequestProperty("User-Agent", "SubsCheck-Android")
            conn.connect()
            val code = conn.responseCode
            if (code in 300..399) {
                val location = conn.getHeaderField("Location") ?: break
                conn.disconnect()
                current = if (location.startsWith("http")) location else URL(URL(current), location).toString()
                continue
            }
            return conn
        }
        throw IllegalStateException("重定向过多")
    }

    /** Android 8.0+ 未授予「安装未知应用」时不能拉起安装器。 */
    fun isInstallAllowed(ctx: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return true
        return try {
            ctx.packageManager.canRequestPackageInstalls()
        } catch (e: Exception) {
            true
        }
    }

    /**
     * 打开系统「安装未知应用」授权页。这是系统强制交互，App 无法代用户授权，
     * 只能把用户送到正确的开关上。返回 false 表示该 ROM 没有对应页面。
     */
    fun openInstallSettings(ctx: Context): Boolean {
        val pkgUri = Uri.parse("package:" + ctx.packageName)
        val candidates = listOf(
            Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, pkgUri),
            Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES),
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, pkgUri)
        )
        for (base in candidates) {
            try {
                val intent = Intent(base).apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) }
                ctx.startActivity(intent)
                return true
            } catch (e: Exception) {
                Log.w(TAG, "open install settings failed: " + e.message)
            }
        }
        return false
    }

    private fun install(ctx: Context, apk: File) {
        if (!isInstallAllowed(ctx)) {
            // 包已下载好，只差一次系统授权；用户在授权页打开开关后回到 App 会自动续装。
            set("needPermission", true)
            set("installing", false)
            set("error", "缺少「安装未知应用」权限")
            Log.i(TAG, "install blocked: REQUEST_INSTALL_PACKAGES not granted")
            return
        }
        try {
            val uri = FileProvider.getUriForFile(ctx, ctx.packageName + ".fileprovider", apk)
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            ctx.startActivity(intent)
            set("needPermission", false)
            set("installing", true)
        } catch (e: Exception) {
            Log.w(TAG, "install intent failed: " + e.message)
            set("error", "无法唤起安装器：" + (e.message ?: e.toString()))
        }
    }

    /**
     * 用户从系统设置返回后调用：若之前卡在权限上、且现在已授权，就接着装。
     * 返回 true 表示本次确实重新拉起了安装器。
     */
    fun resumeIfPending(ctx: Context): Boolean {
        val snapshot = status()
        if (snapshot["needPermission"] != true) return false
        if (snapshot["done"] != true) return false
        if (!isInstallAllowed(ctx)) return false
        val path = snapshot["path"] as? String ?: return false
        val apk = File(path)
        if (!apk.exists() || apk.length() < 1024) return false
        Log.i(TAG, "install permission granted, resuming install")
        install(ctx, apk)
        return true
    }

    /** Flutter 侧在弹窗里点「去授权」时调用。 */
    fun requestPermission(ctx: Context): Map<String, Any?> {
        val opened = openInstallSettings(ctx)
        val next = HashMap(status())
        next["ok"] = opened
        next["allowed"] = isInstallAllowed(ctx)
        if (!opened) next["error"] = "当前系统没有「安装未知应用」设置页"
        return next
    }

    /** 仅当系统下载器可用时的备用方案（当前未使用，保留给后续调度下载的需求）。 */
    @Suppress("unused")
    fun enqueueSystem(ctx: Context, url: String, fileName: String): Long {
        val req = DownloadManager.Request(Uri.parse(url))
        req.setTitle(fileName)
        req.setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
        req.setDestinationInExternalFilesDir(ctx, null, fileName)
        val dm = ctx.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
        return dm.enqueue(req)
    }
}
