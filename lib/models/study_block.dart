import 'package:flutter/material.dart';

class ChecklistItem {
  final String id;
  final String text;
  final bool isDone;

  const ChecklistItem({
    required this.id,
    required this.text,
    this.isDone = false,
  });

  ChecklistItem copyWith({
    String? id,
    String? text,
    bool? isDone,
  }) {
    return ChecklistItem(
      id: id ?? this.id,
      text: text ?? this.text,
      isDone: isDone ?? this.isDone,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'isDone': isDone,
      };

  factory ChecklistItem.fromJson(Map<String, dynamic> json) {
    return ChecklistItem(
      id: json['id'] as String,
      text: json['text'] as String,
      isDone: json['isDone'] as bool? ?? false,
    );
  }
}

/// 분 단위 자유 시간대 지정이 가능한 학습 블록 모델
/// - [weekdays]: 1(월) ~ 7(일) 반복 요일 목록 (요일별 기본 시간표용)
/// - [specificDate]: 'yyyy-MM-dd' 형식의 특정 날짜 (오늘만의 일일 계획용, null이면 요일 반복)
/// - [autoFocusLock]: 이 스케줄 시작 시간에 자동으로 강제집중(다른 앱 차단)을 실행할지 여부
/// - [lockSyncBothDevices]: 강제집중 시 S25와 탭 S10 Ultra 두 기기를 동시에 잠글지 여부
class StudyBlock {
  final String id;
  final String subject; // 과목명 (예: 수학, 영어, 탐구, 코딩)
  final String title; // 세부 활동/공부 내용 (예: 미적분 기출 3단원 풀이)
  final String memo; // 추가 메모
  final int colorValue; // 과목 색상 ARGB
  final int startMinutes; // 자정(00:00) 기준 시작 분 (예: 09:30 -> 570)
  final int endMinutes; // 자정(00:00) 기준 종료 분 (예: 11:15 -> 675)
  final List<int> weekdays; // 1 = 월요일 ... 7 = 일요일
  final String? specificDate; // 'yyyy-MM-dd' (특정일 전용 계획일 경우 설정)
  final bool notifyOnStart; // 시작 정각 알림 여부
  final int notifyBeforeEndMinutes; // 종료 N분 전 알림 (0이면 끔, 예: 5, 10)
  final List<ChecklistItem> checklist; // 세부 할 일 체크리스트
  final bool autoFocusLock; // 스케줄별 강제집중 모드 활성화 여부
  final bool lockSyncBothDevices; // 강제집중 시 폰+태블릿 동시 잠금 여부

  const StudyBlock({
    required this.id,
    required this.subject,
    required this.title,
    this.memo = '',
    required this.colorValue,
    required this.startMinutes,
    required this.endMinutes,
    this.weekdays = const [],
    this.specificDate,
    this.notifyOnStart = true,
    this.notifyBeforeEndMinutes = 5,
    this.checklist = const [],
    this.autoFocusLock = false,
    this.lockSyncBothDevices = true,
  });

  Color get color => Color(colorValue);

  int get durationMinutes => endMinutes - startMinutes;

  TimeOfDay get startTime =>
      TimeOfDay(hour: startMinutes ~/ 60, minute: startMinutes % 60);

  TimeOfDay get endTime =>
      TimeOfDay(hour: endMinutes ~/ 60, minute: endMinutes % 60);

  String get formattedTimeRange =>
      '${formatMinutes(startMinutes)} ~ ${formatMinutes(endMinutes)}';

  String get formattedDuration {
    final total = durationMinutes;
    final h = total ~/ 60;
    final m = total % 60;
    if (h > 0 && m > 0) return '${h}시간 ${m}분';
    if (h > 0) return '${h}시간';
    return '${m}분';
  }

