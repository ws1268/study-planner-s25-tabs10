package com.example.study_planner_app

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.os.Build
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
                else -> result.notImplemented()
            }
        }
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        // 최대 집중 모드(다른 앱 차단) 중 다른 앱이나 홈 화면으로 이탈 시도 시 즉시 공부 화면으로 복귀
        if (isUltraFocusLocked) {
            val intent = Intent(this, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            }
            startActivity(intent)
        }
    }

    override fun onBackPressed() {
        // 최대 집중 모드 중에는 뒤로가기 버튼으로 앱 종료 차단 (비상 마스터 키로만 해제 가능)
        if (isUltraFocusLocked) {
            return
        }
        super.onBackPressed()
    }
}
