import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/study_block.dart';

class PomodoroTimerCard extends StatefulWidget {
  final StudyBlock? currentBlock;
  final String pairingCode;
  final String emergencyMasterKey;
  final void Function(String title, String message, Color color) onPhaseFinished;
  final void Function({
    required int durationSeconds,
    required bool syncBothDevices,
  }) onStartUltraFocusLock;
  final VoidCallback onOpenSecuritySettings;

  const PomodoroTimerCard({
    super.key,
    required this.currentBlock,
    required this.pairingCode,
    required this.emergencyMasterKey,
    required this.onPhaseFinished,
    required this.onStartUltraFocusLock,
    required this.onOpenSecuritySettings,
  });

  @override
  State<PomodoroTimerCard> createState() => _PomodoroTimerCardState();
}

class _PomodoroTimerCardState extends State<PomodoroTimerCard> {
  int _focusMinutes = 25;
  int _breakMinutes = 5;
  bool _isFocusPhase = true;
  bool _isRunning = false;
  int _remainingSeconds = 25 * 60;
  int _completedPomodoros = 0;
  bool _ultraFocusLockMode = true; // 최대 집중 버전 (다른 앱 차단)
  bool _syncBothDevices = true; // S25 + 탭 S10 Ultra 동시 잠금
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _applyPreset(int focusMins, int breakMins) {
    _timer?.cancel();
    setState(() {
      _focusMinutes = focusMins;
      _breakMinutes = breakMins;
      _isFocusPhase = true;
      _isRunning = false;
      _remainingSeconds = focusMins * 60;
    });
  }

