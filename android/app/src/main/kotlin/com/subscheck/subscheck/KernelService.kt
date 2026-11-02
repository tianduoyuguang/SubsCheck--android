package com.subscheck.subscheck

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.util.Log

/**
 * 前台服务：只负责把内核进程的存活优先级抬高（避免被系统回收），
 * 真正的进程管理在 KernelManager 单例里，Service 退出不影响内核。
 */
class KernelService : Service() {

    companion object {
        private const val TAG = "SubsCheckService"
        private const val CHANNEL_ID = "subscheck_kernel"
        private const val NOTIF_ID = 4201
        const val ACTION_START = "com.subscheck.subscheck.START"
        const val ACTION_STOP = "com.subscheck.subscheck.STOP"
    }

    private var km: KernelManager? = null

    override fun onCreate() {
        super.onCreate()
        km = KernelManager.get(this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action
        if (action == ACTION_STOP) {
            km?.stop()
            stopForegroundCompat()
            stopSelf()
            return START_NOT_STICKY
        }
        startForegroundCompat()
        try {
            km?.start()
        } catch (e: Exception) {
            Log.e(TAG, "start kernel failed", e)
        }
        return START_STICKY
    }

    private fun channelId(): String {
        if (Build.VERSION.SDK_INT >= 26) {
            val nm = getSystemService(NotificationManager::class.java)
            if (nm.getNotificationChannel(CHANNEL_ID) == null) {
                val ch = NotificationChannel(CHANNEL_ID, "SubsCheck 内核", NotificationManager.IMPORTANCE_LOW)
                ch.setShowBadge(false)
                nm.createNotificationChannel(ch)
            }
        }
        return CHANNEL_ID
    }

    private fun notification(): Notification {
        val open = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java),
            if (Build.VERSION.SDK_INT >= 23) PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            else PendingIntent.FLAG_UPDATE_CURRENT
        )
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, channelId())
        else @Suppress("DEPRECATION") Notification.Builder(this)
        builder.setContentTitle("SubsCheck 运行中")
        builder.setContentText("节点检测内核正在后台运行")
        builder.setSmallIcon(android.R.drawable.stat_notify_sync)
        builder.setContentIntent(open)
        builder.setOngoing(true)
        return builder.build()
    }

    private fun startForegroundCompat() {
        val n = notification()
        if (Build.VERSION.SDK_INT >= 26) {
            startForeground(NOTIF_ID, n)
        } else {
            @Suppress("DEPRECATION")
            startForeground(NOTIF_ID, n)
        }
    }

    private fun stopForegroundCompat() {
        if (Build.VERSION.SDK_INT >= 24) stopForeground(STOP_FOREGROUND_REMOVE)
        else @Suppress("DEPRECATION") stopForeground(true)
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        Log.i(TAG, "service destroyed")
        super.onDestroy()
    }
}
