package com.example.study_planner_app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin

class StudyWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        val widgetData = HomeWidgetPlugin.getData(context)

        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.study_widget)

            val status = widgetData.getString("widget_status", "🔥 지금 해야 할 공부")
            val subject = widgetData.getString("widget_subject", "공부 시간표")
            val title = widgetData.getString("widget_title", "앱을 열어 나만의 공부 시간표를 설정하세요!")
            val timeRange = widgetData.getString("widget_time_range", "--:-- ~ --:--")
            val progress = widgetData.getInt("widget_progress", 0)
            val checklist = widgetData.getString("widget_checklist", "")
            val todayList = widgetData.getString("widget_today_list", "오늘 예정된 공부 목록을 불러오는 중...")
            val next = widgetData.getString("widget_next", "🎯 모든 과목 주간 목표 순항 중!")

            views.setTextViewText(R.id.widget_status_text, status)
            views.setTextViewText(R.id.widget_subject_badge, subject)
            views.setTextViewText(R.id.widget_title_text, title)
            views.setTextViewText(R.id.widget_time_range_text, timeRange)
            views.setProgressBar(R.id.widget_progress_bar, 100, progress, false)
            views.setTextViewText(R.id.widget_checklist_text, checklist)
            views.setTextViewText(R.id.widget_today_list_text, todayList)
            views.setTextViewText(R.id.widget_next_text, next)

            // 위젯 터치 시 앱 바로 열기
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
}
