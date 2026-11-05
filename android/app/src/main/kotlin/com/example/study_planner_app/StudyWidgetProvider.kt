package com.example.study_planner_app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

class StudyWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.study_widget)

            val status = prefs.getString("flutter.widget_status", "🔥 지금 해야 할 공부") ?: "🔥 지금 해야 할 공부"
            val subject = prefs.getString("flutter.widget_subject", "공부 시간표") ?: "공부 시간표"
            val title = prefs.getString("flutter.widget_title", "앱을 열어 나만의 공부 시간표를 설정하세요!") ?: "앱을 열어 나만의 공부 시간표를 설정하세요!"
            val timeRange = prefs.getString("flutter.widget_time_range", "--:-- ~ --:--") ?: "--:-- ~ --:--"
            val progress = prefs.getLong("flutter.widget_progress", 0L).toInt()
            val checklist = prefs.getString("flutter.widget_checklist", "") ?: ""
            val todayList = prefs.getString("flutter.widget_today_list", "오늘 예정된 공부 목록을 불러오는 중...") ?: "오늘 예정된 공부 목록을 불러오는 중..."
            val next = prefs.getString("flutter.widget_next", "🎯 모든 과목 주간 목표 순항 중!") ?: "🎯 모든 과목 주간 목표 순항 중!"

            views.setTextViewText(R.id.widget_status_text, status)
            views.setTextViewText(R.id.widget_subject_badge, subject)
            views.setTextViewText(R.id.widget_title_text, title)
            views.setTextViewText(R.id.widget_time_range_text, timeRange)
            views.setProgressBar(R.id.widget_progress_bar, 100, progress, false)
            views.setTextViewText(R.id.widget_checklist_text, checklist)
            views.setTextViewText(R.id.widget_today_list_text, todayList)
            views.setTextViewText(R.id.widget_next_text, next)

            val openAppIntent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val pendingIntent = PendingIntent.getActivity(
                context,
                0,
                openAppIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.widget_root_container, pendingIntent)

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }

    companion object {
        fun refreshWidgets(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, StudyWidgetProvider::class.java))
            if (ids != null && ids.isNotEmpty()) {
                val intent = Intent(context, StudyWidgetProvider::class.java).apply {
                    action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
                    putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
                }
                context.sendBroadcast(intent)
            }
        }
    }
}
