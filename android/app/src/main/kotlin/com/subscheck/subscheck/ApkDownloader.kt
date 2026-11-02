package com.subscheck.subscheck

import android.app.DownloadManager
import android.content.Context
import android.content.Intent
import android.net.Uri
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
            set("done", true)
            install(app, target)
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

    private fun install(ctx: Context, apk: File) {
        try {
            val uri = FileProvider.getUriForFile(ctx, ctx.packageName + ".fileprovider", apk)
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            ctx.startActivity(intent)
        } catch (e: Exception) {
            Log.w(TAG, "install intent failed: " + e.message)
            set("error", "无法唤起安装器：" + (e.message ?: e.toString()))
        }
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
