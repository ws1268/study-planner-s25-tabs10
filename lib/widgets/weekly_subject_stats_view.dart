import 'package:flutter/material.dart';
import '../models/study_block.dart';
import '../models/subject_goal.dart';

class SubjectStatItem {
  final String subject;
  final int colorValue;
  final int totalMinutes;
  final int sessionCount;
  final int targetMinutes;

  const SubjectStatItem({
    required this.subject,
    required this.colorValue,
    required this.totalMinutes,
    required this.sessionCount,
    required this.targetMinutes,
  });

  Color get color => Color(colorValue);

  int get deficitMinutes => (targetMinutes - totalMinutes).clamp(0, 100000);

  bool get isGoalMet => targetMinutes <= 0 || totalMinutes >= targetMinutes;

  double get goalProgress => targetMinutes > 0
      ? (totalMinutes / targetMinutes).clamp(0.0, 1.0)
      : 1.0;

  String get formattedTime => formatMins(totalMinutes);
  String get formattedTarget => formatMins(targetMinutes);
  String get formattedDeficit => formatMins(deficitMinutes);

  static String formatMins(int mins) {
    final h = mins ~/ 60;
    final m = mins % 60;
    if (h > 0 && m > 0) return '${h}시간 ${m}분';
    if (h > 0) return '${h}시간';
    return '${m}분';
  }
}

class WeeklySubjectStatsView extends StatelessWidget {
  final List<StudyBlock> Function(int weekday) getBlocksForWeekday;
  final List<SubjectWeeklyGoal> weeklyGoals;
  final int currentWeekday;
  final void Function(String subject, int newTargetMinutes, int colorValue)
      onUpdateSubjectGoal;
  final void Function(String subject, int deficitMinutes, int colorValue)
      onAssignDeficitBlockToday;
  final void Function(String subject, int deficitMinutes, int colorValue)
      onStartEnforcedFocusNow;

  const WeeklySubjectStatsView({
    super.key,
    required this.getBlocksForWeekday,
    required this.weeklyGoals,
    required this.currentWeekday,
    required this.onUpdateSubjectGoal,
    required this.onAssignDeficitBlockToday,
    required this.onStartEnforcedFocusNow,
  });

  static const List<String> _weekdayLabels = ['월', '화', '수', '목', '금', '토', '일'];

