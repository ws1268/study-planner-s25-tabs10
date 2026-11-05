import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/study_block.dart';

class UltraFocusLockOverlay extends StatefulWidget {
  final String subject;
  final String title;
  final Color accentColor;
  final int remainingSeconds;
  final int totalSeconds;
  final String pairingCode;
  final bool syncBothDevices;
  final String emergencyMasterKey;
  final StudyBlock? activeBlock;
  final void Function(StudyBlock block, String checklistId)? onToggleChecklist;
  final VoidCallback onEmergencyUnlockSuccess;

  const UltraFocusLockOverlay({
    super.key,
    required this.subject,
    required this.title,
    required this.accentColor,
    required this.remainingSeconds,
    required this.totalSeconds,
    required this.pairingCode,
    required this.syncBothDevices,
    required this.emergencyMasterKey,
    this.activeBlock,
    this.onToggleChecklist,
    required this.onEmergencyUnlockSuccess,
  });

  @override
  State<UltraFocusLockOverlay> createState() => _UltraFocusLockOverlayState();
}

class _UltraFocusLockOverlayState extends State<UltraFocusLockOverlay> {
  bool _showKeyInput = false;
  final TextEditingController _keyController = TextEditingController();
  String? _errorText;
  int _blockedAttemptCount = 0;

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  String _formatMMSS(int secs) {
    final m = (secs ~/ 60).toString().padLeft(2, '0');
    final s = (secs % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _verifyEmergencyKey() {
    final entered = _keyController.text.trim();
    if (entered == widget.emergencyMasterKey.trim()) {
      HapticFeedback.heavyImpact();
      widget.onEmergencyUnlockSuccess();
    } else {
      HapticFeedback.vibrate();
      setState(() {
        _errorText = '비상 해제 키가 일치하지 않습니다! 다시 집중하세요.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = widget.totalSeconds > 0
        ? ((widget.totalSeconds - widget.remainingSeconds) /
                widget.totalSeconds)
            .clamp(0.0, 1.0)
        : 0.0;
    final progressPct = (progress * 100).round();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          HapticFeedback.vibrate();
          setState(() => _blockedAttemptCount++);
        }
      },
      child: Material(
        color: const Color(0xFF070B14),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 540),
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 24,
                ),
                shrinkWrap: true,
                children: [
                  // 상단 잠금 경고 배지
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(
                          color: Colors.redAccent.withValues(alpha: 0.5),
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.lock_rounded,
                            color: Colors.redAccent,
                            size: 16,
                          ),
                          SizedBox(width: 6),
                          Text(
                            '최대 집중 모드 작동 중 • 다른 앱 사용 차단됨',
                            style: TextStyle(
                              color: Colors.redAccent,
                              fontWeight: FontWeight.w900,
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // S25 <-> Tab S10 Ultra 동시 잠금 배지
                  if (widget.syncBothDevices)
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.indigo.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          '🔗 갤럭시 S25 ↔ 갤럭시 탭 S10 Ultra 동시 앱 잠금 연동 중 (코드: ${widget.pairingCode})',
                          style: const TextStyle(
                            color: Colors.amberAccent,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),

                  if (_blockedAttemptCount > 0) ...[
                    const SizedBox(height: 8),
                    Center(
                      child: Text(
                        '🚫 이탈 시도가 $_blockedAttemptCount회 차단되었습니다. 타이머 종료까지 다른 앱을 열 수 없습니다.',
                        style: const TextStyle(
                          color: Colors.orangeAccent,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),

                  // 과목 및 공부 제목
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: widget.accentColor,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        widget.subject,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    widget.title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 28),

                  // 대형 원형 프로그레스 타이머
                  Center(
                    child: SizedBox(
                      width: 220,
                      height: 220,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            width: 220,
                            height: 220,
                            child: CircularProgressIndicator(
                              value: progress,
                              strokeWidth: 12,
                              backgroundColor: Colors.white12,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                widget.accentColor,
                              ),
                            ),
                          ),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '잠금 해제까지 ($progressPct%)',
                                style: const TextStyle(
                                  color: Colors.white60,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _formatMMSS(widget.remainingSeconds),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 48,
                                  fontWeight: FontWeight.w900,
                                  fontFeatures: [FontFeature.tabularFigures()],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // 현재 공부 블록 체크리스트 (잠금 화면 안에서도 체크 가능)
                  if (widget.activeBlock != null &&
                      widget.activeBlock!.checklist.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '📋 지금 달성해야 할 체크리스트',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ...widget.activeBlock!.checklist.map((item) {
                            return InkWell(
                              onTap: () => widget.onToggleChecklist
                                  ?.call(widget.activeBlock!, item.id),
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 5),
                                child: Row(
                                  children: [
                                    Icon(
                                      item.isDone
                                          ? Icons.check_circle
                                          : Icons.radio_button_unchecked,
                                      color: item.isDone
                                          ? Colors.amberAccent
                                          : Colors.white54,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        item.text,
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                          decoration: item.isDone
                                              ? TextDecoration.lineThrough
                                              : null,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // 예측하지 못한 긴급 상황을 위한 비상 마스터 키 입력 영역
                  if (!_showKeyInput)
                    Center(
                      child: TextButton.icon(
                        onPressed: () {
                          setState(() {
                            _showKeyInput = true;
                            _errorText = null;
                          });
                        },
                        icon: const Icon(
                          Icons.vpn_key_outlined,
                          color: Colors.white54,
                          size: 16,
                        ),
                        label: const Text(
                          '긴급 상황 발생 시 비상 마스터 키로 잠금 해제',
                          style: TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.amberAccent),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '🔑 비상 마스터 키 입력 (S25 & 탭 S10 Ultra 동시 잠금 해제)',
                            style: TextStyle(
                              color: Colors.amberAccent,
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            '예측하지 못한 긴급 상황일 때만 설정해둔 마스터 키를 입력하세요.',
                            style:
                                TextStyle(color: Colors.white70, fontSize: 11.5),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _keyController,
                                  obscureText: true,
                                  style: const TextStyle(color: Colors.white),
                                  onSubmitted: (_) => _verifyEmergencyKey(),
                                  decoration: InputDecoration(
                                    hintText: '마스터 키 입력',
                                    hintStyle:
                                        const TextStyle(color: Colors.white38),
                                    errorText: _errorText,
                                    isDense: true,
                                    filled: true,
                                    fillColor: Colors.black26,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              FilledButton(
                                onPressed: _verifyEmergencyKey,
                                style: FilledButton.styleFrom(
                                  backgroundColor: Colors.redAccent,
                                ),
                                child: const Text('잠금 해제'),
                              ),
                              IconButton(
                                onPressed: () =>
                                    setState(() => _showKeyInput = false),
                                icon: const Icon(
                                  Icons.close,
                                  color: Colors.white54,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
