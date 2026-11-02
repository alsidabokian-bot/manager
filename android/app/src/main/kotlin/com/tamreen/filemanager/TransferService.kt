package com.tamreen.filemanager

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

/** يبني إشعار التقدم ويحدّثه. */
object TransferNotifier {
    const val CHANNEL_ID = "transfers"
    const val NOTIFICATION_ID = 4711

    private fun ensureChannel(ctx: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = ctx.getSystemService(NotificationManager::class.java)
            if (nm.getNotificationChannel(CHANNEL_ID) == null) {
                nm.createNotificationChannel(
                    NotificationChannel(
                        CHANNEL_ID,
                        "عمليات النسخ والنقل",
                        NotificationManager.IMPORTANCE_LOW
                    )
                )
            }
        }
    }

    /** progress بين 0 و100، أو سالب لشريط غير محدد. */
    fun build(ctx: Context, title: String, text: String, progress: Int): Notification {
        ensureChannel(ctx)
        @Suppress("DEPRECATION")
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(ctx, CHANNEL_ID)
        } else {
            Notification.Builder(ctx)
        }
        val launch = ctx.packageManager.getLaunchIntentForPackage(ctx.packageName) ?: Intent()
        val pending = PendingIntent.getActivity(
            ctx, 0, launch,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        builder.setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle(title)
            .setContentText(text)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(pending)
        if (progress >= 0) {
            builder.setProgress(100, progress, false)
        } else {
            builder.setProgress(0, 0, true)
        }
        return builder.build()
    }
}

/**
 * خدمة أمامية: وجودها (مع إشعارها) يمنع النظام من إيقاف عملية التطبيق
 * أثناء النسخ عند الخروج منه أو إطفاء الشاشة.
 */
class TransferService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val title = intent?.getStringExtra("title") ?: "جارٍ النسخ"
        val text = intent?.getStringExtra("text") ?: ""
        val notification = TransferNotifier.build(this, title, text, -1)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                TransferNotifier.NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
            )
        } else {
            startForeground(TransferNotifier.NOTIFICATION_ID, notification)
        }
        return START_NOT_STICKY
    }
}