  static String formatMinutes(int minutes) {
    final h = (minutes ~/ 60).toString().padLeft(2, '0');
    final m = (minutes % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }

  /// 현재 시각(초 단위 포함) 기준으로 진행률(0.0 ~ 1.0) 계산
  double progressAt(DateTime now) {
    final nowSeconds = now.hour * 3600 + now.minute * 60 + now.second;
    final startSeconds = startMinutes * 60;
    final endSeconds = endMinutes * 60;
    if (nowSeconds <= startSeconds) return 0.0;
    if (nowSeconds >= endSeconds) return 1.0;
    return (nowSeconds - startSeconds) / (endSeconds - startSeconds);
  }

  /// 현재 시각 기준 남은 시간(초)
  int remainingSecondsAt(DateTime now) {
    final nowSeconds = now.hour * 3600 + now.minute * 60 + now.second;
    final endSeconds = endMinutes * 60;
    return (endSeconds - nowSeconds).clamp(0, 86400);
  }

  /// 현재 시각이 이 시간 블록 안에 포함되는지 여부
  bool isActiveAt(DateTime now) {
    final nowMinutes = now.hour * 60 + now.minute;
    return nowMinutes >= startMinutes && nowMinutes < endMinutes;
  }

  int get completedChecklistCount =>
      checklist.where((item) => item.isDone).length;

  StudyBlock copyWith({
    String? id,
    String? subject,
    String? title,
    String? memo,
    int? colorValue,
    int? startMinutes,
    int? endMinutes,
    List<int>? weekdays,
    String? specificDate,
    bool clearSpecificDate = false,
    bool? notifyOnStart,
    int? notifyBeforeEndMinutes,
    List<ChecklistItem>? checklist,
    bool? autoFocusLock,
    bool? lockSyncBothDevices,
  }) {
    return StudyBlock(
      id: id ?? this.id,
      subject: subject ?? this.subject,
      title: title ?? this.title,
      memo: memo ?? this.memo,
      colorValue: colorValue ?? this.colorValue,
      startMinutes: startMinutes ?? this.startMinutes,
      endMinutes: endMinutes ?? this.endMinutes,
      weekdays: weekdays ?? this.weekdays,
      specificDate:
          clearSpecificDate ? null : (specificDate ?? this.specificDate),
      notifyOnStart: notifyOnStart ?? this.notifyOnStart,
      notifyBeforeEndMinutes:
          notifyBeforeEndMinutes ?? this.notifyBeforeEndMinutes,
      checklist: checklist ?? this.checklist,
      autoFocusLock: autoFocusLock ?? this.autoFocusLock,
      lockSyncBothDevices: lockSyncBothDevices ?? this.lockSyncBothDevices,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'subject': subject,
        'title': title,
        'memo': memo,
        'colorValue': colorValue,
        'startMinutes': startMinutes,
        'endMinutes': endMinutes,
        'weekdays': weekdays,
        'specificDate': specificDate,
        'notifyOnStart': notifyOnStart,
        'notifyBeforeEndMinutes': notifyBeforeEndMinutes,
        'checklist': checklist.map((e) => e.toJson()).toList(),
        'autoFocusLock': autoFocusLock,
        'lockSyncBothDevices': lockSyncBothDevices,
      };

  factory StudyBlock.fromJson(Map<String, dynamic> json) {
    return StudyBlock(
      id: json['id'] as String,
      subject: json['subject'] as String,
      title: json['title'] as String,
      memo: json['memo'] as String? ?? '',
      colorValue: json['colorValue'] as int,
      startMinutes: json['startMinutes'] as int,
      endMinutes: json['endMinutes'] as int,
      weekdays: (json['weekdays'] as List<dynamic>? ?? [])
          .map((e) => e as int)
          .toList(),
      specificDate: json['specificDate'] as String?,
      notifyOnStart: json['notifyOnStart'] as bool? ?? true,
      notifyBeforeEndMinutes: json['notifyBeforeEndMinutes'] as int? ?? 5,
      checklist: (json['checklist'] as List<dynamic>? ?? [])
          .map((e) => ChecklistItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      autoFocusLock: json['autoFocusLock'] as bool? ?? false,
      lockSyncBothDevices: json['lockSyncBothDevices'] as bool? ?? true,
    );
  }
}
