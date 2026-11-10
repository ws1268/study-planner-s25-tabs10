import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/study_block.dart';

class StudyBlockEditorSheet extends StatefulWidget {
  final StudyBlock? existingBlock;
  final bool defaultToDailyPlan;
  final String targetDateStr; // 'yyyy-MM-dd'
  final int targetWeekday; // 1 (월) ~ 7 (일)

  const StudyBlockEditorSheet({
    super.key,
    this.existingBlock,
    required this.defaultToDailyPlan,
    required this.targetDateStr,
    required this.targetWeekday,
  });

  @override
  State<StudyBlockEditorSheet> createState() => _StudyBlockEditorSheetState();
}

class _StudyBlockEditorSheetState extends State<StudyBlockEditorSheet> {
  final _uuid = const Uuid();
  late TextEditingController _subjectController;
  late TextEditingController _titleController;
  late TextEditingController _memoController;
  final TextEditingController _newChecklistController = TextEditingController();

  late int _startMinutes;
  late int _endMinutes;
  late int _selectedColor;
  late bool _isDailySpecific;
  late Set<int> _selectedWeekdays;
  late bool _notifyOnStart;
  late int _notifyBeforeEndMinutes;
  late List<ChecklistItem> _checklist;
  late bool _autoFocusLock;
  late bool _lockSyncBothDevices;

  static const List<String> _quickSubjects = [
    '수학',
    '영어',
    '국어',
    '탐구',
    '코딩',
    '전공/자격증',
    '복습/오답',
    '자습',
  ];

  static const List<int> _paletteColors = [
    0xFF4F46E5, // Indigo
    0xFF0D9488, // Teal
    0xFFE11D48, // Rose
    0xFFD97706, // Amber
    0xFF2563EB, // Blue
    0xFF7C3AED, // Violet
    0xFF059669, // Emerald
    0xFFDB2777, // Pink
    0xFFEA580C, // Orange
    0xFF475569, // Slate
  ];

  static const List<String> _weekdayLabels = ['월', '화', '수', '목', '금', '토', '일'];

  @override
  void initState() {
    super.initState();
    final b = widget.existingBlock;
    final now = TimeOfDay.now();
    final defaultStart = (now.hour * 60 + now.minute).clamp(0, 22 * 60);

    _subjectController = TextEditingController(text: b?.subject ?? '수학');
    _titleController = TextEditingController(text: b?.title ?? '');
    _memoController = TextEditingController(text: b?.memo ?? '');

    _startMinutes = b?.startMinutes ?? defaultStart;
    _endMinutes = b?.endMinutes ?? (defaultStart + 50).clamp(15, 23 * 60 + 59);
    _selectedColor = b?.colorValue ?? _paletteColors.first;

    if (b != null) {
      _isDailySpecific = b.specificDate != null;
      _selectedWeekdays =
          b.weekdays.isNotEmpty ? b.weekdays.toSet() : {widget.targetWeekday};
    } else {
      _isDailySpecific = widget.defaultToDailyPlan;
      _selectedWeekdays = {widget.targetWeekday};
    }

    _notifyOnStart = b?.notifyOnStart ?? true;
    _notifyBeforeEndMinutes = b?.notifyBeforeEndMinutes ?? 5;
    _checklist = b != null ? List.of(b.checklist) : [];
    _autoFocusLock = b?.autoFocusLock ?? false;
    _lockSyncBothDevices = b?.lockSyncBothDevices ?? true;
  }

  @override
  void dispose() {
    _subjectController.dispose();
    _titleController.dispose();
    _memoController.dispose();
    _newChecklistController.dispose();
    super.dispose();
  }

