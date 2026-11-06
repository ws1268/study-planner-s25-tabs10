import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/study_block.dart';
import '../models/subject_goal.dart';

class ScheduleStorage {
  static const String _blocksKey = 'study_planner_blocks_v1';
  static const String _customModeDatesKey = 'study_planner_custom_dates_v1';
  static const String _weeklyGoalsKey = 'study_planner_weekly_goals_v1';
  static const String _emergencyKeyPref = 'study_planner_emergency_key_v1';
  static const String _pairingCodePref = 'study_planner_pairing_code_v1';
  static const String _pomoExtraMinsKey = 'study_planner_pomo_extra_mins_v1';
  static const String _pomoCountKey = 'study_planner_pomo_count_v1';
  static const String _lastSyncTimestampKey = 'study_planner_last_sync_ts_v1';

  static String formatDate(DateTime date) =>
      DateFormat('yyyy-MM-dd').format(date);

  Future<List<StudyBlock>> loadAllBlocks() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_blocksKey);
    if (raw == null || raw.isEmpty) {
      final defaults = _buildInitialSampleBlocks();
      await saveAllBlocks(defaults);
      return defaults;
    }
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((item) => StudyBlock.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveAllBlocks(List<StudyBlock> blocks) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(blocks.map((b) => b.toJson()).toList());
    await prefs.setString(_blocksKey, encoded);
    await _touchSyncTimestamp(prefs);
  }

  /// 과목당 1주일 목표 공부시간 로드
  Future<List<SubjectWeeklyGoal>> loadSubjectWeeklyGoals() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_weeklyGoalsKey);
    if (raw == null || raw.isEmpty) {
      final defaults = _buildInitialWeeklyGoals();
      await saveSubjectWeeklyGoals(defaults);
      return defaults;
    }
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => SubjectWeeklyGoal.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return _buildInitialWeeklyGoals();
    }
  }

  Future<void> saveSubjectWeeklyGoals(List<SubjectWeeklyGoal> goals) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(goals.map((g) => g.toJson()).toList());
    await prefs.setString(_weeklyGoalsKey, encoded);
    await _touchSyncTimestamp(prefs);
  }

  /// 뽀모도로 자유 타이머로 추가 달성한 과목별 주간 공부 시간(분) 로드/저장
  Future<Map<String, int>> loadExtraPomodoroMinutes() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_pomoExtraMinsKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, (v as num).toInt()));
    } catch (_) {
      return {};
    }
  }

  Future<void> saveExtraPomodoroMinutes(Map<String, int> map) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pomoExtraMinsKey, jsonEncode(map));
    await _touchSyncTimestamp(prefs);
  }

  Future<int> loadCompletedPomodoroCount() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_pomoCountKey) ?? 0;
  }

  Future<void> saveCompletedPomodoroCount(int count) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_pomoCountKey, count);
    await _touchSyncTimestamp(prefs);
  }

  /// 비상 해제 마스터 키 로드/저장 (기본값: '1129')
  Future<String> loadEmergencyMasterKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_emergencyKeyPref) ?? '1129';
  }

  Future<void> saveEmergencyMasterKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_emergencyKeyPref, key.trim());
  }

  /// 갤럭시 S25 <-> 갤럭시 탭 S10 Ultra 연동 코드 로드/저장
  Future<String> loadDevicePairingCode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_pairingCodePref) ?? 'S25-TAB10';
  }

  Future<void> saveDevicePairingCode(String code) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pairingCodePref, code.trim().toUpperCase());
  }

  /// 특정 날짜('yyyy-MM-dd')가 '오늘만의 일일 계획 단독 모드'인지 여부 목록 로드
  Future<Set<String>> loadCustomOverrideDates() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_customModeDatesKey) ?? [];
    return list.toSet();
  }

  Future<void> saveCustomOverrideDates(Set<String> dates) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_customModeDatesKey, dates.toList());
    await _touchSyncTimestamp(prefs);
  }

  Future<int> getLastSyncTimestamp() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_lastSyncTimestampKey) ?? 0;
  }

  Future<void> _touchSyncTimestamp(SharedPreferences prefs) async {
    await prefs.setInt(
      _lastSyncTimestampKey,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// S25 <-> 탭 S10 Ultra 전체 데이터 동기화용 스냅샷 추출
  Future<Map<String, dynamic>> exportFullSyncSnapshot({
    required List<StudyBlock> blocks,
    required List<SubjectWeeklyGoal> weeklyGoals,
    required Set<String> customOverrideDates,
    required Map<String, int> extraPomodoroMinutes,
    required int completedPomodoroCount,
  }) async {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastSyncTimestampKey, ts);

    return {
      'updatedAt': ts,
      'blocks': blocks.map((b) => b.toJson()).toList(),
      'weeklyGoals': weeklyGoals.map((g) => g.toJson()).toList(),
      'customOverrideDates': customOverrideDates.toList(),
      'extraPomodoroMinutes': extraPomodoroMinutes,
      'completedPomodoroCount': completedPomodoroCount,
    };
  }

  List<SubjectWeeklyGoal> _buildInitialWeeklyGoals() {
    return const [
      SubjectWeeklyGoal(
        subject: '수학',
        targetMinutes: 600, // 주 10시간 목표
        colorValue: 0xFF4F46E5,
      ),
      SubjectWeeklyGoal(
        subject: '영어',
        targetMinutes: 420, // 주 7시간 목표
        colorValue: 0xFF0D9488,
      ),
      SubjectWeeklyGoal(
        subject: '국어',
        targetMinutes: 360, // 주 6시간 목표
        colorValue: 0xFFE11D48,
      ),
      SubjectWeeklyGoal(
        subject: '탐구',
        targetMinutes: 300, // 주 5시간 목표
        colorValue: 0xFFD97706,
      ),
    ];
  }

  List<StudyBlock> _buildInitialSampleBlocks() {
    final now = DateTime.now();
    final nowMinutes = now.hour * 60 + now.minute;

    final currentStart = (nowMinutes - 15).clamp(0, 22 * 60);
    final currentEnd =
        (currentStart + 65).clamp(currentStart + 15, 23 * 60 + 30);
    final nextStart = (currentEnd + 15).clamp(0, 23 * 60 + 30);
    final nextEnd = (nextStart + 50).clamp(nextStart + 10, 23 * 60 + 59);

    return [
      StudyBlock(
        id: 'sample_now_1',
        subject: '수학',
        title: '미적분 기출문제 풀이 & 오답노트 정리',
        memo: '틀린 문제는 풀이 발상 한 줄씩 꼭 적어두기',
        colorValue: 0xFF4F46E5,
        startMinutes: currentStart,
        endMinutes: currentEnd,
        weekdays: const [1, 2, 3, 4, 5, 6, 7],
        notifyOnStart: true,
        notifyBeforeEndMinutes: 5,
        checklist: const [
          ChecklistItem(id: 'c1', text: '3단원 기출 15문제 시간 재고 풀기', isDone: true),
          ChecklistItem(id: 'c2', text: '헷갈린 문항 해설지 비교 및 오답 체크', isDone: false),
          ChecklistItem(id: 'c3', text: '핵심 공식 암기 테스트', isDone: false),
        ],
      ),
      StudyBlock(
        id: 'sample_next_2',
        subject: '영어',
        title: '수능/토익 빈출 어휘 암기 & 구문 독해 5지문',
        memo: '모르는 구문은 형광펜 표시 후 소리 내어 읽기',
        colorValue: 0xFF0D9488,
        startMinutes: nextStart,
        endMinutes: nextEnd,
        weekdays: const [1, 2, 3, 4, 5, 6, 7],
        notifyOnStart: true,
        notifyBeforeEndMinutes: 5,
        checklist: const [
          ChecklistItem(
              id: 'c4', text: 'Day 14 단어장 60개 암기 및 셀프 테스트', isDone: false),
          ChecklistItem(id: 'c5', text: '빈칸추론 고난도 5지문 분석', isDone: false),
        ],
      ),
      const StudyBlock(
        id: 'sample_morning',
        subject: '국어',
        title: '비문학 독서 지문 3개 구조 독해 훈련',
        memo: '문단별 핵심 키워드 동그라미 치며 읽기',
        colorValue: 0xFFE11D48,
        startMinutes: 9 * 60 + 10,
        endMinutes: 10 * 60 + 35,
        weekdays: [1, 2, 3, 4, 5],
        notifyOnStart: true,
        notifyBeforeEndMinutes: 10,
        checklist: [
          ChecklistItem(id: 'c6', text: '경제/법률 지문 2개 시간 재고 풀기', isDone: false),
          ChecklistItem(id: 'c7', text: '선지 근거 본문에서 1:1 매칭 확인', isDone: false),
        ],
      ),
    ];
  }
}
