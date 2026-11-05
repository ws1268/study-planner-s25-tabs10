import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import '../models/study_block.dart';

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  static const String _channelId = 'study_schedule_channel';
  static const String _channelName = '공부 시간표 알림';
  static const String _channelDesc = '공부 시작 시간 및 종료 전 알림을 제공합니다.';

  static const String _ongoingChannelId = 'study_ongoing_channel';
  static const String _ongoingChannelName = '현재 진행 중인 공부 상태바 표시';

  Future<void> initialize() async {
    if (_initialized || kIsWeb) return;

    tz.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation('Asia/Seoul'));
    } catch (_) {}

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _plugin.initialize(initSettings);

    final androidImplementation =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidImplementation?.requestNotificationsPermission();
    await androidImplementation?.requestExactAlarmsPermission();

    _initialized = true;
  }

  /// 오늘의 시간표 블록들에 대해 시작 정각 알림 & 종료 N분 전 알림을 예약합니다.
  Future<void> rescheduleTodayNotifications(
      List<StudyBlock> todayBlocks) async {
    if (kIsWeb || !_initialized) return;

    await _plugin.cancelAll();

    final now = DateTime.now();

    for (int i = 0; i < todayBlocks.length; i++) {
      final block = todayBlocks[i];

      // 1) 시작 정각 알림 예약
      if (block.notifyOnStart) {
        final startDateTime = DateTime(
          now.year,
          now.month,
          now.day,
          block.startMinutes ~/ 60,
          block.startMinutes % 60,
        );
        if (startDateTime.isAfter(now)) {
          final checklistPreview = block.checklist.isNotEmpty
              ? ' • 할 일: ${block.checklist.map((c) => c.text).join(', ')}'
              : '';
          await _scheduleExactNotification(
            id: 1000 + i * 2,
            scheduledTime: startDateTime,
            title: '📚 [${block.subject}] 지금 시작할 시간입니다!',
            body:
                '${block.formattedTimeRange} | ${block.title}$checklistPreview',
          );
        }
      }

      // 2) 종료 N분 전 알림 예약
      if (block.notifyBeforeEndMinutes > 0 &&
          block.durationMinutes > block.notifyBeforeEndMinutes) {
        final warnMinutes = block.endMinutes - block.notifyBeforeEndMinutes;
        final warnDateTime = DateTime(
          now.year,
          now.month,
          now.day,
          warnMinutes ~/ 60,
          warnMinutes % 60,
        );
        if (warnDateTime.isAfter(now)) {
          await _scheduleExactNotification(
            id: 1000 + i * 2 + 1,
            scheduledTime: warnDateTime,
            title:
                '⏰ [${block.subject}] 종료 ${block.notifyBeforeEndMinutes}분 전입니다!',
            body: '${block.title} 마무리 정리 및 다음 일정을 준비하세요.',
          );
        }
      }
    }
  }

  Future<void> _scheduleExactNotification({
    required int id,
    required DateTime scheduledTime,
    required String title,
    required String body,
  }) async {
    final tzDateTime = tz.TZDateTime.from(scheduledTime, tz.local);

    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      category: AndroidNotificationCategory.reminder,
      visibility: NotificationVisibility.public,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    await _plugin.zonedSchedule(
      id,
      title,
      body,
      tzDateTime,
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  /// 상단 알림창(잠금화면 포함)에 현재 진행 중인 공부와 진행률을 상시 표시
  Future<void> updateOngoingStudyNotification({
    required StudyBlock? currentBlock,
    required StudyBlock? nextBlock,
    required DateTime now,
  }) async {
    if (kIsWeb || !_initialized) return;

    const int ongoingId = 9999;

    if (currentBlock == null) {
      await _plugin.cancel(ongoingId);
      return;
    }

    final remainingMins = (currentBlock.remainingSecondsAt(now) / 60).ceil();
    final progressPercent = (currentBlock.progressAt(now) * 100).round();
    final nextText = nextBlock != null
        ? ' | 다음: ${nextBlock.subject} (${StudyBlock.formatMinutes(nextBlock.startMinutes)})'
        : '';

    final androidDetails = AndroidNotificationDetails(
      _ongoingChannelId,
      _ongoingChannelName,
      channelDescription: '현재 해야 할 공부와 남은 시간을 상단바에 실시간 표시합니다.',
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      autoCancel: false,
      onlyAlertOnce: true,
      showProgress: true,
      maxProgress: 100,
      progress: progressPercent,
    );

    await _plugin.show(
      ongoingId,
      '🔥 지금 공부 중: [${currentBlock.subject}] ${currentBlock.title}',
      '${currentBlock.formattedTimeRange} (남은 시간 약 ${remainingMins}분, $progressPercent%)$nextText',
      NotificationDetails(android: androidDetails),
    );
  }

  /// 즉시 알림 테스트 발송
  Future<void> showTestNotification(StudyBlock? currentBlock) async {
    if (kIsWeb || !_initialized) return;

    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
    );

    final title = currentBlock != null
        ? '📚 [${currentBlock.subject}] 지금 해야 할 공부 알림'
        : '📚 맞춤형 공부 시간표 알림 테스트';
    final body = currentBlock != null
        ? '${currentBlock.formattedTimeRange} — ${currentBlock.title}'
        : '설정한 시작 시간 및 종료 전 알림이 사운드+팝업 토스트로 정상 작동합니다!';

    await _plugin.show(
      8888,
      title,
      body,
      const NotificationDetails(
        android: androidDetails,
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
        ),
      ),
    );
  }
}
