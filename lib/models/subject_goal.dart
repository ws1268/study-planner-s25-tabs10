import 'package:flutter/material.dart';

/// 과목당 1주일 목표 공부 시간 모델
class SubjectWeeklyGoal {
  final String subject;
  final int targetMinutes; // 1주일 목표 공부 시간(분), 예: 600분(10시간)
  final int colorValue;

  const SubjectWeeklyGoal({
    required this.subject,
    required this.targetMinutes,
    required this.colorValue,
  });

  Color get color => Color(colorValue);

  String get formattedTarget {
    final h = targetMinutes ~/ 60;
    final m = targetMinutes % 60;
    if (h > 0 && m > 0) return '${h}시간 ${m}분';
    if (h > 0) return '${h}시간';
    return '${m}분';
  }

  SubjectWeeklyGoal copyWith({
    String? subject,
    int? targetMinutes,
    int? colorValue,
  }) {
    return SubjectWeeklyGoal(
      subject: subject ?? this.subject,
      targetMinutes: targetMinutes ?? this.targetMinutes,
      colorValue: colorValue ?? this.colorValue,
    );
  }

  Map<String, dynamic> toJson() => {
        'subject': subject,
        'targetMinutes': targetMinutes,
        'colorValue': colorValue,
      };

  factory SubjectWeeklyGoal.fromJson(Map<String, dynamic> json) {
    return SubjectWeeklyGoal(
      subject: json['subject'] as String,
      targetMinutes: json['targetMinutes'] as int? ?? 300,
      colorValue: json['colorValue'] as int? ?? 0xFF4F46E5,
    );
  }
}
