import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/study_block.dart';

class PomodoroTimerCard extends StatefulWidget {
  final StudyBlock? currentBlock;
  final String pairingCode;
  final String emergencyMasterKey;
  final int completedPomodoros;
  final void Function(String title, String message, Color color) onPhaseFinished;
  final void Function(String subject, int completedFocusMinutes)
      onPomodoroSessionCompleted;
  final void Function({
    required String subject,
    required String title,
    required Color color,
    required int durationSeconds,
    required bool syncBothDevices,
  }) onStartUltraFocusLock;
  final VoidCallback onOpenSecuritySettings;

  const PomodoroTimerCard({
    super.key,
    required this.currentBlock,
    required this.pairingCode,
    required this.emergencyMasterKey,
    required this.completedPomodoros,
    required this.onPhaseFinished,
    required this.onPomodoroSessionCompleted,
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

  // 시간표 외에 사용자가 직접 정한 과목/목표 (null이면 현재 시간표 블록과 자동 연동)
  String? _customSubject;
  String? _customGoalTitle;
  int _customColorValue = 0xFFE11D48;

  bool _ultraFocusLockMode = true; // 최대 집중 버전 (다른 앱 차단)
  bool _syncBothDevices = true; // S25 + 탭 S10 Ultra 동시 잠금
  Timer? _timer;

  static const List<String> _subjectPresets = [
    '수학',
    '영어',
    '국어',
    '탐구',
    '코딩',
    '자격증',
    '자습',
  ];

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _effectiveSubject =>
      _customSubject ?? widget.currentBlock?.subject ?? '자유 집중';

  String get _effectiveTitle =>
      (_customGoalTitle != null && _customGoalTitle!.isNotEmpty)
          ? _customGoalTitle!
          : (widget.currentBlock?.title ?? '$_effectiveSubject 집중 학습');

  Color get _effectiveColor => _customSubject != null
      ? Color(_customColorValue)
      : (widget.currentBlock?.color ?? const Color(0xFFE11D48));

  void _applyPreset(int focusMins, int breakMins) {
    _timer?.cancel();
    setState(() {
      _focusMinutes = focusMins.clamp(1, 240);
      _breakMinutes = breakMins.clamp(1, 90);
      _isFocusPhase = true;
      _isRunning = false;
      _remainingSeconds = _focusMinutes * 60;
    });
  }

  void _adjustDurationMinutes(int delta) {
    if (_isRunning) return;
    setState(() {
      if (_isFocusPhase) {
        _focusMinutes = (_focusMinutes + delta).clamp(1, 240);
        _remainingSeconds = _focusMinutes * 60;
      } else {
        _breakMinutes = (_breakMinutes + delta).clamp(1, 90);
        _remainingSeconds = _breakMinutes * 60;
      }
    });
  }

  /// 시간표와 별개로 내가 원하는 집중/휴식 시간(분)과 과목·할 일을 자유롭게 설정하는 모달
  void _openCustomPomodoroDialog() {
    final focusCtrl = TextEditingController(text: _focusMinutes.toString());
    final breakCtrl = TextEditingController(text: _breakMinutes.toString());
    final subjCtrl = TextEditingController(text: _customSubject ?? '');
    final titleCtrl = TextEditingController(text: _customGoalTitle ?? '');
    bool useCustomSubj = _customSubject != null;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return AlertDialog(
              title: const Text(
                '🍅 나만의 뽀모도로 시간 & 과목 설정',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '1. 집중 시간 & 휴식 시간 직접 입력 (분 단위)',
                      style:
                          TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: focusCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: '집중 시간(분)',
                              suffixText: '분',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: breakCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: '휴식 시간(분)',
                              suffixText: '분',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      '2. 공부할 과목 설정 (시간표 외 자유 선택 가능)',
                      style:
                          TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: const Text(
                        '시간표와 별개로 내가 할 과목 직접 지정',
                        style: TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w700),
                      ),
                      subtitle: const Text(
                        '완료 시 해당 과목의 주간 공부시간 및 목표에 자동 합산됩니다.',
                        style: TextStyle(fontSize: 11),
                      ),
                      value: useCustomSubj,
                      onChanged: (v) => setModalState(() => useCustomSubj = v),
                    ),
                    if (useCustomSubj) ...[
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: _subjectPresets.map((s) {
                          return ActionChip(
                            label:
                                Text(s, style: const TextStyle(fontSize: 12)),
                            visualDensity: VisualDensity.compact,
                            onPressed: () {
                              setModalState(() => subjCtrl.text = s);
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: subjCtrl,
                        decoration: const InputDecoration(
                          labelText: '과목명 (예: 수학, 영어, 코딩)',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: titleCtrl,
                        decoration: const InputDecoration(
                          labelText: '이번 뽀모도로 목표 (선택)',
                          hintText: '예: 미적분 오답 10문제 완벽 정리',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('취소'),
                ),
                FilledButton(
                  onPressed: () {
                    final f = int.tryParse(focusCtrl.text.trim()) ?? 25;
                    final b = int.tryParse(breakCtrl.text.trim()) ?? 5;
                    setState(() {
                      if (useCustomSubj && subjCtrl.text.trim().isNotEmpty) {
                        _customSubject = subjCtrl.text.trim();
                        _customGoalTitle = titleCtrl.text.trim();
                      } else {
                        _customSubject = null;
                        _customGoalTitle = null;
                      }
                    });
                    _applyPreset(f, b);
                    Navigator.of(ctx).pop();
                  },
                  child: const Text('적용하기'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _toggleStartPause() {
    HapticFeedback.selectionClick();
    if (_isRunning) {
      _timer?.cancel();
      setState(() => _isRunning = false);
    } else {
      if (_isFocusPhase && _ultraFocusLockMode) {
        widget.onStartUltraFocusLock(
          subject: _effectiveSubject,
          title: _effectiveTitle,
          color: _effectiveColor,
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
    final subj = _effectiveSubject;

    if (_isFocusPhase) {
      final completedMins = _focusMinutes;
      setState(() {
        _isFocusPhase = false;
        _isRunning = false;
        _remainingSeconds = _breakMinutes * 60;
      });
      widget.onPomodoroSessionCompleted(subj, completedMins);
      widget.onPhaseFinished(
        '🍅 뽀모도로 집중 완료! (+$completedMins분 기록됨)',
        '[$subj] ${_focusMinutes}분 집중 달성! 주간 공부 통계에 반영되었으며 앱 잠금이 해제되었습니다.',
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
        _effectiveColor,
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
    final accentColor =
        _isFocusPhase ? _effectiveColor : const Color(0xFF059669);

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
              Flexible(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    _isFocusPhase
                        ? '🍅 뽀모도로 집중 • $_effectiveSubject (${_focusMinutes}분)'
                        : '☕ 뽀모도로 휴식 (${_breakMinutes}분)',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: accentColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
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
                      '오늘 달성: ${widget.completedPomodoros} 🍅',
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

          // 프리셋 + [⚙️ 내 마음대로 시간/과목 설정] 버튼
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ActionChip(
                  avatar: Icon(Icons.tune, size: 15, color: accentColor),
                  label: Text(
                    '내 마음대로 시간·과목 설정',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w900,
                      color: accentColor,
                    ),
                  ),
                  backgroundColor: accentColor.withValues(alpha: 0.1),
                  side: BorderSide(color: accentColor),
                  visualDensity: VisualDensity.compact,
                  onPressed: _openCustomPomodoroDialog,
                ),
                const SizedBox(width: 6),
                _presetChip('25/5분', 25, 5, accentColor),
                const SizedBox(width: 6),
                _presetChip('50/10분', 50, 10, accentColor),
                const SizedBox(width: 6),
                _presetChip('45/15분', 45, 15, accentColor),
                const SizedBox(width: 6),
                _presetChip('60/10분', 60, 10, accentColor),
                const SizedBox(width: 6),
                _presetChip('90/15분', 90, 15, accentColor),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // 빠른 분 단위 미세 조절 바 (-5분 / -1분 / +1분 / +5분 / +10분)
          if (!_isRunning)
            Row(
              children: [
                Text(
                  _isFocusPhase ? '집중 시간 직접 조절:' : '휴식 시간 직접 조절:',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey.shade700,
                  ),
                ),
                const Spacer(),
                _quickStepBtn('-5분', () => _adjustDurationMinutes(-5)),
                const SizedBox(width: 4),
                _quickStepBtn('-1분', () => _adjustDurationMinutes(-1)),
                const SizedBox(width: 4),
                _quickStepBtn('+1분', () => _adjustDurationMinutes(1)),
                const SizedBox(width: 4),
                _quickStepBtn('+5분', () => _adjustDurationMinutes(5)),
                const SizedBox(width: 4),
                _quickStepBtn('+10분', () => _adjustDurationMinutes(10)),
              ],
            ),
          const SizedBox(height: 10),

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
              GestureDetector(
                onTap: _openCustomPomodoroDialog,
                child: SizedBox(
                  width: 74,
                  height: 74,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 74,
                        height: 74,
                        child: CircularProgressIndicator(
                          value: progress,
                          strokeWidth: 7,
                          backgroundColor: Colors.grey.shade100,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(accentColor),
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _formatMMSS(_remainingSeconds),
                            style: const TextStyle(
                              fontSize: 16.5,
                              fontWeight: FontWeight.w900,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                          Text(
                            '시간변경',
                            style: TextStyle(
                              fontSize: 9.5,
                              color: Colors.grey.shade500,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _isFocusPhase
                                ? '[$_effectiveSubject] $_effectiveTitle'
                                : '눈을 감거나 스트레칭하며 뇌를 쉬게 해주세요.',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        if (_customSubject != null)
                          InkWell(
                            onTap: () => setState(() {
                              _customSubject = null;
                              _customGoalTitle = null;
                            }),
                            child: Padding(
                              padding: const EdgeInsets.only(left: 4),
                              child: Text(
                                '시간표연동 복귀',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  color: Colors.indigo.shade600,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                      ],
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

  Widget _quickStepBtn(String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800),
        ),
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
