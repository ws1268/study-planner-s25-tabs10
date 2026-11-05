import 'package:flutter/material.dart';
import '../models/study_block.dart';

class ActiveStudyHeroCard extends StatelessWidget {
  final StudyBlock? currentBlock;
  final StudyBlock? nextBlock;
  final DateTime now;
  final void Function(StudyBlock block, String checklistId) onToggleChecklist;
  final VoidCallback onEditCurrent;
  final VoidCallback onTestNotification;

  const ActiveStudyHeroCard({
    super.key,
    required this.currentBlock,
    required this.nextBlock,
    required this.now,
    required this.onToggleChecklist,
    required this.onEditCurrent,
    required this.onTestNotification,
  });

  String _formatRemainingSeconds(int totalSeconds) {
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final s = totalSeconds % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (currentBlock == null) {
      return _buildIdleHeroCard(context);
    }

    final block = currentBlock!;
    final progress = block.progressAt(now);
    final progressPercent = (progress * 100).round();
    final remainingSecs = block.remainingSecondsAt(now);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            block.color,
            Color.lerp(block.color, Colors.black, 0.28)!,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: block.color.withValues(alpha: 0.35),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 상단 상태 뱃지 & 알림 테스트 / 편집 버튼
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.bolt, color: Colors.amberAccent, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      '지금 해야 할 공부 • ${block.subject}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: '즉시 알림 테스트',
                    onPressed: onTestNotification,
                    icon: const Icon(
                      Icons.notifications_active_outlined,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: '현재 블록 수정',
                    onPressed: onEditCurrent,
                    icon: const Icon(
                      Icons.edit_outlined,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 핵심 공부 제목
          Text(
            block.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
              height: 1.25,
            ),
          ),
          if (block.memo.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              block.memo,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: 13,
              ),
            ),
          ],
          const SizedBox(height: 16),

          // 타이머 & 시간 범위
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '진행 시간대 (${block.formattedDuration})',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.75),
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          block.formattedTimeRange,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '남은 시간 ($progressPercent%)',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.75),
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _formatRemainingSeconds(remainingSecs),
                          style: const TextStyle(
                            color: Colors.amberAccent,
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 10,
                    backgroundColor: Colors.white.withValues(alpha: 0.2),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Colors.amberAccent,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 세부 할 일 체크리스트 (바로 체크 가능)
          if (block.checklist.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              '체크리스트 (${block.completedChecklistCount}/${block.checklist.length} 완료)',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            ...block.checklist.map((item) {
              return InkWell(
                onTap: () => onToggleChecklist(block, item.id),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(
                        item.isDone
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        color: item.isDone
                            ? Colors.amberAccent
                            : Colors.white.withValues(alpha: 0.8),
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          item.text,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            decoration: item.isDone
                                ? TextDecoration.lineThrough
                                : null,
                            decorationColor: Colors.white70,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],

          // 다음 공부 일정 안내
          if (nextBlock != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.upcoming_outlined,
                      color: Colors.white70, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '다음 예정: [${nextBlock!.subject}] ${nextBlock!.title} (${StudyBlock.formatMinutes(nextBlock!.startMinutes)}~)',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildIdleHeroCard(BuildContext context) {
    final nowMinutes = now.hour * 60 + now.minute;
    final minsUntilNext =
        nextBlock != null ? (nextBlock!.startMinutes - nowMinutes) : null;

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: const Text(
                  '☕ 현재 쉬는 시간 / 자유 시간',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: onTestNotification,
                icon: const Icon(Icons.notifications_active_outlined,
                    color: Colors.amberAccent, size: 16),
                label: const Text(
                  '알림 테스트',
                  style: TextStyle(color: Colors.amberAccent, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            nextBlock != null
                ? '다음 공부 시작까지 ${minsUntilNext}분 남았습니다'
                : '지금 진행 중인 공부 블록이 없습니다',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          if (nextBlock != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 38,
                    decoration: BoxDecoration(
                      color: nextBlock!.color,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '[${nextBlock!.subject}] ${nextBlock!.title}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          nextBlock!.formattedTimeRange,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )
          else
            const Text(
              '아래 [+ 공부 시간 추가] 버튼을 눌러 원하는 시간대(분 단위)와 과목·할 일을 자유롭게 만들어보세요!',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
        ],
      ),
    );
  }
}
