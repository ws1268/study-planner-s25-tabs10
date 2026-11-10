package com.example.study_planner_app

import android.Manifest
import android.app.Activity
import android.content.ClipData
import android.content.ContentProvider
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.database.Cursor
import android.database.MatrixCursor
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import android.os.ParcelFileDescriptor
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.provider.Settings
import android.view.WindowManager
import android.widget.Toast
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileNotFoundException
import java.io.FileOutputStream
import kotlin.math.max

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.study_planner_app/focus_lock"
    private var isUltraFocusLocked = false
    private var pendingInstallAfterPermission = false
    private var pendingImageResult: MethodChannel.Result? = null

    companion object {
        private const val REQ_CAMERA_CAPTURE = 9001
        private const val REQ_GALLERY_PICK = 9002
        private const val REQ_CAMERA_PERMISSION = 9003
    }

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
                "pickPlannerImage" -> {
                    val source = call.argument<String>("source") ?: "camera"
                    pendingImageResult = result
                    runOnUiThread {
                        if (source == "camera") {
                            startCameraFlow()
                        } else {
                            startGalleryFlow()
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun startCameraFlow() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            if (checkSelfPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
                requestPermissions(arrayOf(Manifest.permission.CAMERA), REQ_CAMERA_PERMISSION)
                return
            }
        }
        launchCameraIntent()
    }

    private fun launchCameraIntent() {
        try {
            val photoFile = File(applicationContext.cacheDir, "scanned_planner.jpg")
            if (photoFile.exists()) {
                photoFile.delete()
            }
            photoFile.createNewFile()

            val photoUri = Uri.parse("content://$packageName.apkprovider/scanned_planner.jpg")
            val intent = Intent(MediaStore.ACTION_IMAGE_CAPTURE).apply {
                putExtra(MediaStore.EXTRA_OUTPUT, photoUri)
                clipData = ClipData.newRawUri("", photoUri)
                addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION or Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            startActivityForResult(intent, REQ_CAMERA_CAPTURE)
        } catch (e: Exception) {
            Toast.makeText(this, "카메라 실행 실패 (${e.message}), 갤러리 선택으로 전환합니다.", Toast.LENGTH_SHORT).show()
            startGalleryFlow()
        }
    }

    private fun startGalleryFlow() {
        try {
            val intent = Intent(Intent.ACTION_GET_CONTENT).apply {
                type = "image/*"
                addCategory(Intent.CATEGORY_OPENABLE)
            }
            startActivityForResult(Intent.createChooser(intent, "손글씨 플래너 사진 선택"), REQ_GALLERY_PICK)
        } catch (e: Exception) {
            val res = pendingImageResult
            pendingImageResult = null
            res?.success(null)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQ_CAMERA_PERMISSION) {
            if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                launchCameraIntent()
            } else {
                Toast.makeText(this, "카메라 권한이 거부되어 갤러리 사진 선택으로 이동합니다.", Toast.LENGTH_SHORT).show()
                startGalleryFlow()
            }
        }
    }

    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQ_CAMERA_CAPTURE && requestCode != REQ_GALLERY_PICK) return

        val callback = pendingImageResult
        pendingImageResult = null

        if (resultCode != Activity.RESULT_OK) {
            callback?.success(null)
            return
        }

        val outFile = File(applicationContext.cacheDir, "scanned_planner.jpg")
        try {
            if (requestCode == REQ_CAMERA_CAPTURE) {
                if (!outFile.exists() || outFile.length() == 0L) {
                    val bmp = data?.extras?.get("data") as? Bitmap
                    if (bmp != null) {
                        FileOutputStream(outFile).use { fos ->
                            bmp.compress(Bitmap.CompressFormat.JPEG, 90, fos)
                        }
                    }
                }
            } else if (requestCode == REQ_GALLERY_PICK) {
                val uri = data?.data
                if (uri != null) {
                    contentResolver.openInputStream(uri)?.use { input ->
                        FileOutputStream(outFile).use { output ->
                            input.copyTo(output)
                        }
                    }
                }
            }

            if (outFile.exists() && outFile.length() > 0L) {
                optimizeImageFile(outFile)
                callback?.success(outFile.absolutePath)
            } else {
                callback?.success(null)
            }
        } catch (e: Exception) {
            callback?.success(if (outFile.exists()) outFile.absolutePath else null)
        }
    }

    private fun optimizeImageFile(file: File) {
        try {
            val boundsOpts = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(file.absolutePath, boundsOpts)
            val w = boundsOpts.outWidth
            val h = boundsOpts.outHeight
            if (w <= 0 || h <= 0) return

            var sampleSize = 1
            val maxDim = max(w, h)
            while (maxDim / sampleSize > 1600) {
                sampleSize *= 2
            }

            val decodeOpts = BitmapFactory.Options().apply { inSampleSize = sampleSize }
            val bmp = BitmapFactory.decodeFile(file.absolutePath, decodeOpts) ?: return
            FileOutputStream(file).use { fos ->
                bmp.compress(Bitmap.CompressFormat.JPEG, 84, fos)
            }
            bmp.recycle()
        } catch (_: Exception) {}
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

    private fun resolveTargetFile(uri: Uri): File {
        val ctx = context ?: throw IllegalStateException("Context is null")
        val path = uri.path ?: ""
        return if (path.endsWith(".jpg")) {
            File(ctx.cacheDir, "scanned_planner.jpg")
        } else {
            File(ctx.cacheDir, "study_planner_update.apk")
        }
    }

    override fun query(
        uri: Uri,
        projection: Array<out String>?,
        selection: String?,
        selectionArgs: Array<out String>?,
        sortOrder: String?
    ): Cursor {
        val file = resolveTargetFile(uri)
        val cols = projection ?: arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE)
        val values = arrayOfNulls<Any>(cols.size)
        for (i in cols.indices) {
            when (cols[i]) {
                OpenableColumns.DISPLAY_NAME -> values[i] = file.name
                OpenableColumns.SIZE -> values[i] = if (file.exists()) file.length() else 0L
            }
        }
        val cursor = MatrixCursor(cols, 1)
        cursor.addRow(values)
        return cursor
    }

    override fun getType(uri: Uri): String {
        val path = uri.path ?: ""
        return if (path.endsWith(".jpg")) {
            "image/jpeg"
        } else {
            "application/vnd.android.package-archive"
        }
    }

    override fun insert(uri: Uri, values: ContentValues?): Uri? = null
    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int = 0
    override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<out String>?): Int = 0

    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor {
        val file = resolveTargetFile(uri)
        if (mode.contains("w")) {
            if (!file.exists()) {
                file.createNewFile()
            }
            return ParcelFileDescriptor.open(
                file,
                ParcelFileDescriptor.MODE_CREATE or
                    ParcelFileDescriptor.MODE_READ_WRITE or
                    ParcelFileDescriptor.MODE_TRUNCATE
            )
        }
        if (!file.exists()) {
            throw FileNotFoundException("File not found at ${file.absolutePath}")
        }
        return ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
    }
}
