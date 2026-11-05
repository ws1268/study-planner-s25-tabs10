import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/study_block.dart';

class WidgetService {
  WidgetService._();
  static final WidgetService instance = WidgetService._();

  static const MethodChannel _channel =
      MethodChannel('com.example.study_planner_app/focus_lock');

  /// Android 홈 화면 위젯 데이터를 최신 상태로 동기화하고 즉시 새로고침합니다.
  /// - 지금 해야 할 공부 + 오늘 해야 할 전체 공부 목록(타임라인) + 주간 목표 미달 과목 안내 포함
  Future<void> updateHomeScreenWidget({
    required StudyBlock? currentBlock,
    required StudyBlock? nextBlock,
    required List<StudyBlock> todayBlocks,
    required List<String> underTargetWarnings,
    required DateTime now,
  }) async {
    if (kIsWeb) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final nowMins = now.hour * 60 + now.minute;

      if (currentBlock != null) {
        final progressPercent = (currentBlock.progressAt(now) * 100).round();
        final remainingMins =
            (currentBlock.remainingSecondsAt(now) / 60).ceil();
        final pendingChecklist = currentBlock.checklist
            .map((item) => '${item.isDone ? "☑" : "☐"} ${item.text}')
            .take(2)
            .join('\n');

        await prefs.setString(
          'widget_status',
          '🔥 지금 공부 중 (${remainingMins}분 남음)',
        );
        await prefs.setString('widget_subject', currentBlock.subject);
        await prefs.setString('widget_title', currentBlock.title);
        await prefs.setString(
          'widget_time_range',
          currentBlock.formattedTimeRange,
        );
        await prefs.setInt('widget_progress', progressPercent);
        await prefs.setString(
          'widget_checklist',
          pendingChecklist.isNotEmpty
              ? pendingChecklist
              : (currentBlock.memo.isNotEmpty
                  ? currentBlock.memo
                  : '집중해서 목표를 달성해보세요!'),
        );
      } else {
        await prefs.setString('widget_status', '☕ 현재 쉬는 시간 / 자유 시간');
        await prefs.setString('widget_subject', '대기 중');
        await prefs.setString(
          'widget_title',
          nextBlock != null
              ? '다음: [${nextBlock.subject}] ${nextBlock.title}'
              : '오늘 예정된 다음 공부 일정이 없습니다.',
        );
        await prefs.setString(
          'widget_time_range',
          nextBlock != null ? nextBlock.formattedTimeRange : '--:-- ~ --:--',
        );
        await prefs.setInt('widget_progress', 0);
        await prefs.setString(
          'widget_checklist',
          nextBlock != null
              ? '${StudyBlock.formatMinutes(nextBlock.startMinutes)} 시작 예정'
              : '앱을 열어 자유롭게 시간표를 추가해보세요!',
        );
      }

      // 📋 오늘 해야 할 전체 공부 리스트 문자열 생성 (위젯 하단 전체 일정 표시)
      final todayListLines = <String>[];
      for (final b in todayBlocks) {
        final String statusIcon;
        if (nowMins >= b.endMinutes) {
          statusIcon = '✅';
        } else if (nowMins >= b.startMinutes && nowMins < b.endMinutes) {
          statusIcon = '🔥';
        } else {
          statusIcon = '⏳';
        }
        todayListLines.add(
          '$statusIcon ${StudyBlock.formatMinutes(b.startMinutes)}~${StudyBlock.formatMinutes(b.endMinutes)} [${b.subject}] ${b.title}',
        );
      }

      final todaySummaryText = todayListLines.isNotEmpty
          ? todayListLines.take(4).join('\n')
          : '오늘 등록된 공부 일정이 없습니다.';

      await prefs.setString('widget_today_list', todaySummaryText);

      // 🚨 주간 목표 미달 과목 경고 텍스트
      final goalWarningText = underTargetWarnings.isNotEmpty
          ? '🚨 주간 목표 미달: ${underTargetWarnings.join(", ")}'
          : '🎯 모든 과목 주간 목표 순항 중!';

      await prefs.setString('widget_next', goalWarningText);

      await _channel.invokeMethod('updateHomeWidget');
    } catch (e) {
      debugPrint('HomeWidget 업데이트 생략/오류: $e');
    }
  }
}
