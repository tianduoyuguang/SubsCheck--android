package com.subscheck.subscheck

import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import java.io.File
import java.util.ArrayDeque
import java.util.concurrent.TimeUnit
import java.util.zip.ZipFile

/**
 * 内核进程管理：定位/准备内核二进制、生成 config.yaml、启动停止进程、收集 stdout。
 * 内核是 GOOS=linux 静态编译的 ET_EXEC 程序（无 PT_INTERP、无 PIE），
 * 因此优先从 nativeLibraryDir 执行（jniLibs 里命名为 lib*.so 才会被安装器解压）。
 */
class KernelManager private constructor(ctx: Context) {

    companion object {
        private const val TAG = "SubsCheckKernel"
        private const val PREF = "subscheck"
        private const val KEY_API = "api_key"
        private const val KEY_HOST = "listen_host"
        private const val KEY_PORT = "listen_port"
        private const val MAX_LOG_LINES = 800

        @Volatile
        private var instance: KernelManager? = null

        fun get(ctx: Context): KernelManager =
            instance ?: synchronized(this) {
                instance ?: KernelManager(ctx.applicationContext).also { instance = it }
            }
    }

    private val app: Context = ctx.applicationContext
    private val prefs = app.getSharedPreferences(PREF, Context.MODE_PRIVATE)
    private var process: Process? = null

    @Volatile
    private var exitCode: Int? = null

    @Volatile
    private var stopping = false

    private val logLines = ArrayDeque<String>()
    private val logLock = Any()

    val baseDir: File get() = File(app.filesDir, "kernel")
    val configDir: File get() = File(baseDir, "config")
    val configFile: File get() = File(configDir, "config.yaml")
    val outputDir: File get() = File(baseDir, "output")
    val tmpDir: File get() = File(baseDir, "tmp")
    val binDir: File get() = File(baseDir, "bin")

    var listenHost: String
        get() = prefs.getString(KEY_HOST, "127.0.0.1") ?: "127.0.0.1"
        set(v) = prefs.edit().putString(KEY_HOST, v).apply()

    var listenPort: Int
        get() = prefs.getInt(KEY_PORT, 8199)
        set(v) = prefs.edit().putInt(KEY_PORT, v).apply()

    val apiKey: String
        get() {
            val cur = prefs.getString(KEY_API, null)
            if (cur != null && cur.isNotEmpty()) return cur
            val chars = "0123456789abcdef"
            val rnd = java.util.Random()
            val sb = StringBuilder()
            repeat(24) { sb.append(chars[rnd.nextInt(chars.length)]) }
            val gen = sb.toString()
            prefs.edit().putString(KEY_API, gen).apply()
            return gen
        }

    init {
        configDir.mkdirs()
        outputDir.mkdirs()
        tmpDir.mkdirs()
        binDir.mkdirs()
    }

    private fun listenAddress(): String = listenHost + ":" + listenPort

    fun prepare(template: String): Map<String, Any?> {
        configDir.mkdirs()
        outputDir.mkdirs()
        tmpDir.mkdirs()
        val bin = ensureBinary()
        if (template.isNotEmpty()) {
            val current = if (configFile.exists()) configFile.readText() else ""
            val patched = patchConfig(if (current.isEmpty()) template else current,
                outputDir.absolutePath, listenAddress(), apiKey)
            if (patched != current) {
                configFile.writeText(patched)
                Log.i(TAG, "wrote config " + configFile.absolutePath)
            }
        }
        return mapOf(
            "configPath" to configFile.absolutePath,
            "outputDir" to outputDir.absolutePath,
            "configDir" to configDir.absolutePath,
            "tmpDir" to tmpDir.absolutePath,
            "binPath" to bin.absolutePath,
            "apiKey" to apiKey,
            "port" to listenPort,
            "host" to listenHost,
            "abi" to Build.SUPPORTED_ABIS.firstOrNull(),
            "sdk" to Build.VERSION.SDK_INT,
            "running" to isRunning(),
            // 设置页/关于页要在 prepare 之后立刻显示版本号，
            // 这里一并带上，免得它们回落到硬编码的默认值。
            "versionName" to app.packageManager.getPackageInfo(app.packageName, 0).versionName,
            "versionCode" to (if (Build.VERSION.SDK_INT >= 28)
                app.packageManager.getPackageInfo(app.packageName, 0).longVersionCode
            else app.packageManager.getPackageInfo(app.packageName, 0).versionCode.toLong()),
            "packageName" to app.packageName,
            "device" to (Build.MANUFACTURER + " " + Build.MODEL)
        ) + ExportStore.info(app)
    }

    /** 强制重写配置（用户改了输出目录/端口/密钥后调） */
    fun rewriteConfig(content: String) {
        configDir.mkdirs()
        configFile.writeText(content)
    }

