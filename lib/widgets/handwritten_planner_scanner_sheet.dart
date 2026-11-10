import 'dart:io';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/study_block.dart';
import '../services/planner_scanner_service.dart';

class HandwrittenPlannerScannerSheet extends StatefulWidget {
  final String targetDateStr;

  const HandwrittenPlannerScannerSheet({
    super.key,
    required this.targetDateStr,
  });

  @override
  State<HandwrittenPlannerScannerSheet> createState() =>
      _HandwrittenPlannerScannerSheetState();
}

class _HandwrittenPlannerScannerSheetState
    extends State<HandwrittenPlannerScannerSheet> {
  final Uuid _uuid = const Uuid();
  final TextEditingController _quickTextController = TextEditingController();

  File? _selectedImageFile;
  bool _isScanning = false;
  String _scanStatusMessage =
      '손으로 적은 플래너나 노트를 카메라로 찍거나 갤러리에서 불러오세요!';
  bool _showQuickTextParser = false;
  bool _replaceExistingTodayPlan = false;

  List<ScannedBlockDraft> _drafts = [];

  static const List<String> _subjectPresets = [
    '수학',
    '영어',
    '국어',
    '탐구',
    '코딩',
    '전공',
    '복습',
    '자습',
  ];

  @override
  void dispose() {
    _quickTextController.dispose();
    super.dispose();
  }

  Future<void> _captureOrPickImage({required bool fromCamera}) async {
    setState(() {
      _isScanning = true;
      _scanStatusMessage =
          fromCamera ? '📸 카메라에서 플래너 사진을 가져오는 중...' : '🖼️ 갤러리에서 사진을 불러오는 중...';
    });

    final path = await PlannerScannerService.instance
        .pickPlannerImage(fromCamera: fromCamera);

    if (!mounted) return;
    if (path == null || path.isEmpty) {
      setState(() {
        _isScanning = false;
        _scanStatusMessage = '사진 선택이 취소되었습니다. 다시 촬영하거나 아래에서 직접 입력할 수 있습니다.';
      });
      return;
    }

    final file = File(path);
    setState(() {
      _selectedImageFile = file;
      _scanStatusMessage = '🔍 손글씨 플래너의 시간대와 과목·학습 내용을 스캔하고 있습니다...';
    });

    final bundle =
        await PlannerScannerService.instance.scanPlannerImageFile(file);
    if (!mounted) return;

    setState(() {
      _isScanning = false;
      _drafts = bundle.drafts;
      if (bundle.rawRecognizedText.isNotEmpty) {
        _quickTextController.text = bundle.rawRecognizedText;
      }
      _scanStatusMessage =
          '✅ ${bundle.engineUsed} 완료! (${_drafts.length}개 시간 블록 추출됨 — 아래에서 시간/강제집중 여부를 확인 후 바로 등록하세요)';
    });
  }

  void _parseFromQuickText() {
    final text = _quickTextController.text.trim();
    if (text.isEmpty) return;

    final parsed = PlannerScannerService.instance.parseTimetableText(text);
    if (parsed.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '시간 범위를 찾지 못했습니다. 예: "09:00~10:30 수학 미적분 기출" 형태로 적어주세요.',
          ),
        ),
      );
      return;
    }

    setState(() {
      _drafts = parsed;
      _scanStatusMessage =
          '✨ 입력한 텍스트에서 ${parsed.length}개의 시간표 블록을 자동 변환했습니다!';
    });
  }

  void _addBlankDraft() {
    final lastEnd =
        _drafts.isNotEmpty ? _drafts.last.endMinutes + 10 : 9 * 60;
    final start = lastEnd.clamp(0, 22 * 60 + 30);
    final end = (start + 60).clamp(15, 23 * 60 + 59);

    setState(() {
      _drafts.add(
        ScannedBlockDraft(
          id: _uuid.v4(),
          subject: '수학',
          title: '집중 문제풀이 및 오답 정리',
          startMinutes: start,
          endMinutes: end,
          colorValue: PlannerScannerService.detectSubjectColor('수학'),
          autoFocusLock: true,
        ),
      );
    });
  }

  void _toggleAllFocusLock(bool enable) {
    setState(() {
      for (final d in _drafts) {
        d.autoFocusLock = enable;
      }
    });
  }

  Future<void> _pickDraftTime(ScannedBlockDraft draft,
      {required bool isStart}) async {
    final initMins = isStart ? draft.startMinutes : draft.endMinutes;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initMins ~/ 60, minute: initMins % 60),
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
          draft.startMinutes = mins;
          if (draft.endMinutes <= draft.startMinutes) {
            draft.endMinutes =
                (draft.startMinutes + 30).clamp(15, 23 * 60 + 59);
          }
        } else {
          draft.endMinutes =
              mins <= draft.startMinutes ? draft.startMinutes + 30 : mins;
        }
      });
    }
  }

  Future<void> _openGeminiKeyDialog() async {
    final currentKey = await PlannerScannerService.instance.loadGeminiApiKey();
    if (!mounted) return;
    final ctrl = TextEditingController(text: currentKey);

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          '✨ AI 손글씨 정밀 인식 키 설정 (선택)',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '기본 한국어 OCR은 별도 키 없이도 즉시 작동합니다.\n'
              '만약 흘려 쓴 손글씨까지 AI 비전(Gemini 2.5 Flash)으로 더 정확하게 자동 인식하고 싶다면 무료 Gemini API 키를 등록해 둘 수 있습니다.',
              style: TextStyle(fontSize: 12.5, height: 1.45),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              decoration: InputDecoration(
                labelText: 'Gemini API Key (AIza...)',
                hintText: '비워두면 기본 한국어 OCR 엔진 사용',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () async {
              await PlannerScannerService.instance.saveGeminiApiKey(ctrl.text);
              if (ctx.mounted) Navigator.pop(ctx);
              if (_selectedImageFile != null && mounted) {
                setState(() {
                  _isScanning = true;
                  _scanStatusMessage = '🔍 설정된 AI 비전 엔진으로 사진을 다시 스캔 중...';
                });
                final bundle = await PlannerScannerService.instance
                    .scanPlannerImageFile(_selectedImageFile!);
                if (!mounted) return;
                setState(() {
                  _isScanning = false;
                  _drafts = bundle.drafts;
                  _scanStatusMessage = '✅ ${bundle.engineUsed} 완료!';
                });
              }
            },
            child: const Text('저장'),
          ),
        ],
      ),
    );
  }

  void _confirmAndInsertToTodaySchedule() {
    if (_drafts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('추가할 시간표 블록이 없습니다. 사진을 촬영하거나 [시간 블록 추가]를 눌러주세요.'),
        ),
      );
      return;
    }

    final blocks = _drafts
        .map((d) => d.toStudyBlock(targetDateStr: widget.targetDateStr))
        .toList();

    Navigator.of(context).pop((
      blocks: blocks,
      replaceExistingTodayPlan: _replaceExistingTodayPlan,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final allLocked =
        _drafts.isNotEmpty && _drafts.every((d) => d.autoFocusLock);

    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      maxChildSize: 0.97,
      minChildSize: 0.65,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFFF8FAFC),
            borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 46,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4F46E5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.document_scanner_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '📷 손글씨 플래너 촬영 & 스케줄 스캔',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 17,
                            ),
                          ),
                          Text(
                            '오늘(${widget.targetDateStr})의 스케줄표로 바로 변환 & 강제집중 설정',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Colors.indigo.shade700,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'AI 손글씨 정밀 인식 키 설정',
                      onPressed: _openGeminiKeyDialog,
                      icon: const Icon(Icons.auto_awesome_outlined),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 30),
                  children: [
                    // 1. 카메라 촬영 / 갤러리 선택 버튼 바
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _isScanning
                                ? null
                                : () => _captureOrPickImage(fromCamera: true),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF4F46E5),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            icon: const Icon(Icons.camera_alt_rounded),
                            label: const Text(
                              '카메라로 플래너 찍기',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 13.5,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton.tonalIcon(
                            onPressed: _isScanning
                                ? null
                                : () => _captureOrPickImage(fromCamera: false),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            icon: const Icon(Icons.photo_library_rounded),
                            label: const Text(
                              '갤러리 사진 불러오기',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13.5,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // 스캔 상태 안내 배너
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEEF2FF),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFC7D2FE)),
                      ),
                      child: Row(
                        children: [
                          if (_isScanning)
                            const Padding(
                              padding: EdgeInsets.only(right: 10),
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2.4),
                              ),
                            )
                          else
                            const Padding(
                              padding: EdgeInsets.only(right: 8),
                              child: Icon(
                                Icons.tips_and_updates_rounded,
                                color: Color(0xFF4F46E5),
                                size: 20,
                              ),
                            ),
                          Expanded(
                            child: Text(
                              _scanStatusMessage,
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1E1B4B),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // 촬영된 플래너 사진 미리보기 (확대/축소 가능)
                    if (_selectedImageFile != null) ...[
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          height: 210,
                          width: double.infinity,
                          color: Colors.black87,
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: InteractiveViewer(
                                  minScale: 0.8,
                                  maxScale: 4.0,
                                  child: Image.file(
                                    _selectedImageFile!,
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              ),
                              Positioned(
                                right: 10,
                                bottom: 10,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.65),
                                    borderRadius: BorderRadius.circular(99),
                                  ),
                                  child: const Text(
                                    '🔍 두 손가락으로 손글씨 사진 확대 가능',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 12),

                    // S펜 손글씨 / 텍스트 빠른 파서 토글
                    InkWell(
                      onTap: () => setState(
                          () => _showQuickTextParser = !_showQuickTextParser),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.edit_note_rounded,
                                color: Color(0xFF0D9488)),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                '✍️ S펜 손글씨 / 텍스트로 빠르게 적어서 자동 변환하기',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            Icon(_showQuickTextParser
                                ? Icons.expand_less
                                : Icons.expand_more),
                          ],
                        ),
                      ),
                    ),
                    if (_showQuickTextParser) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.teal.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '갤럭시 기본 카메라 텍스트 추출(T) 결과를 붙여넣거나, 탭 S10 Ultra S펜으로 아래처럼 적으면 시간표 블록으로 자동 변환됩니다:',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: Color(0xFF475569),
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _quickTextController,
                              maxLines: 4,
                              decoration: InputDecoration(
                                hintText:
                                    '09:00 ~ 10:30 수학 미적분 기출 3단원\n10:45 - 12:00 영어 수능특강 독해 2강\n13시 30분 ~ 15시 국어 비문학 3지문',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerRight,
                              child: FilledButton.tonalIcon(
                                onPressed: _parseFromQuickText,
                                icon: const Icon(Icons.bolt_rounded, size: 18),
                                label: const Text(
                                  '텍스트를 시간표 블록으로 자동 변환',
                                  style: TextStyle(fontWeight: FontWeight.w800),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 16),

                    // 스캔된 스케줄 블록 헤더 + 일괄 강제집중 스위치
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '📋 스캔된 시간표 블록 (${_drafts.length}개)',
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 15.5,
                          ),
                        ),
                        Row(
                          children: [
                            if (_drafts.isNotEmpty)
                              ActionChip(
                                avatar: Icon(
                                  allLocked
                                      ? Icons.lock_clock_rounded
                                      : Icons.lock_open_rounded,
                                  size: 16,
                                  color: allLocked
                                      ? const Color(0xFFDC2626)
                                      : Colors.blueGrey,
                                ),
                                label: Text(
                                  allLocked ? '전체 강제집중 ON' : '전체 강제집중 켜기',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w800,
                                    color: allLocked
                                        ? const Color(0xFFDC2626)
                                        : Colors.blueGrey.shade800,
                                  ),
                                ),
                                backgroundColor: allLocked
                                    ? const Color(0xFFFEF2F2)
                                    : Colors.white,
                                onPressed: () =>
                                    _toggleAllFocusLock(!allLocked),
                              ),
                            const SizedBox(width: 6),
                            FilledButton.tonalIcon(
                              onPressed: _addBlankDraft,
                              icon: const Icon(Icons.add, size: 16),
                              label: const Text(
                                '블록 추가',
                                style: TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.w800),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    if (_drafts.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Column(
                          children: [
                            Icon(Icons.camera_enhance_outlined,
                                size: 42, color: Colors.indigo.shade300),
                            const SizedBox(height: 10),
                            const Text(
                              '위에서 [카메라로 플래너 찍기]를 누르거나\n[블록 추가]를 눌러 오늘의 스케줄을 구성해 보세요!',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF475569),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      ..._drafts.asMap().entries.map((entry) {
                        final idx = entry.key;
                        final draft = entry.value;
                        return _buildScannedDraftCard(idx, draft);
                      }),

                    const SizedBox(height: 12),

                    // 오늘 기존 계획 유지/교체 옵션
                    SwitchListTile(
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 12),
                      tileColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.grey.shade300),
                      ),
                      title: const Text(
                        '오늘의 스케줄을 이 스캔 시간표로만 덮어쓰기',
                        style: TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 13),
                      ),
                      subtitle: const Text(
                        '켜면 오늘 날짜만 특별 계획 모드로 전환되어 스캔한 시간표만 깔끔하게 표시됩니다.',
                        style: TextStyle(fontSize: 11.5),
                      ),
                      value: _replaceExistingTodayPlan,
                      onChanged: (v) =>
                          setState(() => _replaceExistingTodayPlan = v),
                    ),
                  ],
                ),
              ),

              // 하단 고정: 오늘의 스케줄표에 바로 넣기 버튼
              Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 10,
                      offset: const Offset(0, -3),
                    ),
                  ],
                ),
                child: SafeArea(
                  top: false,
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _confirmAndInsertToTodaySchedule,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF4F46E5),
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: const Icon(Icons.playlist_add_check_circle_rounded),
                      label: Text(
                        '오늘의 스케줄표에 바로 넣기 (${_drafts.length}개 블록)',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 15.5,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildScannedDraftCard(int index, ScannedBlockDraft draft) {
    final color = Color(draft.colorValue);
    return Container(
      key: ValueKey(draft.id),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: draft.autoFocusLock
              ? const Color(0xFFFCA5A5)
              : Colors.grey.shade300,
          width: draft.autoFocusLock ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 상단: 시간대 선택 + 강제집중 토글 + 삭제 버튼
          Row(
            children: [
              InkWell(
                onTap: () => _pickDraftTime(draft, isStart: true),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: color.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    StudyBlock.formatMinutes(draft.startMinutes),
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                      color: color,
                    ),
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Text('~',
                    style:
                        TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              ),
              InkWell(
                onTap: () => _pickDraftTime(draft, isStart: false),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: color.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    StudyBlock.formatMinutes(draft.endMinutes),
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                      color: color,
                    ),
                  ),
                ),
              ),
              const Spacer(),
              // 스케줄별 강제집중 원터치 토글
              InkWell(
                onTap: () => setState(
                    () => draft.autoFocusLock = !draft.autoFocusLock),
                borderRadius: BorderRadius.circular(99),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: draft.autoFocusLock
                        ? const Color(0xFFFEF2F2)
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(
                      color: draft.autoFocusLock
                          ? const Color(0xFFEF4444)
                          : Colors.grey.shade300,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        draft.autoFocusLock
                            ? Icons.lock_clock_rounded
                            : Icons.lock_open_rounded,
                        size: 15,
                        color: draft.autoFocusLock
                            ? const Color(0xFFDC2626)
                            : Colors.grey.shade600,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        draft.autoFocusLock ? '강제집중 ON' : '강제집중 OFF',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: draft.autoFocusLock
                              ? const Color(0xFFDC2626)
                              : Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  setState(() {
                    _drafts.removeAt(index);
                  });
                },
                icon: const Icon(Icons.delete_outline,
                    size: 19, color: Colors.redAccent),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // 과목 빠른 선택 칩
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _subjectPresets.map((subj) {
                final selected = draft.subject == subj;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(subj, style: const TextStyle(fontSize: 11.5)),
                    selected: selected,
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) {
                      setState(() {
                        draft.subject = subj;
                        draft.colorValue =
                            PlannerScannerService.detectSubjectColor(subj);
                      });
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 8),

          // 과목명 + 공부 내용 직접 수정 입력창
          Row(
            children: [
              SizedBox(
                width: 90,
                child: TextFormField(
                  initialValue: draft.subject,
                  decoration: InputDecoration(
                    labelText: '과목',
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onChanged: (v) {
                    draft.subject = v;
                    draft.colorValue =
                        PlannerScannerService.detectSubjectColor(v);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  initialValue: draft.title,
                  decoration: InputDecoration(
                    labelText: '세부 공부 내용',
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onChanged: (v) => draft.title = v,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