  void _toggleStartPause() {
    HapticFeedback.selectionClick();
    if (_isRunning) {
      _timer?.cancel();
      setState(() => _isRunning = false);
    } else {
      // 집중 페이즈이고 '🔒 최대 집중 모드'가 켜져 있으면 전체화면 앱 차단 + 기기 동시 잠금 실행
      if (_isFocusPhase && _ultraFocusLockMode) {
        widget.onStartUltraFocusLock(
          durationSeconds: _remainingSeconds,
          syncBothDevices: _syncBothDevices,
        );
      }

      setState(() => _isRunning = true);
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (_remainingSeconds > 1) {
          setState(() => _remainingSeconds--);
        } else {
          _handlePhaseComplete();
        }
      });
    }
  }

  void _handlePhaseComplete() {
    _timer?.cancel();
    final subj = widget.currentBlock?.subject ?? '집중 공부';

    if (_isFocusPhase) {
      setState(() {
        _completedPomodoros++;
        _isFocusPhase = false;
        _isRunning = false;
        _remainingSeconds = _breakMinutes * 60;
      });
      widget.onPhaseFinished(
        '🍅 뽀모도로 집중 완료! ($_completedPomodoros세트 달성)',
        '[$subj] ${_focusMinutes}분 집중을 마쳤습니다. 앱 잠금이 해제되었습니다!',
        const Color(0xFF059669),
      );
    } else {
      setState(() {
        _isFocusPhase = true;
        _isRunning = false;
        _remainingSeconds = _focusMinutes * 60;
      });
      widget.onPhaseFinished(
        '⚡ 휴식 종료! 다시 집중을 시작할 시간입니다',
        '[$subj] 다음 ${_focusMinutes}분 뽀모도로 세트를 시작해보세요.',
        widget.currentBlock?.color ?? const Color(0xFF4F46E5),
      );
    }
  }

  void _resetTimer() {
    _timer?.cancel();
    setState(() {
      _isRunning = false;
      _remainingSeconds = (_isFocusPhase ? _focusMinutes : _breakMinutes) * 60;
    });
  }

  void _skipPhase() {
    _timer?.cancel();
    setState(() {
      _isRunning = false;
      _isFocusPhase = !_isFocusPhase;
      _remainingSeconds = (_isFocusPhase ? _focusMinutes : _breakMinutes) * 60;
    });
  }

  String _formatMMSS(int secs) {
    final m = (secs ~/ 60).toString().padLeft(2, '0');
    final s = (secs % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final totalSecs = (_isFocusPhase ? _focusMinutes : _breakMinutes) * 60;
    final progress = totalSecs > 0
        ? ((totalSecs - _remainingSeconds) / totalSecs).clamp(0.0, 1.0)
        : 0.0;
    final accentColor = _isFocusPhase
        ? (widget.currentBlock?.color ?? const Color(0xFFE11D48))
        : const Color(0xFF059669);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: _ultraFocusLockMode
              ? Colors.redAccent.withValues(alpha: 0.5)
              : Colors.grey.shade200,
          width: _ultraFocusLockMode ? 1.8 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 상단 헤더 & 완료 세트 배지
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      _isFocusPhase ? '🍅 뽀모도로 집중 타이머' : '☕ 뽀모도로 휴식 타이머',
                      style: TextStyle(
                        color: accentColor,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(color: Colors.amber.shade200),
                    ),
                    child: Text(
                      '오늘 달성: $_completedPomodoros 🍅',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Colors.amber.shade900,
                      ),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: '비상 해제 키 & 기기 연동 설정',
                    onPressed: widget.onOpenSecuritySettings,
                    icon: const Icon(Icons.vpn_key_outlined, size: 18),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),

          // 프리셋 선택 칩
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _presetChip('25분 집중 / 5분 휴식', 25, 5, accentColor),
                const SizedBox(width: 6),
                _presetChip('50분 집중 / 10분 휴식', 50, 10, accentColor),
                const SizedBox(width: 6),
                _presetChip('45분 집중 / 15분 휴식', 45, 15, accentColor),
                const SizedBox(width: 6),
                _presetChip('15분 초집중 / 3분 휴식', 15, 3, accentColor),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // 🔒 최대 집중 모드 (다른 앱 차단 + S25/탭S10 동시 잠금) 설정 박스
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: _ultraFocusLockMode
                  ? const Color(0xFFFEF2F2)
                  : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _ultraFocusLockMode
                    ? Colors.red.shade200
                    : Colors.grey.shade200,
              ),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(
                      _ultraFocusLockMode
                          ? Icons.lock_rounded
                          : Icons.lock_open_rounded,
                      size: 18,
                      color: _ultraFocusLockMode
                          ? Colors.red.shade700
                          : Colors.grey.shade600,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '🔒 최대 집중 버전 (다른 앱 사용 완전 차단)',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 12.5,
                              color: _ultraFocusLockMode
                                  ? Colors.red.shade900
                                  : Colors.black87,
                            ),
                          ),
                          Text(
                            '타이머 종료 전까지 다른 앱 전환 불가 (비상 키로만 해제)',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _ultraFocusLockMode,
                      activeThumbColor: Colors.red.shade700,
                      onChanged: (v) => setState(() => _ultraFocusLockMode = v),
                    ),
                  ],
                ),
                if (_ultraFocusLockMode) ...[
                  const Divider(height: 12),
                  Row(
                    children: [
                      const Icon(
                        Icons.phonelink_lock_rounded,
                        size: 16,
                        color: Colors.indigo,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '갤럭시 S25 + 탭 S10 Ultra 동시 잠금 (코드: ${widget.pairingCode})',
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: Colors.indigo,
                          ),
                        ),
                      ),
                      Checkbox(
                        visualDensity: VisualDensity.compact,
                        value: _syncBothDevices,
                        onChanged: (v) =>
                            setState(() => _syncBothDevices = v ?? true),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),

          // 타이머 숫자 & 컨트롤 버튼
          Row(
            children: [
              SizedBox(
                width: 72,
                height: 72,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 72,
                      height: 72,
                      child: CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 7,
                        backgroundColor: Colors.grey.shade100,
                        valueColor: AlwaysStoppedAnimation<Color>(accentColor),
                      ),
                    ),
                    Text(
                      _formatMMSS(_remainingSeconds),
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isFocusPhase
                          ? (widget.currentBlock?.title ?? '현재 목표에 몰입해 보세요!')
                          : '눈을 감거나 스트레칭하며 뇌를 쉬게 해주세요.',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        FilledButton.icon(
                          onPressed: _toggleStartPause,
                          style: FilledButton.styleFrom(
                            backgroundColor: _ultraFocusLockMode && _isFocusPhase
                                ? Colors.red.shade700
                                : accentColor,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            visualDensity: VisualDensity.compact,
                          ),
                          icon: Icon(
                            _isRunning
                                ? Icons.pause
                                : (_ultraFocusLockMode && _isFocusPhase
                                    ? Icons.lock_clock
                                    : Icons.play_arrow),
                            size: 17,
                          ),
                          label: Text(
                            _isRunning
                                ? '일시정지'
                                : (_ultraFocusLockMode && _isFocusPhase
                                    ? '최대 집중 잠금 시작'
                                    : '시작'),
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        IconButton.filledTonal(
                          visualDensity: VisualDensity.compact,
                          tooltip: '타이머 리셋',
                          onPressed: _resetTimer,
                          icon: const Icon(Icons.replay, size: 17),
                        ),
                        IconButton.filledTonal(
                          visualDensity: VisualDensity.compact,
                          tooltip: _isFocusPhase ? '휴식으로 넘기기' : '집중으로 넘기기',
                          onPressed: _skipPhase,
                          icon: const Icon(Icons.skip_next, size: 17),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _presetChip(String label, int fMins, int bMins, Color accent) {
    final selected = _focusMinutes == fMins && _breakMinutes == bMins;
    return InkWell(
      onTap: () => _applyPreset(fMins, bMins),
      borderRadius: BorderRadius.circular(99),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color:
              selected ? accent.withValues(alpha: 0.14) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(
            color: selected ? accent : Colors.grey.shade300,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            color: selected ? accent : Colors.grey.shade700,
          ),
        ),
      ),
    );
  }
}