    private fun patchConfig(text: String, outDir: String, addr: String, key: String): String {
        val sb = StringBuilder()
        for (line in text.split("\n")) {
            val t = line.trimStart()
            when {
                t.startsWith("output-dir:") -> sb.append("output-dir: \"").append(outDir).append("\"")
                t.startsWith("listen-port:") -> sb.append("listen-port: \"").append(addr).append("\"")
                t.startsWith("api-key:") -> sb.append("api-key: \"").append(key).append("\"")
                t.startsWith("sub-store-port:") -> sb.append("sub-store-port: \"\"")
                t.startsWith("enable-web-ui:") -> sb.append("enable-web-ui: true")
                else -> sb.append(line)
            }
            sb.append('\n')
        }
        return sb.toString()
    }

    fun syncListenAddress() {
        if (!configFile.exists()) return
        val text = configFile.readText()
        val addr = listenAddress()
        val regex = Regex("(?m)^listen-port:.*$")
        val next = if (regex.containsMatchIn(text)) regex.replace(text, "listen-port: \"" + addr + "\"") else text
        if (next != text) configFile.writeText(next)
    }

    private fun chmod(f: File, mode: String): Boolean = try {
        val p = Runtime.getRuntime().exec(arrayOf("chmod", mode, f.absolutePath))
        p.waitFor(5, TimeUnit.SECONDS)
        f.canExecute() || p.exitValue() == 0
    } catch (e: Exception) {
        Log.w(TAG, "chmod failed: " + e.message)
        false
    }

    /** 优先 nativeLibraryDir/libsubscheck.so；不可用时从 APK 解压到 filesDir/bin/sub检查并 chmod */
    fun ensureBinary(): File {
        val info = app.applicationInfo
        val libDir = info.nativeLibraryDir
        if (!libDir.isNullOrEmpty()) {
            val f = File(libDir, "libsubscheck.so")
            if (f.exists() && f.length() > 1_000_000) return f
        }
        val out = File(binDir, "subscheck")
        if (out.exists() && out.length() > 1_000_000 && out.canExecute()) return out
        val src = File(info.sourceDir)
        binDir.mkdirs()
        if (src.exists()) {
            ZipFile(src).use { zip ->
                for (abi in Build.SUPPORTED_ABIS) {
                    val entry = zip.getEntry("lib/" + abi + "/libsubscheck.so") ?: continue
                    zip.getInputStream(entry).use { input ->
                        out.outputStream().use { output -> input.copyTo(output, 1 shl 20) }
                    }
                    break
                }
            }
        }
        if (!out.exists() && !libDir.isNullOrEmpty()) {
            val n = File(libDir, "libsubscheck.so")
            if (n.exists()) n.copyTo(out, overwrite = true)
        }
        if (!out.exists()) throw IllegalStateException("找不到内核二进制：当前 ABI " + Build.SUPPORTED_ABIS.joinToString(","))
        chmod(out, "755")
        return out
    }

    fun isRunning(): Boolean {
        val p = process ?: return false
        return p.isAlive
    }

    fun pid(): Int {
        val p = process ?: return -1
        if (!p.isAlive) return -1
        return try {
            (Process::class.java.getMethod("pid").invoke(p) as Long).toInt()
        } catch (e: Exception) {
            -1
        }
    }

    private fun buildProcess(bin: File, dir: File): ProcessBuilder {
        val pb = ProcessBuilder(bin.absolutePath, "-f", configFile.absolutePath)
        pb.directory(dir)
        pb.redirectErrorStream(true)
        val env = pb.environment()
        env["TMPDIR"] = tmpDir.absolutePath
        env["HOME"] = baseDir.absolutePath
        env["PATH"] = "/system/bin:/system/xbin"
        env["SUB_CHECK_DNS"] = "223.5.5.5,119.29.29.29"
        env["GIN_MODE"] = "release"
        return pb
    }

    @Synchronized
    fun start(): Map<String, Any?> {
        if (isRunning()) return statusMap()
        if (!configFile.exists()) throw IllegalStateException("配置文件不存在")
        syncListenAddress()
        stopping = false
        exitCode = null
        synchronized(logLock) { logLines.clear() }
        val bin = ensureBinary()
        appendLog("[subscheck] 内核: " + bin.absolutePath)
        appendLog("[subscheck] 配置: " + configFile.absolutePath)
        var launched: Process? = null
        try {
            launched = buildProcess(bin, baseDir).start()
        } catch (e: Exception) {
            appendLog("[subscheck] 直接执行失败: " + e.message + "，改用私有目录副本")
            val fb = File(binDir, "subscheck")
            try {
                bin.copyTo(fb, overwrite = true)
                chmod(fb, "755")
                launched = buildProcess(fb, baseDir).start()
            } catch (e2: Exception) {
                appendLog("[subscheck] 启动失败: " + e2.message)
                throw e2
            }
        }
        process = launched
        val p = launched
        appendLog("[subscheck] 内核已启动 pid=" + p.pid())
        Thread({ pump(p) }, "subscheck-stdout").apply { isDaemon = true; start() }
        return statusMap()
    }

