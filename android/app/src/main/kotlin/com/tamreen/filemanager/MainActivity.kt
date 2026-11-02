package com.tamreen.filemanager

import android.Manifest
import android.app.NotificationManager
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.PowerManager
import android.os.StatFs
import android.provider.Settings
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val channelName = "com.tamreen.filemanager/storage"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "hasAccess" -> result.success(hasAccess())
                    "requestAccess" -> {
                        requestAccess()
                        result.success(null)
                    }
                    "roots" -> result.success(roots())
                    "diskSpace" -> {
                        val path = call.argument<String>("path")
                        if (path == null) {
                            result.error("ARG", "path is required", null)
                        } else {
                            try {
                                val stat = StatFs(path)
                                result.success(
                                    mapOf(
                                        "total" to stat.totalBytes,
                                        "free" to stat.availableBytes
                                    )
                                )
                            } catch (e: Exception) {
                                result.error("STAT", e.message, null)
                            }
                        }
                    }
                    "startService" -> {
                        askNotificationPermission()
                        val intent = Intent(this, TransferService::class.java)
                            .putExtra("title", call.argument<String>("title") ?: "")
                            .putExtra("text", call.argument<String>("text") ?: "")
                        try {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                startForegroundService(intent)
                            } else {
                                startService(intent)
                            }
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("SERVICE", e.message, null)
                        }
                    }
                    "updateNotification" -> {
                        val n = TransferNotifier.build(
                            this,
                            call.argument<String>("title") ?: "",
                            call.argument<String>("text") ?: "",
                            call.argument<Int>("progress") ?: -1
                        )
                        getSystemService(NotificationManager::class.java)
                            .notify(TransferNotifier.NOTIFICATION_ID, n)
                        result.success(null)
                    }
                    "stopService" -> {
                        stopService(Intent(this, TransferService::class.java))
                        getSystemService(NotificationManager::class.java)
                            .cancel(TransferNotifier.NOTIFICATION_ID)
                        result.success(null)
                    }
                    "isIgnoringBattery" -> {
                        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                        result.success(pm.isIgnoringBatteryOptimizations(packageName))
                    }
                    "requestIgnoreBattery" -> {
                        try {
                            startActivity(
                                Intent(
                                    Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                                    Uri.parse("package:$packageName")
                                )
                            )
                        } catch (e: Exception) {
                            startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                        }
                        result.success(null)
                    }
                    "openFile" -> {
                        val path = call.argument<String>("path")
                        if (path == null || !File(path).exists()) {
                            result.error("NOT_FOUND", "الملف غير موجود", null)
                        } else {
                            try {
                                val intent = Intent(Intent.ACTION_VIEW)
                                    .setDataAndType(uriFor(path), mimeOf(path))
                                    .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                startActivity(intent)
                                result.success(true)
                            } catch (e: ActivityNotFoundException) {
                                result.error("NO_APP", "لا يوجد تطبيق يفتح هذا النوع من الملفات", null)
                            } catch (e: Exception) {
                                result.error("OPEN", e.message, null)
                            }
                        }
                    }
                    "shareFiles" -> {
                        val paths = call.argument<List<String>>("paths") ?: emptyList()
                        val files = paths.filter { File(it).isFile }
                        if (files.isEmpty()) {
                            result.error("NO_FILES", "لا توجد ملفات للمشاركة", null)
                        } else {
                            try {
                                val uris = ArrayList(files.map { uriFor(it) })
                                val intent = if (uris.size == 1) {
                                    Intent(Intent.ACTION_SEND)
                                        .putExtra(Intent.EXTRA_STREAM, uris[0])
                                        .setType(mimeOf(files[0]))
                                } else {
                                    Intent(Intent.ACTION_SEND_MULTIPLE)
                                        .putParcelableArrayListExtra(Intent.EXTRA_STREAM, uris)
                                        .setType(commonMime(files))
                                }
                                intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                startActivity(Intent.createChooser(intent, "مشاركة"))
                                result.success(true)
                            } catch (e: Exception) {
                                result.error("SHARE", e.message, null)
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // أندرويد 11 فما فوق: إذن "الوصول إلى كل الملفات"، وقبله: إذن التخزين العادي.
    private fun hasAccess(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Environment.isExternalStorageManager()
        } else {
            checkSelfPermission(Manifest.permission.READ_EXTERNAL_STORAGE) ==
                PackageManager.PERMISSION_GRANTED &&
                checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) ==
                PackageManager.PERMISSION_GRANTED
        }
    }

    private fun requestAccess() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            try {
                startActivity(
                    Intent(
                        Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                        Uri.parse("package:$packageName")
                    )
                )
            } catch (e: Exception) {
                startActivity(Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION))
            }
        } else {
            requestPermissions(
                arrayOf(
                    Manifest.permission.READ_EXTERNAL_STORAGE,
                    Manifest.permission.WRITE_EXTERNAL_STORAGE
                ),
                1001
            )
        }
    }

    // أندرويد 13 فما فوق: إذن عرض الإشعارات (الخدمة تعمل حتى لو رُفض).
    private fun askNotificationPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1002)
        }
    }

    private fun uriFor(path: String) =
        FileProvider.getUriForFile(this, "$packageName.fileprovider", File(path))

    private fun mimeOf(path: String): String {
        val ext = File(path).extension.lowercase()
        return MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext) ?: "*/*"
    }

    // نوع مشترك لعدة ملفات: نفس النوع، أو النوع الرئيسي (image/*)، أو الكل.
    private fun commonMime(files: List<String>): String {
        val types = files.map { mimeOf(it) }.toSet()
        if (types.size == 1) return types.first()
        val majors = types.map { it.substringBefore('/') }.toSet()
        return if (majors.size == 1) "${majors.first()}/*" else "*/*"
    }

    @Suppress("DEPRECATION")
    private fun roots(): Map<String, String> {
        fun pub(type: String) = Environment.getExternalStoragePublicDirectory(type).absolutePath
        return mapOf(
            "internal" to Environment.getExternalStorageDirectory().absolutePath,
            "downloads" to pub(Environment.DIRECTORY_DOWNLOADS),
            "pictures" to pub(Environment.DIRECTORY_PICTURES),
            "dcim" to pub(Environment.DIRECTORY_DCIM),
            "documents" to pub(Environment.DIRECTORY_DOCUMENTS),
            "music" to pub(Environment.DIRECTORY_MUSIC),
            "movies" to pub(Environment.DIRECTORY_MOVIES)
        )
    }
}
