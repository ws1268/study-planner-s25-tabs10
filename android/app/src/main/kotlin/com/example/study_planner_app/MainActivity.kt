package com.example.study_planner_app

import android.content.ContentProvider
import android.content.ContentValues
import android.content.Intent
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.os.Build
import android.os.ParcelFileDescriptor
import android.provider.OpenableColumns
import android.provider.Settings
import android.view.WindowManager
import android.widget.Toast
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileNotFoundException

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.study_planner_app/focus_lock"
    private var isUltraFocusLocked = false
    private var pendingInstallAfterPermission = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "enableLockTask" -> {
                    isUltraFocusLocked = true
                    runOnUiThread {
                        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        try {
                            startLockTask()
                        } catch (_: Exception) {}
                    }
                    result.success(true)
                }
                "disableLockTask" -> {
                    isUltraFocusLocked = false
                    runOnUiThread {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        try {
                            stopLockTask()
                        } catch (_: Exception) {}
                    }
                    result.success(true)
                }
                "updateHomeWidget" -> {
                    StudyWidgetProvider.refreshWidgets(applicationContext)
                    result.success(true)
                }
                "getCacheApkPath" -> {
                    val file = File(applicationContext.cacheDir, "study_planner_update.apk")
                    result.success(file.absolutePath)
                }
                "installApk" -> {
                    runOnUiThread {
                        triggerApkInstall()
                    }
                    result.success(true)
                }
                "openBrowserUrl" -> {
                    val url = call.argument<String>("url")
                    if (!url.isNullOrEmpty()) {
                        runOnUiThread {
                            try {
                                val browserIntent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
                                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                }
                                startActivity(browserIntent)
                            } catch (_: Exception) {}
                        }
                    }
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun triggerApkInstall() {
        val apkFile = File(applicationContext.cacheDir, "study_planner_update.apk")
        if (!apkFile.exists()) {
            Toast.makeText(this, "다운로드된 업데이트 파일을 찾을 수 없습니다.", Toast.LENGTH_SHORT).show()
            return
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            if (!packageManager.canRequestPackageInstalls()) {
                pendingInstallAfterPermission = true
                Toast.makeText(
                    this,
                    "최초 1회 '이 출처의 앱 허용'을 켜주시면 바로 덮어쓰기 업데이트가 진행됩니다!",
                    Toast.LENGTH_LONG
                ).show()
                try {
                    val permIntent = Intent(
                        Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                        Uri.parse("package:$packageName")
                    ).apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    startActivity(permIntent)
                } catch (_: Exception) {}
                return
            }
        }

        try {
            val apkUri = Uri.parse("content://$packageName.apkprovider/study_planner_update.apk")
            val installIntent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(apkUri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(installIntent)
        } catch (e: Exception) {
            Toast.makeText(this, "설치 창 실행 오류: ${e.message}", Toast.LENGTH_LONG).show()
        }
    }

    override fun onResume() {
        super.onResume()
        if (pendingInstallAfterPermission) {
            pendingInstallAfterPermission = false
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O || packageManager.canRequestPackageInstalls()) {
                triggerApkInstall()
            }
        }
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (isUltraFocusLocked) {
            val intent = Intent(this, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            }
            startActivity(intent)
        }
    }

    override fun onBackPressed() {
        if (isUltraFocusLocked) {
            return
        }
        super.onBackPressed()
    }
}

class ApkUpdateFileProvider : ContentProvider() {
    override fun onCreate(): Boolean = true

    override fun query(
        uri: Uri,
        projection: Array<out String>?,
        selection: String?,
        selectionArgs: Array<out String>?,
        sortOrder: String?
    ): Cursor {
        val ctx = context ?: throw IllegalStateException("Context is null")
        val file = File(ctx.cacheDir, "study_planner_update.apk")
        val cols = projection ?: arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE)
        val values = arrayOfNulls<Any>(cols.size)
        for (i in cols.indices) {
            when (cols[i]) {
                OpenableColumns.DISPLAY_NAME -> values[i] = "study_planner_update.apk"
                OpenableColumns.SIZE -> values[i] = if (file.exists()) file.length() else 0L
            }
        }
        val cursor = MatrixCursor(cols, 1)
        cursor.addRow(values)
        return cursor
    }

    override fun getType(uri: Uri): String = "application/vnd.android.package-archive"

    override fun insert(uri: Uri, values: ContentValues?): Uri? = null
    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int = 0
    override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<out String>?): Int = 0

    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor {
        val ctx = context ?: throw FileNotFoundException("Context is null")
        val file = File(ctx.cacheDir, "study_planner_update.apk")
        if (!file.exists()) {
            throw FileNotFoundException("APK not found at ${file.absolutePath}")
        }
        return ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
    }
}
