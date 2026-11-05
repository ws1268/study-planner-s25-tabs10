package com.example.study_planner_app

import android.content.Intent
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.study_planner_app/focus_lock"
    private var isUltraFocusLocked = false

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
                else -> result.notImplemented()
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
