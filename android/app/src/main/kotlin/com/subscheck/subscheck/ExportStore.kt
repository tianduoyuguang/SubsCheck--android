package com.subscheck.subscheck

import android.Manifest
import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.DocumentsContract
import android.provider.MediaStore
import android.util.Log
import java.io.File
import java.io.IOException

/**
 * 导出目录管理。三种模式：
 *  - private  : 应用私有外部目录 Android/data/<pkg>/files/exports（默认，卸载即清）
 *  - download : 公共 Download/SubsCheck（文件管理器里直接可见）
 *  - custom   : 用户用系统文件夹选择器（SAF）挑的目录，持久化授权后直接写入
 */
object ExportStore {
    private const val TAG = "SubsCheckExport"
    private const val PREF = "subscheck"
    private const val KEY_MODE = "export_mode"
    private const val KEY_TREE = "export_tree_uri"
    private const val KEY_TREE_LABEL = "export_tree_label"

    const val MODE_PRIVATE = "private"
    const val MODE_DOWNLOAD = "download"
    const val MODE_CUSTOM = "custom"

    data class Saved(val path: String, val size: Long)

    private fun prefs(ctx: Context) = ctx.getSharedPreferences(PREF, Context.MODE_PRIVATE)

    fun mode(ctx: Context): String = prefs(ctx).getString(KEY_MODE, MODE_PRIVATE) ?: MODE_PRIVATE

    fun setMode(ctx: Context, m: String) {
        prefs(ctx).edit().putString(KEY_MODE, m).apply()
    }

    fun treeUri(ctx: Context): String = prefs(ctx).getString(KEY_TREE, "") ?: ""

    fun treeLabel(ctx: Context): String = prefs(ctx).getString(KEY_TREE_LABEL, "") ?: ""

    fun setTree(ctx: Context, uri: Uri) {
        val label = friendlyLabel(uri)
        prefs(ctx).edit()
            .putString(KEY_TREE, uri.toString())
            .putString(KEY_TREE_LABEL, label)
            .putString(KEY_MODE, MODE_CUSTOM)
            .apply()
    }

    /** 把 SAF 的 tree uri 翻译成人类可读的路径，翻译不出来就退回原始 uri。 */
    fun friendlyLabel(uri: Uri): String {
        if (uri.authority != "com.android.externalstorage.documents") return uri.toString()
        val docId = try {
            DocumentsContract.getTreeDocumentId(uri)
        } catch (e: Exception) {
            return uri.toString()
        }
        val volume = docId.substringBefore(':', "")
        val rest = docId.substringAfter(':', "")
        val base = when (volume) {
            "primary" -> "/storage/emulated/0"
            "home" -> "/storage/emulated/0/Documents"
            else -> "/storage/" + volume
        }
        return if (rest.isEmpty()) base else base + "/" + rest
    }

    fun privateDir(ctx: Context): File {
        val root = ctx.getExternalFilesDir(null) ?: File(ctx.filesDir, "export")
        return File(root, "exports")
    }

