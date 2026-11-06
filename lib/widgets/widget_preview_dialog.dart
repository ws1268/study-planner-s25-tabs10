import 'package:flutter/material.dart';
import '../models/study_block.dart';

class WidgetPreviewDialog extends StatelessWidget {
  final StudyBlock? currentBlock;
  final StudyBlock? nextBlock;
  final List<StudyBlock> todayBlocks;
  final List<String> underTargetWarnings;
  final DateTime now;
  final VoidCallback onSyncWidget;

  const WidgetPreviewDialog({
    super.key,
    required this.currentBlock,
    required this.nextBlock,
    required this.todayBlocks,
    required this.underTargetWarnings,
    required this.now,
    required this.onSyncWidget,
  });

  @override
  Widget build(BuildContext context) {
    final progress = currentBlock?.progressAt(now) ?? 0.0;
    final progressPercent = (progress * 100).round();
    final remainingMins = currentBlock != null
        ? (currentBlock!.remainingSecondsAt(now) / 60).ceil()
        : 0;
    final nowMins = now.hour * 60 + now.minute;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      '📱 고가독성 Android 홈 화면 위젯',
                      style:
                          TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  '갤럭시 S25와 탭 S10 Ultra 바탕화면에서 멀리서도 한눈에 읽히도록 글씨 크기와 대비, 카드 구분을 대폭 강화했습니다.',
                  style: TextStyle(fontSize: 12.5, color: Colors.black54),
                ),
                const SizedBox(height: 14),

                // 실제 Android 위젯 레이아웃과 동일한 고가독성 2단 분리 카드
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: currentBlock?.color ?? const Color(0xFF6366F1),
                      width: 2,
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 14,
                        offset: Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 1단: 지금 해야 할 공부 내부 카드
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFF334155)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color:
                                        currentBlock?.color ?? Colors.blueGrey,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    currentBlock?.subject ?? '대기 중',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 13.5,
                                    ),
                                  ),
                                ),
                                Text(
                                  currentBlock != null
                                      ? '🔥 ${remainingMins}분 남음 ($progressPercent%)'
                                      : '☕ 쉬는 시간',
                                  style: const TextStyle(
                                    color: Color(0xFFFDE047),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              currentBlock?.title ??
                                  (nextBlock != null
                                      ? '다음: [${nextBlock!.subject}] ${nextBlock!.title}'
                                      : '오늘 예정된 다음 공부 일정이 없습니다.'),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 17.5,
                                fontWeight: FontWeight.w900,
                                height: 1.25,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              currentBlock != null
                                  ? '⏰ ${currentBlock!.formattedTimeRange} (${currentBlock!.formattedDuration})'
                                  : (nextBlock != null
                                      ? '⏰ ${nextBlock!.formattedTimeRange}'
                                      : '⏰ --:-- ~ --:--'),
                              style: const TextStyle(
                                color: Color(0xFF93C5FD),
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(99),
                              child: LinearProgressIndicator(
                                value: progress,
                                minHeight: 9,
                                backgroundColor: const Color(0xFF334155),
                                valueColor: const AlwaysStoppedAnimation<Color>(
                                  Color(0xFFFDE047),
                                ),
                              ),
                            ),
                            if (currentBlock != null &&
                                currentBlock!.checklist.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                currentBlock!.checklist
                                    .take(2)
                                    .map((c) =>
                                        '${c.isDone ? "☑" : "☐"} ${c.text}')
                                    .join('\n'),
                                style: const TextStyle(
                                  color: Color(0xFFF8FAFC),
                                  fontSize: 12.5,
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),

                      // 2단: 오늘 해야 할 공부 전체 스케줄 카드
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFF334155)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '📋 오늘 해야 할 공부 스케줄',
                              style: TextStyle(
                                color: Color(0xFF38BDF8),
                                fontSize: 12.5,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 6),
                            if (todayBlocks.isEmpty)
                              const Text(
                                '오늘 등록된 공부 일정이 없습니다.',
                                style: TextStyle(
                                    color: Colors.white70, fontSize: 12),
                              )
                            else
                              ...todayBlocks.take(5).map((b) {
                                final String icon;
                                if (nowMins >= b.endMinutes) {
                                  icon = '✅';
                                } else if (nowMins >= b.startMinutes &&
                                    nowMins < b.endMinutes) {
                                  icon = '🔥';
                                } else {
                                  icon = '⏳';
                                }
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 5),
                                  child: Text(
                                    '$icon ${StudyBlock.formatMinutes(b.startMinutes)}~${StudyBlock.formatMinutes(b.endMinutes)}  [${b.subject}] ${b.title}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                );
                              }),
                            if (underTargetWarnings.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                '🚨 주간 목표 미달: ${underTargetWarnings.join(", ")}',
                                style: const TextStyle(
                                  color: Color(0xFFFCA5A5),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      onSyncWidget();
                      Navigator.of(context).pop();
                    },
                    icon: const Icon(Icons.sync),
                    label: const Text('지금 홈 화면 위젯 즉시 동기화'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