  Future<void> _pickTime({required bool isStart}) async {
    final currentMins = isStart ? _startMinutes : _endMinutes;
    final initial = TimeOfDay(hour: currentMins ~/ 60, minute: currentMins % 60);

    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      helpText: isStart ? '시작 시간 선택 (분 단위 자유 지정)' : '종료 시간 선택 (분 단위 자유 지정)',
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        final mins = picked.hour * 60 + picked.minute;
        if (isStart) {
          _startMinutes = mins;
          if (_endMinutes <= _startMinutes) {
            _endMinutes = (_startMinutes + 30).clamp(1, 23 * 60 + 59);
          }
        } else {
          _endMinutes = mins;
        }
      });
    }
  }

  void _adjustMinutes({required bool isStart, required int delta}) {
    setState(() {
      if (isStart) {
        _startMinutes = (_startMinutes + delta).clamp(0, 23 * 60 + 50);
        if (_endMinutes <= _startMinutes) {
          _endMinutes = (_startMinutes + 10).clamp(1, 23 * 60 + 59);
        }
      } else {
        _endMinutes =
            (_endMinutes + delta).clamp(_startMinutes + 5, 23 * 60 + 59);
      }
    });
  }

  void _addChecklistItem() {
    final text = _newChecklistController.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _checklist.add(ChecklistItem(id: _uuid.v4(), text: text));
      _newChecklistController.clear();
    });
  }

  void _save() {
    final subject = _subjectController.text.trim();
    final title = _titleController.text.trim();

    if (subject.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('과목명을 입력해주세요.')),
      );
      return;
    }
    if (_endMinutes <= _startMinutes) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('종료 시간은 시작 시간보다 뒤여야 합니다.')),
      );
      return;
    }
    if (!_isDailySpecific && _selectedWeekdays.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('반복할 요일을 최소 1개 이상 선택해주세요.')),
      );
      return;
    }

    // 입력창에 남아있는 할 일 텍스트도 자동 추가
    if (_newChecklistController.text.trim().isNotEmpty) {
      _checklist.add(
        ChecklistItem(
          id: _uuid.v4(),
          text: _newChecklistController.text.trim(),
        ),
      );
    }

    final result = StudyBlock(
      id: widget.existingBlock?.id ?? _uuid.v4(),
      subject: subject,
      title: title.isEmpty ? '$subject 집중 학습' : title,
      memo: _memoController.text.trim(),
      colorValue: _selectedColor,
      startMinutes: _startMinutes,
      endMinutes: _endMinutes,
      weekdays: _isDailySpecific ? [] : (_selectedWeekdays.toList()..sort()),
      specificDate: _isDailySpecific ? widget.targetDateStr : null,
      notifyOnStart: _notifyOnStart,
      notifyBeforeEndMinutes: _notifyBeforeEndMinutes,
      checklist: _checklist,
      autoFocusLock: _autoFocusLock,
      lockSyncBothDevices: _lockSyncBothDevices,
    );

    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final duration = _endMinutes - _startMinutes;
    final durationText = duration > 0
        ? '${duration ~/ 60 > 0 ? '${duration ~/ 60}시간 ' : ''}${duration % 60}분 동안 공부'
        : '시간을 확인해주세요';

    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      maxChildSize: 0.96,
      minChildSize: 0.6,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      widget.existingBlock == null
                          ? '새 공부 시간 블록 만들기'
                          : '공부 시간 블록 수정',
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: _save,
                      icon: const Icon(Icons.check, size: 18),
                      label: const Text('저장'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Color(_selectedColor),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                  children: [
                    // 1. 계획 유형 선택 (요일별 반복 vs 오늘만의 일일 계획)
                    const Text(
                      '1. 시간표 적용 방식',
                      style:
                          TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<bool>(
                      segments: [
                        const ButtonSegment(
                          value: false,
                          icon: Icon(Icons.repeat),
                          label: Text('요일별 반복 시간표'),
                        ),
                        ButtonSegment(
                          value: true,
                          icon: const Icon(Icons.today),
                          label: Text('오늘(${widget.targetDateStr.substring(5)}) 전용 계획'),
                        ),
                      ],
                      selected: {_isDailySpecific},
                      onSelectionChanged: (s) {
                        setState(() => _isDailySpecific = s.first);
                      },
                    ),
                    if (!_isDailySpecific) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 6,
                        children: List.generate(7, (idx) {
                          final dayNum = idx + 1;
                          final isSelected = _selectedWeekdays.contains(dayNum);
                          return FilterChip(
                            label: Text(_weekdayLabels[idx]),
                            selected: isSelected,
                            selectedColor:
                                Color(_selectedColor).withValues(alpha: 0.2),
                            checkmarkColor: Color(_selectedColor),
                            onSelected: (val) {
                              setState(() {
                                if (val) {
                                  _selectedWeekdays.add(dayNum);
                                } else {
                                  _selectedWeekdays.remove(dayNum);
                                }
                              });
                            },
                          );
                        }),
                      ),
                    ],
                    const SizedBox(height: 22),

                    // 2. 자유로운 시작 ~ 종료 시간 설정 (분 단위)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          '2. 공부 시간대 (분 단위 자유 선택)',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 14),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Color(_selectedColor).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            durationText,
                            style: TextStyle(
                              color: Color(_selectedColor),
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _buildTimeAdjustCard(
                            label: '시작 시간',
                            minutes: _startMinutes,
                            onTapPicker: () => _pickTime(isStart: true),
                            onMinus5: () =>
                                _adjustMinutes(isStart: true, delta: -5),
                            onMinus1: () =>
                                _adjustMinutes(isStart: true, delta: -1),
                            onPlus1: () =>
                                _adjustMinutes(isStart: true, delta: 1),
                            onPlus5: () =>
                                _adjustMinutes(isStart: true, delta: 5),
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8),
                          child: Text(
                            '~',
                            style: TextStyle(
                                fontSize: 22, fontWeight: FontWeight.bold),
                          ),
                        ),
                        Expanded(
                          child: _buildTimeAdjustCard(
                            label: '종료 시간',
                            minutes: _endMinutes,
                            onTapPicker: () => _pickTime(isStart: false),
                            onMinus5: () =>
                                _adjustMinutes(isStart: false, delta: -5),
                            onMinus1: () =>
                                _adjustMinutes(isStart: false, delta: -1),
                            onPlus1: () =>
                                _adjustMinutes(isStart: false, delta: 1),
                            onPlus5: () =>
                                _adjustMinutes(isStart: false, delta: 5),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),

                    // 3. 과목 선택 및 색상 지정
                    const Text(
                      '3. 과목 및 테마 색상',
                      style:
                          TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: _quickSubjects.map((subj) {
                        final isCurrent = _subjectController.text.trim() == subj;
                        return ActionChip(
                          label: Text(subj),
                          backgroundColor: isCurrent
                              ? Color(_selectedColor).withValues(alpha: 0.18)
                              : null,
                          side: BorderSide(
                            color: isCurrent
                                ? Color(_selectedColor)
                                : Colors.grey.shade300,
                          ),
                          onPressed: () {
                            setState(() {
                              _subjectController.text = subj;
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _subjectController,
                      decoration: InputDecoration(
                        labelText: '과목명 직접 입력',
                        hintText: '예: 수학, 영어회화, 알고리즘, 물리1',
                        prefixIcon:
                            Icon(Icons.book, color: Color(_selectedColor)),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 42,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _paletteColors.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 10),
                        itemBuilder: (context, idx) {
                          final c = _paletteColors[idx];
                          final selected = c == _selectedColor;
                          return GestureDetector(
                            onTap: () => setState(() => _selectedColor = c),
                            child: Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: Color(c),
                                shape: BoxShape.circle,
                                border: selected
                                    ? Border.all(color: Colors.black87, width: 3)
                                    : null,
                              ),
                              child: selected
                                  ? const Icon(Icons.check,
                                      color: Colors.white, size: 20)
                                  : null,
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 22),

                    // 4. 무엇을 할지 (세부 학습 목표 & 체크리스트)
                    const Text(
                      '4. 이 시간에 무엇을 공부할까요?',
                      style:
                          TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _titleController,
                      decoration: InputDecoration(
                        labelText: '핵심 공부 내용 (위젯과 알림에 크게 표시됩니다)',
                        hintText: '예: 미적분 기출 3단원 20문제 풀이 & 오답 정리',
                        prefixIcon: const Icon(Icons.flag_outlined),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _memoController,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: '메모 / 준비물 / 페이지 범위 (선택)',
                        hintText: '예: 수특 p.42~58, 타이머 45분 맞추고 실전처럼 풀기',
                        prefixIcon: const Icon(Icons.notes),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 세부 체크리스트
                    const Text(
                      '세부 할 일 체크리스트 (공부하면서 하나씩 체크!)',
                      style:
                          TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _newChecklistController,
                            onSubmitted: (_) => _addChecklistItem(),
                            decoration: InputDecoration(
                              hintText: '할 일 추가 (예: 단어 50개 테스트)',
                              isDense: true,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.tonalIcon(
                          onPressed: _addChecklistItem,
                          icon: const Icon(Icons.add),
                          label: const Text('추가'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ..._checklist.map((item) {
                      return Card(
                        margin: const EdgeInsets.only(bottom: 6),
                        elevation: 0,
                        color: Colors.grey.shade100,
                        child: ListTile(
                          dense: true,
                          leading: const Icon(Icons.check_box_outline_blank,
                              size: 20),
                          title: Text(item.text),
                          trailing: IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () {
                              setState(() {
                                _checklist.removeWhere((e) => e.id == item.id);
                              });
                            },
                          ),
                        ),
                      );
                    }),
                    const SizedBox(height: 20),

                    // 5. 스케줄별 강제집중 기능 (다른 앱 차단)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: _autoFocusLock
                            ? const Color(0xFFFEF2F2)
                            : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: _autoFocusLock
                              ? const Color(0xFFEF4444)
                              : Colors.grey.shade300,
                          width: _autoFocusLock ? 1.5 : 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                _autoFocusLock
                                    ? Icons.lock_clock_rounded
                                    : Icons.lock_open_rounded,
                                color: _autoFocusLock
                                    ? const Color(0xFFDC2626)
                                    : Colors.blueGrey,
                              ),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: Text(
                                  '5. 이 스케줄에 강제집중(앱 차단) 활성화',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                              Switch(
                                value: _autoFocusLock,
                                activeColor: const Color(0xFFDC2626),
                                onChanged: (v) =>
                                    setState(() => _autoFocusLock = v),
                              ),
                            ],
                          ),
                          const Text(
                            '켜두면 이 공부 시간대가 시작될 때 자동으로 최대 집중 잠금이 켜져 다른 앱 사용을 막아줍니다. (비상 키로 언제든 해제 가능)',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF475569),
                              height: 1.4,
                            ),
                          ),
                          if (_autoFocusLock) ...[
                            const Divider(height: 16),
                            SwitchListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: const Text(
                                '갤럭시 S25 + 탭 S10 Ultra 동시 강제잠금 연동',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12.5,
                                ),
                              ),
                              subtitle: const Text(
                                '이 스케줄이 시작되면 폰과 태블릿 두 기기 모두 다른 앱을 쓰지 못하게 잠급니다.',
                                style: TextStyle(fontSize: 11.5),
                              ),
                              value: _lockSyncBothDevices,
                              activeColor: const Color(0xFFDC2626),
                              onChanged: (v) =>
                                  setState(() => _lockSyncBothDevices = v),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // 6. 알림 설정
                    const Text(
                      '6. 알림 설정 (사운드 + 팝업 토스트)',
                      style:
                          TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('공부 시작 정각에 알림 받기'),
                      subtitle: const Text('지금 무슨 과목·무슨 공부를 해야 하는지 알려줍니다.'),
                      value: _notifyOnStart,
                      onChanged: (v) => setState(() => _notifyOnStart = v),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('종료 전 마무리 알림'),
                        DropdownButton<int>(
                          value: _notifyBeforeEndMinutes,
                          items: const [
                            DropdownMenuItem(value: 0, child: Text('사용 안 함')),
                            DropdownMenuItem(value: 5, child: Text('종료 5분 전')),
                            DropdownMenuItem(value: 10, child: Text('종료 10분 전')),
                            DropdownMenuItem(value: 15, child: Text('종료 15분 전')),
                          ],
                          onChanged: (v) {
                            if (v != null) {
                              setState(() => _notifyBeforeEndMinutes = v);
                            }
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTimeAdjustCard({
    required String label,
    required int minutes,
    required VoidCallback onTapPicker,
    required VoidCallback onMinus5,
    required VoidCallback onMinus1,
    required VoidCallback onPlus1,
    required VoidCallback onPlus5,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 4),
          InkWell(
            onTap: onTapPicker,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    StudyBlock.formatMinutes(minutes),
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.edit_calendar_outlined, size: 16),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _miniStepBtn('-5분', onMinus5),
              _miniStepBtn('-1분', onMinus1),
              _miniStepBtn('+1분', onPlus1),
              _miniStepBtn('+5분', onPlus5),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniStepBtn(String text, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Text(
          text,
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