  @override
  Widget build(BuildContext context) {
    final Map<String, SubjectStatItem> subjectMap = {};
    final List<int> dailyMinutes = List.filled(7, 0);
    int grandTotalMinutes = 0;

    // 1) 먼저 목표가 설정된 과목들을 기본 등록
    for (final g in weeklyGoals) {
      subjectMap[g.subject] = SubjectStatItem(
        subject: g.subject,
        colorValue: g.colorValue,
        totalMinutes: 0,
        sessionCount: 0,
        targetMinutes: g.targetMinutes,
      );
    }

    // 2) 월~일 실제 시간표 합산
    for (int day = 1; day <= 7; day++) {
      final dayBlocks = getBlocksForWeekday(day);
      for (final b in dayBlocks) {
        final dur = b.durationMinutes;
        dailyMinutes[day - 1] += dur;
        grandTotalMinutes += dur;

        final prev = subjectMap[b.subject];
        if (prev == null) {
          subjectMap[b.subject] = SubjectStatItem(
            subject: b.subject,
            colorValue: b.colorValue,
            totalMinutes: dur,
            sessionCount: 1,
            targetMinutes: 300, // 기본 주 5시간 목표
          );
        } else {
          subjectMap[b.subject] = SubjectStatItem(
            subject: b.subject,
            colorValue: prev.colorValue,
            totalMinutes: prev.totalMinutes + dur,
            sessionCount: prev.sessionCount + 1,
            targetMinutes: prev.targetMinutes,
          );
        }
      }
    }

    final sortedSubjects = subjectMap.values.toList()
      ..sort((a, b) => b.deficitMinutes.compareTo(a.deficitMinutes));

    final underTargetSubjects =
        sortedSubjects.where((s) => !s.isGoalMet).toList();

    final dailyAvgMinutes = (grandTotalMinutes / 7).round();
    final maxDailyMins =
        dailyMinutes.fold<int>(60, (max, v) => v > max ? v : max);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      children: [
        // 🚨 1. 주간 목표 미달 과목 강제 보충 경고 카드
        if (underTargetSubjects.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.red.shade300, width: 1.8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        color: Colors.red.shade700, size: 22),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '🚨 1주일 목표치 미달 과목 (${underTargetSubjects.length}과목) — 보충 학습 필수!',
                        style: TextStyle(
                          color: Colors.red.shade900,
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '설정한 주간 목표 시간을 채우지 못한 과목입니다. 지금 바로 보충 시간표에 배정하거나 최대 집중 모드로 목표를 달성하세요!',
                  style: TextStyle(
                    color: Colors.red.shade800,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 12),
                ...underTargetSubjects.map((item) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.red.shade100),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: item.color,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                item.subject,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '목표 ${item.formattedTarget} 중 ${item.formattedTime} 계획됨',
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Text(
                              '⚠️ ${item.formattedDeficit} 부족',
                              style: TextStyle(
                                color: Colors.red.shade700,
                                fontWeight: FontWeight.w900,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => onAssignDeficitBlockToday(
                                  item.subject,
                                  item.deficitMinutes.clamp(30, 90),
                                  item.colorValue,
                                ),
                                icon: const Icon(Icons.add_task, size: 16),
                                label: const Text(
                                  '오늘 빈 시간에 보충 배정',
                                  style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w800),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: Colors.red.shade700,
                                ),
                                onPressed: () => onStartEnforcedFocusNow(
                                  item.subject,
                                  item.deficitMinutes.clamp(25, 60),
                                  item.colorValue,
                                ),
                                icon: const Icon(Icons.lock_clock, size: 16),
                                label: const Text(
                                  '지금 강제 집중 시작',
                                  style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w800),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // 2. 주간 총 공부시간 요약 헤더 카드
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF312E81), Color(0xFF4F46E5)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '📊 이번 주 총 계획 공부시간 (월~일)',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    '${grandTotalMinutes ~/ 60}시간 ${grandTotalMinutes % 60}분',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '일평균 ${dailyAvgMinutes ~/ 60}시간 ${dailyAvgMinutes % 60}분',
                    style: const TextStyle(
                      color: Colors.amberAccent,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (grandTotalMinutes > 0) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: SizedBox(
                    height: 14,
                    child: Row(
                      children: sortedSubjects
                          .where((s) => s.totalMinutes > 0)
                          .map((item) {
                        final flex =
                            ((item.totalMinutes / grandTotalMinutes) * 1000)
                                .round()
                                .clamp(1, 1000);
                        return Expanded(
                          flex: flex,
                          child: Container(color: item.color),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 3. 과목별 주간 공부시간 & 목표 달성률 설정 리스트
        const Text(
          '🎯 과목별 1주일 목표치 설정 및 달성 현황',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 10),
        ...sortedSubjects.map((item) {
          final goalPct = (item.goalProgress * 100).round();

          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: item.isGoalMet
                    ? const Color(0xFF059669).withValues(alpha: 0.4)
                    : Colors.red.shade200,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: item.color,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        item.subject,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: item.isGoalMet
                            ? const Color(0xFFECFDF5)
                            : const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        item.isGoalMet
                            ? '✅ 주간 목표 달성 ($goalPct%)'
                            : '⚠️ ${item.formattedDeficit} 부족 ($goalPct%)',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: item.isGoalMet
                              ? const Color(0xFF059669)
                              : Colors.red.shade700,
                        ),
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () =>
                          _showGoalEditDialog(context, item),
                      icon: const Icon(Icons.flag_outlined, size: 15),
                      label: Text(
                        '목표: ${item.formattedTarget}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '현재 주간 계획: ${item.formattedTime} (주 ${item.sessionCount}회)',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '${item.formattedTime} / ${item.formattedTarget}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: item.goalProgress,
                    minHeight: 9,
                    backgroundColor: Colors.grey.shade100,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      item.isGoalMet ? const Color(0xFF059669) : item.color,
                    ),
                  ),
                ),
              ],
            ),
          );
        }),

        const SizedBox(height: 16),

        // 4. 요일별(월~일) 공부시간 밸런스 차트
        const Text(
          '🗓️ 요일별 공부시간 밸런스 (월~일)',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: SizedBox(
            height: 150,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(7, (idx) {
                final mins = dailyMinutes[idx];
                final heightFactor = (mins / maxDailyMins).clamp(0.06, 1.0);
                final isToday = (idx + 1) == currentWeekday;
                final hText = mins >= 60
                    ? '${(mins / 60).toStringAsFixed(1)}h'
                    : '${mins}m';

                return Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      mins > 0 ? hText : '-',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: isToday
                            ? Colors.indigo.shade700
                            : Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: 28,
                      height: 92 * heightFactor,
                      decoration: BoxDecoration(
                        color: isToday
                            ? Colors.indigo.shade600
                            : Colors.indigo.shade200,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _weekdayLabels[idx],
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight:
                            isToday ? FontWeight.w900 : FontWeight.w600,
                        color: isToday
                            ? Colors.indigo.shade700
                            : Colors.black87,
                      ),
                    ),
                  ],
                );
              }),
            ),
          ),
        ),
      ],
    );
  }

  void _showGoalEditDialog(BuildContext context, SubjectStatItem item) {
    int hours = item.targetMinutes ~/ 60;
    int mins = item.targetMinutes % 60;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return AlertDialog(
              title: Text('🎯 [${item.subject}] 1주일 목표 공부시간 설정'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '1주일 동안 이 과목을 최소 몇 시간 공부할지 목표를 정하세요. 미달 시 앱이 자동으로 보충 학습을 안내합니다.',
                    style: TextStyle(fontSize: 12.5, color: Colors.black54),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Column(
                        children: [
                          const Text('시간'),
                          DropdownButton<int>(
                            value: hours.clamp(0, 40),
                            items: List.generate(
                              41,
                              (i) => DropdownMenuItem(
                                value: i,
                                child: Text('${i}시간'),
                              ),
                            ),
                            onChanged: (v) {
                              if (v != null) setModalState(() => hours = v);
                            },
                          ),
                        ],
                      ),
                      Column(
                        children: [
                          const Text('분'),
                          DropdownButton<int>(
                            value: (mins ~/ 10) * 10,
                            items: [0, 10, 20, 30, 40, 50]
                                .map(
                                  (m) => DropdownMenuItem(
                                    value: m,
                                    child: Text('${m}분'),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) {
                              if (v != null) setModalState(() => mins = v);
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('취소'),
                ),
                FilledButton(
                  onPressed: () {
                    final total = (hours * 60 + mins).clamp(30, 3000);
                    onUpdateSubjectGoal(item.subject, total, item.colorValue);
                    Navigator.of(ctx).pop();
                  },
                  child: const Text('목표 저장'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