    // Android 的 java.lang.Process 没有 pid()，反射会拿到 App 自己的 pid，
    // 所以直接扫 /proc 找 cmdline 指向内核 so 的进程。
    fun Process.pid(): String = findKernelPid()?.toString() ?: "?"

    private fun findKernelPid(): Int? {
        val self = android.os.Process.myPid()
        val entries = File("/proc").list() ?: return null
        for (name in entries) {
            val pid = name.toIntOrNull() ?: continue
            if (pid == self) continue
            val cmdline = File("/proc/" + name + "/cmdline")
            if (!cmdline.exists()) continue
            val text = try {
                cmdline.readText()
            } catch (e: Exception) {
                continue
            }
            // 子进程 cmdline 是内核二进制的绝对路径（含 libsubscheck），
            // 而 App 自己的 cmdline 是包名，靠这个区分。
            if (text.contains("libsubscheck") || text.contains("/subscheck")) return pid
        }
        return null
    }

    // 内核日志带 ANSI 颜色（tint），直接显示会出现 [2m / [0m 这类乱码。
    private val ansiPattern = Regex("\u001B\\[[0-9;]*[a-zA-Z]")

    private fun pump(p: Process) {
        try {
            p.inputStream.bufferedReader().use { r ->
                while (true) {
                    val line = r.readLine() ?: break
                    appendLog(line)
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "read stdout: " + e.message)
        }
        val code = try { p.waitFor() } catch (e: Exception) { -1 }
        exitCode = code
        appendLog("[subscheck] 进程退出 code=" + code)
    }

    private fun appendLog(raw: String) {
        val line = raw.replace(ansiPattern, "")
        synchronized(logLock) {
            logLines.addLast(line)
            while (logLines.size > MAX_LOG_LINES) logLines.removeFirst()
        }
    }

    fun stdoutTail(limit: Int): String {
        synchronized(logLock) {
            val arr = logLines.toList()
            return arr.takeLast(limit).joinToString("\n")
        }
    }

    fun exitCodeValue(): Int? = exitCode

    @Synchronized
    fun stop() {
        stopping = true
        val p = process ?: return
        appendLog("[subscheck] 正在停止内核 ...")
        try { p.destroy() } catch (e: Exception) { }
        val gone = try { p.waitFor(3, TimeUnit.SECONDS) } catch (e: Exception) { false }
        if (!gone) {
            try { p.destroyForcibly() } catch (e: Exception) { }
        }
        process = null
        appendLog("[subscheck] 内核已停止")
    }

    @Synchronized
    fun restart(): Map<String, Any?> {
        stop()
        Thread.sleep(400)
        return start()
    }

    /** 导出文件写到用户选定的目录（私有 / 公共 Download / SAF 自选） */
    fun saveExport(name: String, content: String): Map<String, Any?> {
        val saved = ExportStore.save(app, name, content)
        return mapOf(
            "path" to saved.path,
            "size" to saved.size,
            "exportMode" to ExportStore.mode(app),
            "exportLabel" to ExportStore.label(app),
            "exportPath" to ExportStore.displayPath(app)
        )
    }

    fun clearResults() {
        try {
            outputDir.listFiles()?.forEach { if (it.isFile) it.delete() }
            File(configDir, "cache").deleteRecursively()
        } catch (e: Exception) {
            Log.w(TAG, "clearResults: " + e.message)
        }
    }

    fun statusMap(): Map<String, Any?> = mapOf(
        "running" to isRunning(),
        "pid" to pid(),
        "port" to listenPort,
        "host" to listenHost,
        "apiKey" to apiKey,
        "configPath" to configFile.absolutePath,
        "outputDir" to outputDir.absolutePath,
        "exitCode" to exitCode
    )

    fun info(): Map<String, Any?> {
        val pkg = app.packageManager.getPackageInfo(app.packageName, 0)
        return mapOf(
            "versionName" to pkg.versionName,
            "versionCode" to (if (Build.VERSION.SDK_INT >= 28) pkg.longVersionCode else pkg.versionCode.toLong()),
            "packageName" to app.packageName,
            "abi" to Build.SUPPORTED_ABIS.firstOrNull(),
            "sdk" to Build.VERSION.SDK_INT,
            "device" to (Build.MANUFACTURER + " " + Build.MODEL),
            "nativeLibraryDir" to (app.applicationInfo.nativeLibraryDir ?: ""),
            "filesDir" to app.filesDir.absolutePath,
            "outputDir" to outputDir.absolutePath,
            "tmpDir" to tmpDir.absolutePath,
            "configPath" to configFile.absolutePath,
            "port" to listenPort,
            "host" to listenHost,
            "apiKey" to apiKey,
            "running" to isRunning(),
            "pid" to pid()
        ) + ExportStore.info(app)
    }

    fun startForegroundService() {
        val intent = Intent(app, KernelService::class.java)
        if (Build.VERSION.SDK_INT >= 26) app.startForegroundService(intent) else app.startService(intent)
    }

    fun stopForegroundService() {
        app.stopService(Intent(app, KernelService::class.java))
    }
}