    fun downloadDir(): File = File(
        Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS), "SubsCheck"
    )

    /** Android 10+ 走 MediaStore 写 Download，不需要任何存储权限；低版本才需要 WRITE。 */
    fun hasStoragePermission(ctx: Context): Boolean = when {
        Build.VERSION.SDK_INT >= 29 -> true
        Build.VERSION.SDK_INT < 23 -> true
        else -> ctx.checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) ==
            PackageManager.PERMISSION_GRANTED
    }

    fun displayPath(ctx: Context): String = when (mode(ctx)) {
        MODE_DOWNLOAD -> downloadDir().absolutePath
        MODE_CUSTOM -> treeLabel(ctx).ifEmpty { treeUri(ctx) }
        else -> privateDir(ctx).absolutePath
    }

    fun label(ctx: Context): String = when (mode(ctx)) {
        MODE_DOWNLOAD -> "手机 Download/SubsCheck"
        MODE_CUSTOM -> "自定义目录"
        else -> "应用私有目录"
    }

    fun info(ctx: Context): Map<String, Any?> = mapOf(
        "exportMode" to mode(ctx),
        "exportLabel" to label(ctx),
        "exportPath" to displayPath(ctx),
        "exportPrivatePath" to privateDir(ctx).absolutePath,
        "exportDownloadPath" to downloadDir().absolutePath,
        "exportHasTree" to treeUri(ctx).isNotEmpty(),
        "exportStorageGranted" to hasStoragePermission(ctx),
        "exportNeedsPermission" to (mode(ctx) == MODE_DOWNLOAD && !hasStoragePermission(ctx))
    )

    fun save(ctx: Context, name: String, content: String): Saved = when (mode(ctx)) {
        MODE_DOWNLOAD -> saveToDownload(ctx, name, content)
        MODE_CUSTOM -> saveToTree(ctx, name, content)
        else -> {
            val dir = privateDir(ctx)
            dir.mkdirs()
            val f = File(dir, name)
            f.writeText(content)
            Saved(f.absolutePath, f.length())
        }
    }

    private fun saveToDownload(ctx: Context, name: String, content: String): Saved {
        val bytes = content.toByteArray(Charsets.UTF_8)
        if (Build.VERSION.SDK_INT >= 29) return saveToDownloadMediaStore(ctx, name, bytes)
        if (!hasStoragePermission(ctx)) {
            throw IOException("没有存储权限，请先授予，或改用「应用私有目录」")
        }
        val dir = downloadDir()
        if (!dir.exists() && !dir.mkdirs()) throw IOException("无法创建目录 " + dir.absolutePath)
        val f = File(dir, name)
        f.writeText(content)
        return Saved(f.absolutePath, f.length())
    }

    /**
     * Android 10+ 用 MediaStore 写入公共 Download/SubsCheck。
     * 不需要 WRITE_EXTERNAL_STORAGE（该权限在 Android 11+ 对普通应用已失效），
     * 也不需要 MANAGE_EXTERNAL_STORAGE（Play 政策限制）。
     */
    private fun saveToDownloadMediaStore(
        ctx: Context, name: String, bytes: ByteArray
    ): Saved {
        val resolver = ctx.contentResolver
        val collection = MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        val relDir = Environment.DIRECTORY_DOWNLOADS + "/SubsCheck"

        // 同名文件先定位（直接 update 覆盖，避免产生 "xxx (1).yaml"）
        var target: Uri? = null
        try {
            resolver.query(
                collection,
                arrayOf(MediaStore.Downloads._ID, MediaStore.Downloads.RELATIVE_PATH),
                MediaStore.Downloads.DISPLAY_NAME + "=?",
                arrayOf(name), null
            )?.use { c ->
                while (c.moveToNext()) {
                    val rel = (c.getString(1) ?: "").trim('/')
                    if (rel.equals(relDir, ignoreCase = true)) {
                        target = ContentUris.withAppendedId(collection, c.getLong(0))
                        break
                    }
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "query media store: " + e.message)
        }

        val values = ContentValues().apply {
            put(MediaStore.Downloads.DISPLAY_NAME, name)
            put(MediaStore.Downloads.MIME_TYPE, mimeFor(name))
            put(MediaStore.Downloads.RELATIVE_PATH, relDir)
            put(MediaStore.Downloads.IS_PENDING, 1)
        }
        val uri = if (target == null) {
            resolver.insert(collection, values) ?: throw IOException("无法在 Download 目录创建文件")
        } else {
            resolver.update(target!!, values, null, null)
            target!!
        }

        try {
            resolver.openOutputStream(uri, "wt")?.use { it.write(bytes); it.flush() }
                ?: throw IOException("无法写入 Download 目录")
            val done = ContentValues().apply { put(MediaStore.Downloads.IS_PENDING, 0) }
            resolver.update(uri, done, null, null)
        } catch (e: Exception) {
            try { resolver.delete(uri, null, null) } catch (ignored: Exception) {}
            throw if (e is IOException) e else IOException("写入 Download 失败：" + e.message)
        }
        return Saved("/storage/emulated/0/" + relDir + "/" + name, bytes.size.toLong())
    }

    private fun mimeFor(name: String): String = when {
        name.endsWith(".yaml", true) || name.endsWith(".yml", true) -> "text/yaml"
        name.endsWith(".txt", true) -> "text/plain"
        name.endsWith(".json", true) -> "application/json"
        else -> "application/octet-stream"
    }

    private fun saveToTree(ctx: Context, name: String, content: String): Saved {
        val raw = treeUri(ctx)
        if (raw.isEmpty()) throw IOException("还没有选择自定义目录")
        val tree = Uri.parse(raw)
        val resolver = ctx.contentResolver
        val docId = try {
            DocumentsContract.getTreeDocumentId(tree)
        } catch (e: Exception) {
            throw IOException("自定义目录已失效，请重新选择")
        }
        // 同名文件先删掉，否则 createDocument 会生成 "xxx (1).yaml"
        var existing: String? = null
        try {
            val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, docId)
            resolver.query(
                children,
                arrayOf(
                    DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                    DocumentsContract.Document.COLUMN_DISPLAY_NAME
                ), null, null, null
            )?.use { c ->
                while (c.moveToNext()) {
                    if (c.getString(1) == name) {
                        existing = c.getString(0)
                        break
                    }
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "query children: " + e.message)
        }

        var target: Uri? = existing?.let { DocumentsContract.buildDocumentUriUsingTree(tree, it) }
        if (target == null) {
            val parent = DocumentsContract.buildDocumentUriUsingTree(tree, docId)
            for (mime in arrayOf("text/yaml", "text/plain", "application/octet-stream")) {
                try {
                    target = DocumentsContract.createDocument(resolver, parent, mime, name)
                    if (target != null) break
                } catch (e: Exception) {
                    Log.w(TAG, "createDocument($mime): " + e.message)
                }
            }
        }
        val uri = target ?: throw IOException("所选目录不支持写入，请换一个目录")

        val bytes = content.toByteArray(Charsets.UTF_8)
        try {
            resolver.openOutputStream(uri, "wt")?.use { it.write(bytes); it.flush() }
                ?: throw IOException("无法写入所选目录")
        } catch (e: IOException) {
            resolver.openOutputStream(uri)?.use { it.write(bytes); it.flush() }
                ?: throw e
        }
        val shown = treeLabel(ctx).trimEnd('/') + "/" + name
        return Saved(shown, bytes.size.toLong())
    }
}
