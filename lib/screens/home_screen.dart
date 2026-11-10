import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import '../models/study_block.dart';
import '../models/subject_goal.dart';
import '../services/app_update_service.dart';
import '../services/focus_lock_service.dart';
import '../services/notification_service.dart';
import '../services/schedule_storage.dart';
import '../services/widget_service.dart';
import '../widgets/active_study_hero_card.dart';
import '../widgets/handwritten_planner_scanner_sheet.dart';
import '../widgets/pomodoro_timer_card.dart';
import '../widgets/study_block_editor_sheet.dart';
import '../widgets/ultra_focus_lock_overlay.dart';
import '../widgets/weekly_subject_stats_view.dart';
import '../widgets/widget_preview_dialog.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  final ScheduleStorage _storage = ScheduleStorage();
  final Uuid _uuid = const Uuid();

  List<StudyBlock> _allBlocks = [];
  List<SubjectWeeklyGoal> _weeklyGoals = [];
  Set<String> _customOverrideDates = {};
  Map<String, int> _extraPomodoroMinutes = {};
  int _completedPomodoroCount = 0;

  String _emergencyMasterKey = '1129';
  String _pairingCode = 'S25-TAB10';
  int _lastAppliedSyncTimestamp = 0;
  ReleaseInfo? _latestRelease;

  DateTime _now = DateTime.now();
  Timer? _ticker;

  // 🔒 최대 집중 모드 (다른 앱 차단 & S25/탭S10 동시 잠금) 상태
  bool _isUltraFocusLocked = false;
  bool _ultraSyncBothDevices = true;
  String _lockedSubject = '수학';
  String _lockedTitle = '최대 집중 모드 진행 중';
  Color _lockedColor = const Color(0xFF4F46E5);
  int _lockRemainingSeconds = 0;
  int _lockTotalSeconds = 0;

  late TabController _tabController;
  int _selectedWeekday = DateTime.now().weekday;
  DateTime _selectedDate = DateTime.now();

  String? _lastAlertKey;
  int _lastWidgetSyncMinute = -1;
  final Set<String> _autoLockedBlockKeys = {};

  static const List<String> _weekdayNames = ['월', '화', '수', '목', '금', '토', '일'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();

    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final current = DateTime.now();
      setState(() {
        _now = current;
        if (_isUltraFocusLocked) {
          if (_lockRemainingSeconds > 1) {
            _lockRemainingSeconds--;
          } else {
            _completeUltraFocusLock();
          }
        }
      });
      _checkRealtimeTransitions(current);
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final blocks = await _storage.loadAllBlocks();
    final goals = await _storage.loadSubjectWeeklyGoals();
    final customDates = await _storage.loadCustomOverrideDates();
    final extraPomo = await _storage.loadExtraPomodoroMinutes();
    final pomoCount = await _storage.loadCompletedPomodoroCount();
    final masterKey = await _storage.loadEmergencyMasterKey();
    final pairingCode = await _storage.loadDevicePairingCode();
    final lastTs = await _storage.getLastSyncTimestamp();

    if (!mounted) return;
    setState(() {
      _allBlocks = blocks;
      _weeklyGoals = goals;
      _customOverrideDates = customDates;
      _extraPomodoroMinutes = extraPomo;
      _completedPomodoroCount = pomoCount;
      _emergencyMasterKey = masterKey;
      _pairingCode = pairingCode;
      _lastAppliedSyncTimestamp = lastTs;
    });

    await FocusLockService.instance.initialize(
      pairingCode: _pairingCode,
      onRemoteEvent: _handleRemoteDeviceEvent,
      getLocalSnapshotCallback: _buildCurrentSyncSnapshotMap,
    );
    await _syncNotificationsAndWidget();
    _checkForAppUpdateSilently();
  }

  Future<void> _checkForAppUpdateSilently() async {
    final release = await AppUpdateService.instance.checkLatestRelease();
    if (!mounted || release == null) return;
    setState(() {
      _latestRelease = release;
    });
  }

  Map<String, dynamic> _buildCurrentSyncSnapshotMap() {
    return {
      'updatedAt': _lastAppliedSyncTimestamp > 0
          ? _lastAppliedSyncTimestamp
          : DateTime.now().millisecondsSinceEpoch,
      'blocks': _allBlocks.map((b) => b.toJson()).toList(),
      'weeklyGoals': _weeklyGoals.map((g) => g.toJson()).toList(),
      'customOverrideDates': _customOverrideDates.toList(),
      'extraPomodoroMinutes': _extraPomodoroMinutes,
      'completedPomodoroCount': _completedPomodoroCount,
    };
  }

  /// 로컬에서 변경 사항이 발생할 때마다 저장 + 연결된 S25 / 탭 S10 Ultra로 전체 동기화 브로드캐스트
  Future<void> _persistAndBroadcastAllChanges() async {
    await _storage.saveAllBlocks(_allBlocks);
    await _storage.saveSubjectWeeklyGoals(_weeklyGoals);
    await _storage.saveCustomOverrideDates(_customOverrideDates);
    await _storage.saveExtraPomodoroMinutes(_extraPomodoroMinutes);
    await _storage.saveCompletedPomodoroCount(_completedPomodoroCount);

    final snap = await _storage.exportFullSyncSnapshot(
      blocks: _allBlocks,
      weeklyGoals: _weeklyGoals,
      customOverrideDates: _customOverrideDates,
      extraPomodoroMinutes: _extraPomodoroMinutes,
      completedPomodoroCount: _completedPomodoroCount,
    );
    _lastAppliedSyncTimestamp = snap['updatedAt'] as int;

    FocusLockService.instance.broadcastFullDataSync(snap);
    await _syncNotificationsAndWidget();
  }

  /// 갤럭시 S25 <-> 갤럭시 탭 S10 Ultra 간 원격 데이터 동기화 및 잠금/해제 신호 수신 처리
  Future<void> _handleRemoteDeviceEvent(FocusLockPayload payload) async {
    if (!mounted) return;

    if (payload.type == 'FULL_DATA_SYNC' && payload.syncData != null) {
      await _applyIncomingSyncSnapshot(payload.syncData!);
      return;
    }

    if (payload.type == 'LOCK_START' && !_isUltraFocusLocked) {
      setState(() {
        _isUltraFocusLocked = true;
        _ultraSyncBothDevices = true;
        _lockedSubject = payload.subject;
        _lockedTitle = payload.title;
        _lockRemainingSeconds = payload.remainingSeconds;
        _lockTotalSeconds = payload.totalSeconds;
      });
      FocusLockService.instance.enableNativeAppLock();
    } else if ((payload.type == 'EMERGENCY_UNLOCK' ||
            payload.type == 'LOCK_COMPLETE') &&
        _isUltraFocusLocked) {
      setState(() {
        _isUltraFocusLocked = false;
      });
      FocusLockService.instance.disableNativeAppLock();
      _showInAppAlertToast(
        title: '🔓 연동 기기 동시 잠금 해제됨',
        message: '연결된 갤럭시 기기에서 잠금이 해제되었습니다.',
        color: Colors.teal,
      );
    }
  }

  Future<void> _applyIncomingSyncSnapshot(Map<String, dynamic> data) async {
    try {
      final incomingTs = (data['updatedAt'] as num?)?.toInt() ?? 0;
      if (incomingTs > 0 && incomingTs < _lastAppliedSyncTimestamp) {
        return; // 이미 더 최신 상태를 보유 중이면 무시
      }

      final newBlocks = (data['blocks'] as List<dynamic>? ?? [])
          .map((e) => StudyBlock.fromJson(e as Map<String, dynamic>))
          .toList();
      final newGoals = (data['weeklyGoals'] as List<dynamic>? ?? [])
          .map((e) => SubjectWeeklyGoal.fromJson(e as Map<String, dynamic>))
          .toList();
      final newDates = (data['customOverrideDates'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toSet();
      final rawExtra =
          data['extraPomodoroMinutes'] as Map<String, dynamic>? ?? {};
      final newExtra =
          rawExtra.map((k, v) => MapEntry(k, (v as num).toInt()));
      final newPomoCount =
          (data['completedPomodoroCount'] as num?)?.toInt() ??
              _completedPomodoroCount;

      if (!mounted) return;
      setState(() {
        _allBlocks = newBlocks;
        if (newGoals.isNotEmpty) _weeklyGoals = newGoals;
        _customOverrideDates = newDates;
        _extraPomodoroMinutes = newExtra;
        _completedPomodoroCount = newPomoCount;
        _lastAppliedSyncTimestamp =
            incomingTs > 0 ? incomingTs : DateTime.now().millisecondsSinceEpoch;
      });

      await _storage.saveAllBlocks(_allBlocks);
      await _storage.saveSubjectWeeklyGoals(_weeklyGoals);
      await _storage.saveCustomOverrideDates(_customOverrideDates);
      await _storage.saveExtraPomodoroMinutes(_extraPomodoroMinutes);
      await _storage.saveCompletedPomodoroCount(_completedPomodoroCount);
      await _syncNotificationsAndWidget();
    } catch (e) {
      debugPrint('원격 동기화 데이터 적용 오류: $e');
    }
  }

  /// 🔒 최대 집중 모드 시작
  Future<void> _startUltraFocusLock({
    required String subject,
    required String title,
    required Color color,
    required int durationSeconds,
    required bool syncBothDevices,
  }) async {
    setState(() {
      _isUltraFocusLocked = true;
      _ultraSyncBothDevices = syncBothDevices;
      _lockedSubject = subject;
      _lockedTitle = title;
      _lockedColor = color;
      _lockRemainingSeconds = durationSeconds;
      _lockTotalSeconds = durationSeconds;
    });

    await FocusLockService.instance.enableNativeAppLock();

    if (syncBothDevices) {
      FocusLockService.instance.broadcastLockSignal(
        FocusLockPayload(
          type: 'LOCK_START',
          pairingCode: _pairingCode,
          subject: subject,
          title: title,
          remainingSeconds: durationSeconds,
          totalSeconds: durationSeconds,
          sourceDevice: FocusLockService.instance.deviceId,
        ),
      );
    }
  }

  Future<void> _completeUltraFocusLock() async {
    final completedMins = (_lockTotalSeconds / 60).round().clamp(1, 240);
    final subj = _lockedSubject;

    setState(() {
      _isUltraFocusLocked = false;
      _completedPomodoroCount++;
      _extraPomodoroMinutes[subj] =
          (_extraPomodoroMinutes[subj] ?? 0) + completedMins;
    });
    await FocusLockService.instance.disableNativeAppLock();

    if (_ultraSyncBothDevices) {
      FocusLockService.instance.broadcastLockSignal(
        FocusLockPayload(
          type: 'LOCK_COMPLETE',
          pairingCode: _pairingCode,
          subject: _lockedSubject,
          title: _lockedTitle,
          remainingSeconds: 0,
          totalSeconds: _lockTotalSeconds,
          sourceDevice: FocusLockService.instance.deviceId,
        ),
      );
    }
    await _persistAndBroadcastAllChanges();

    _showInAppAlertToast(
      title: '🎉 [$_lockedSubject] 최대 집중 모드 목표 달성! (+$completedMins분)',
      message: '주간 통계에 반영되었으며 S25와 탭 S10 Ultra의 잠금이 해제되었습니다.',
      color: const Color(0xFF059669),
    );
  }

  Future<void> _unlockByEmergencyMasterKey() async {
    setState(() {
      _isUltraFocusLocked = false;
    });
    await FocusLockService.instance.disableNativeAppLock();
    if (_ultraSyncBothDevices) {
      FocusLockService.instance.broadcastLockSignal(
        FocusLockPayload(
          type: 'EMERGENCY_UNLOCK',
          pairingCode: _pairingCode,
          subject: _lockedSubject,
          title: _lockedTitle,
          remainingSeconds: 0,
          totalSeconds: _lockTotalSeconds,
          sourceDevice: FocusLockService.instance.deviceId,
        ),
      );
    }
    _showInAppAlertToast(
      title: '🔑 비상 마스터 키 인증 완료 — 동시 잠금 해제',
      message: '갤럭시 S25 및 갤럭시 탭 S10 Ultra의 앱 잠금이 즉시 해제되었습니다.',
      color: Colors.indigo,
    );
  }

  /// 주간 목표 미달 과목 요약 문자열 리스트 반환 (시간표 + 뽀모도로 자유 공부시간 합산)
  List<String> _getUnderTargetWarnings() {
    final Map<String, int> weeklyActual = {..._extraPomodoroMinutes};
    for (int d = 1; d <= 7; d++) {
      for (final b in _getWeeklyBlocksForWeekday(d)) {
        weeklyActual[b.subject] =
            (weeklyActual[b.subject] ?? 0) + b.durationMinutes;
      }
    }
    final warnings = <String>[];
    for (final g in _weeklyGoals) {
      final actual = weeklyActual[g.subject] ?? 0;
      if (actual < g.targetMinutes) {
        final diff = g.targetMinutes - actual;
        final h = diff ~/ 60;
        final m = diff % 60;
        final diffStr = h > 0 ? '${h}시간${m > 0 ? " ${m}분" : ""}' : '${m}분';
        warnings.add('${g.subject}($diffStr 부족)');
      }
    }
    return warnings;
  }

  Future<void> _updateSubjectWeeklyGoal(
      String subject, int newTargetMinutes, int colorValue) async {
    setState(() {
      final idx = _weeklyGoals.indexWhere((g) => g.subject == subject);
      if (idx >= 0) {
        _weeklyGoals[idx] =
            _weeklyGoals[idx].copyWith(targetMinutes: newTargetMinutes);
      } else {
        _weeklyGoals.add(
          SubjectWeeklyGoal(
            subject: subject,
            targetMinutes: newTargetMinutes,
            colorValue: colorValue,
          ),
        );
      }
    });
    await _persistAndBroadcastAllChanges();
  }

  Future<void> _assignDeficitBlockToday(
      String subject, int deficitMinutes, int colorValue) async {
    final todayBlocks = _getEffectiveBlocksForDate(_now);
    final nowMins = _now.hour * 60 + _now.minute;
    int startMins = (nowMins + 5).clamp(0, 22 * 60 + 30);

    for (final b in todayBlocks) {
      if (b.endMinutes > startMins && b.startMinutes <= startMins + 30) {
        startMins = (b.endMinutes + 10).clamp(0, 22 * 60 + 50);
      }
    }
    final dur = deficitMinutes.clamp(30, 90);
    final endMins = (startMins + dur).clamp(startMins + 15, 23 * 60 + 59);

    final newBlock = StudyBlock(
      id: _uuid.v4(),
      subject: subject,
      title: '[주간 목표 미달 보충] $subject 집중 보충 학습',
      memo: '1주일 목표 시간을 채우기 위해 자동 배정된 필수 보충 블록입니다.',
      colorValue: colorValue,
      startMinutes: startMins,
      endMinutes: endMins,
      weekdays: [_now.weekday],
      notifyOnStart: true,
      notifyBeforeEndMinutes: 5,
      checklist: [
        ChecklistItem(
          id: _uuid.v4(),
          text: '$subject 주간 목표 부족분 ${dur}분 완전 정복하기',
        ),
      ],
    );

    setState(() {
      _allBlocks.add(newBlock);
      _tabController.animateTo(0);
    });
    await _persistAndBroadcastAllChanges();

    _showInAppAlertToast(
      title: '⚡ [$subject] 오늘 보충 공부 시간 강제 배정 완료!',
      message: '${newBlock.formattedTimeRange} (${dur}분)에 추가되었으며 연동 기기에도 동기화되었습니다.',
      color: Color(colorValue),
    );
  }

  List<StudyBlock> _getEffectiveBlocksForDate(DateTime date) {
    final dateStr = ScheduleStorage.formatDate(date);
    final weekday = date.weekday;
    final isOverrideOnly = _customOverrideDates.contains(dateStr);

    final filtered = _allBlocks.where((b) {
      if (b.specificDate != null) {
        return b.specificDate == dateStr;
      }
      if (isOverrideOnly) {
        return false;
      }
      return b.weekdays.contains(weekday);
    }).toList();

    filtered.sort((a, b) => a.startMinutes.compareTo(b.startMinutes));
    return filtered;
  }

  List<StudyBlock> _getWeeklyBlocksForWeekday(int weekday) {
    final filtered = _allBlocks
        .where((b) => b.specificDate == null && b.weekdays.contains(weekday))
        .toList();
    filtered.sort((a, b) => a.startMinutes.compareTo(b.startMinutes));
    return filtered;
  }

  StudyBlock? _getCurrentActiveBlock(List<StudyBlock> todayBlocks) {
    for (final b in todayBlocks) {
      if (b.isActiveAt(_now)) return b;
    }
    return null;
  }

  StudyBlock? _getNextUpcomingBlock(List<StudyBlock> todayBlocks) {
    final nowMins = _now.hour * 60 + _now.minute;
    for (final b in todayBlocks) {
      if (b.startMinutes > nowMins) return b;
    }
    return null;
  }

  Future<void> _syncNotificationsAndWidget() async {
    final todayBlocks = _getEffectiveBlocksForDate(_now);
    final currentBlock = _getCurrentActiveBlock(todayBlocks);
    final nextBlock = _getNextUpcomingBlock(todayBlocks);
    final warnings = _getUnderTargetWarnings();

    await NotificationService.instance
        .rescheduleTodayNotifications(todayBlocks);
    await NotificationService.instance.updateOngoingStudyNotification(
      currentBlock: currentBlock,
      nextBlock: nextBlock,
      now: _now,
    );
    await WidgetService.instance.updateHomeScreenWidget(
      currentBlock: currentBlock,
      nextBlock: nextBlock,
      todayBlocks: todayBlocks,
      underTargetWarnings: warnings,
      now: _now,
    );
  }

  void _checkRealtimeTransitions(DateTime now) {
    final todayBlocks = _getEffectiveBlocksForDate(now);
    final nowMins = now.hour * 60 + now.minute;

    if (nowMins != _lastWidgetSyncMinute) {
      _lastWidgetSyncMinute = nowMins;
      final currentBlock = _getCurrentActiveBlock(todayBlocks);
      final nextBlock = _getNextUpcomingBlock(todayBlocks);
      WidgetService.instance.updateHomeScreenWidget(
        currentBlock: currentBlock,
        nextBlock: nextBlock,
        todayBlocks: todayBlocks,
        underTargetWarnings: _getUnderTargetWarnings(),
        now: now,
      );
      NotificationService.instance.updateOngoingStudyNotification(
        currentBlock: currentBlock,
        nextBlock: nextBlock,
        now: now,
      );
    }

    if (now.second == 0) {
      for (final block in todayBlocks) {
        if (block.notifyOnStart && block.startMinutes == nowMins) {
          final key = 'start_${block.id}_$nowMins';
          if (_lastAlertKey != key) {
            _lastAlertKey = key;
            _showInAppAlertToast(
              title: '📚 [${block.subject}] 시작 시간입니다!',
              message: '${block.formattedTimeRange} | ${block.title}',
              color: block.color,
            );
          }
        }
        // 🔒 스케줄별 강제집중(autoFocusLock)이 켜져 있으면 시작 정각에 자동으로 강제집중 잠금 실행!
        if (block.autoFocusLock &&
            block.startMinutes == nowMins &&
            !_isUltraFocusLocked) {
          final lockKey =
              'autolock_${ScheduleStorage.formatDate(now)}_${block.id}_$nowMins';
          if (!_autoLockedBlockKeys.contains(lockKey)) {
            _autoLockedBlockKeys.add(lockKey);
            final durSecs = block.remainingSecondsAt(now).clamp(60, 86400);
            _startUltraFocusLock(
              subject: block.subject,
              title: '[스케줄 자동 강제집중] ${block.title}',
              color: block.color,
              durationSeconds: durSecs,
              syncBothDevices: block.lockSyncBothDevices,
            );
          }
        }
        if (block.notifyBeforeEndMinutes > 0 &&
            block.endMinutes - block.notifyBeforeEndMinutes == nowMins) {
          final key = 'warn_${block.id}_$nowMins';
          if (_lastAlertKey != key) {
            _lastAlertKey = key;
            _showInAppAlertToast(
              title:
                  '⏰ [${block.subject}] 종료 ${block.notifyBeforeEndMinutes}분 전!',
              message: '${block.title} 마무리 및 다음 공부를 준비하세요.',
              color: Colors.deepOrange,
            );
          }
        }
      }
    }
  }

  void _showInAppAlertToast({
    required String title,
    required String message,
    required Color color,
  }) {
    SystemSound.play(SystemSoundType.alert);
    HapticFeedback.heavyImpact();
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: color,
        duration: const Duration(seconds: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 15,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              message,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  /// 기기 전체 동기화(시간표/오늘계획/주간목표/통계) & 비상 해제 마스터 키 설정 모달
  void _openSecurityAndSyncDialog() {
    final keyCtrl = TextEditingController(text: _emergencyMasterKey);
    final codeCtrl = TextEditingController(text: _pairingCode);

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text(
            '🔄 S25 ↔ 탭 S10 전체 연동 & 비상 키 설정',
            style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w900),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '1. 갤럭시 S25 ↔ 갤럭시 탭 S10 Ultra 전체 동기화 코드\n'
                  '두 기기에 동일한 연동 코드를 넣어두면 [오늘의 계획, 요일 시간표, 주간 목표, 공부 통계, 최대 집중 잠금]이 모두 실시간 동기화됩니다.',
                  style: TextStyle(fontSize: 12, color: Colors.black87),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: codeCtrl,
                  decoration: const InputDecoration(
                    labelText: '기기 연동 코드',
                    hintText: '예: S25-TAB10',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          final snap = _buildCurrentSyncSnapshotMap();
                          FocusLockService.instance.broadcastFullDataSync(snap);
                          FocusLockService.instance.requestFullSyncFromPeer();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                  '🔄 같은 네트워크의 S25 ↔ 탭 S10 Ultra 간 전체 데이터를 즉시 동기화했습니다!'),
                            ),
                          );
                        },
                        icon: const Icon(Icons.sync, size: 16),
                        label: const Text(
                          '지금 즉시 무선 동기화',
                          style: TextStyle(
                              fontSize: 11.5, fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: TextButton.icon(
                        onPressed: () async {
                          final snap = _buildCurrentSyncSnapshotMap();
                          final encoded =
                              base64Encode(utf8.encode(jsonEncode(snap)));
                          await Clipboard.setData(ClipboardData(text: encoded));
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                    '📋 전체 데이터 코드가 복사되었습니다! 다른 기기(삼성 클립보드 공유)에서 [붙여넣기 복원]을 누르세요.'),
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.copy, size: 15),
                        label: const Text('데이터 복사(클립보드)',
                            style: TextStyle(fontSize: 11.5)),
                      ),
                    ),
                    Expanded(
                      child: TextButton.icon(
                        onPressed: () async {
                          final clip =
                              await Clipboard.getData(Clipboard.kTextPlain);
                          final raw = clip?.text?.trim() ?? '';
                          if (raw.isEmpty) return;
                          try {
                            final jsonStr = utf8.decode(base64Decode(raw));
                            final map =
                                jsonDecode(jsonStr) as Map<String, dynamic>;
                            await _applyIncomingSyncSnapshot(map);
                            if (ctx.mounted) {
                              Navigator.of(ctx).pop();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                      '✅ 다른 기기의 시간표·목표·통계 데이터를 성공적으로 불러왔습니다!'),
                                ),
                              );
                            }
                          } catch (_) {
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('유효한 동기화 코드가 아닙니다.'),
                                ),
                              );
                            }
                          }
                        },
                        icon: const Icon(Icons.paste, size: 15),
                        label: const Text('데이터 붙여넣기 복원',
                            style: TextStyle(fontSize: 11.5)),
                      ),
                    ),
                  ],
                ),
                const Divider(height: 20),
                const Text(
                  '2. 예측하지 못한 긴급 상황용 비상 마스터 키\n'
                  '최대 집중 모드 작동 중 불가피하게 잠금을 풀어야 할 때 사용하는 비밀 키입니다.',
                  style: TextStyle(fontSize: 12, color: Colors.black87),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: keyCtrl,
                  decoration: const InputDecoration(
                    labelText: '비상 해제 마스터 키',
                    hintText: '예: 1129',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () async {
                final newKey = keyCtrl.text.trim().isEmpty
                    ? '1129'
                    : keyCtrl.text.trim();
                final newCode = codeCtrl.text.trim().isEmpty
                    ? 'S25-TAB10'
                    : codeCtrl.text.trim().toUpperCase();
                setState(() {
                  _emergencyMasterKey = newKey;
                  _pairingCode = newCode;
                });
                FocusLockService.instance.updatePairingCode(newCode);
                await _storage.saveEmergencyMasterKey(newKey);
                await _storage.saveDevicePairingCode(newCode);
                await _persistAndBroadcastAllChanges();
                if (ctx.mounted) Navigator.of(ctx).pop();
              },
              child: const Text('저장 및 동기화'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openEditor({
    StudyBlock? existing,
    required bool defaultToDailyPlan,
  }) async {
    final targetDateStr = ScheduleStorage.formatDate(_selectedDate);
    final targetWeekday = _tabController.index == 0
        ? _selectedDate.weekday
        : _selectedWeekday;

    final result = await showModalBottomSheet<StudyBlock>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 640),
      backgroundColor: Colors.transparent,
      builder: (_) => StudyBlockEditorSheet(
        existingBlock: existing,
        defaultToDailyPlan: defaultToDailyPlan,
        targetDateStr: targetDateStr,
        targetWeekday: targetWeekday,
      ),
    );

    if (result != null) {
      setState(() {
        final idx = _allBlocks.indexWhere((b) => b.id == result.id);
        if (idx >= 0) {
          _allBlocks[idx] = result;
        } else {
          _allBlocks.add(result);
        }
      });
      await _persistAndBroadcastAllChanges();
    }
  }

  Future<void> _deleteBlock(StudyBlock block) async {
    setState(() {
      _allBlocks.removeWhere((b) => b.id == block.id);
    });
    await _persistAndBroadcastAllChanges();
  }

  Future<void> _toggleChecklistItem(
      StudyBlock block, String checklistId) async {
    final updatedChecklist = block.checklist.map((item) {
      if (item.id == checklistId) {
        return item.copyWith(isDone: !item.isDone);
      }
      return item;
    }).toList();

    final updatedBlock = block.copyWith(checklist: updatedChecklist);
    setState(() {
      final idx = _allBlocks.indexWhere((b) => b.id == block.id);
      if (idx >= 0) {
        _allBlocks[idx] = updatedBlock;
      }
    });
    await _persistAndBroadcastAllChanges();
  }

  /// 🔒 스케줄 카드에서 원터치로 해당 스케줄의 강제집중(autoFocusLock) ON/OFF 토글
  Future<void> _toggleBlockAutoFocusLock(StudyBlock block) async {
    final updatedBlock = block.copyWith(autoFocusLock: !block.autoFocusLock);
    setState(() {
      final idx = _allBlocks.indexWhere((b) => b.id == block.id);
      if (idx >= 0) {
        _allBlocks[idx] = updatedBlock;
      }
    });
    await _persistAndBroadcastAllChanges();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          updatedBlock.autoFocusLock
              ? '🔒 [${updatedBlock.subject}] (${updatedBlock.formattedTimeRange}) 시작 시 자동 강제집중 잠금이 켜졌습니다!'
              : '🔓 [${updatedBlock.subject}] 스케줄 자동 강제집중이 해제되었습니다.',
        ),
      ),
    );
  }

  /// 📷 손으로 적은 플래너 시간표 사진 촬영/스캔 → 오늘의 스케줄표에 일괄 등록
  Future<void> _openHandwrittenPlannerScanner() async {
    final targetDateStr = ScheduleStorage.formatDate(_selectedDate);
    final result = await showModalBottomSheet<
        ({List<StudyBlock> blocks, bool replaceExistingTodayPlan})>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 720),
      backgroundColor: Colors.transparent,
      builder: (_) => HandwrittenPlannerScannerSheet(
        targetDateStr: targetDateStr,
      ),
    );

    if (result == null || result.blocks.isEmpty) return;

    setState(() {
      if (result.replaceExistingTodayPlan) {
        _allBlocks.removeWhere((b) => b.specificDate == targetDateStr);
        _customOverrideDates.add(targetDateStr);
      }
      _allBlocks.addAll(result.blocks);
      _tabController.animateTo(0);
    });

    await _persistAndBroadcastAllChanges();

    if (!mounted) return;
    _showInAppAlertToast(
      title: '📷 손글씨 플래너 ${result.blocks.length}개 블록 스캔 등록 완료!',
      message: '오늘의 스케줄표에 반영되었으며 S25 ↔ 탭 S10 Ultra 및 홈 위젯에 즉시 동기화되었습니다.',
      color: const Color(0xFF4F46E5),
    );
  }

  Future<void> _copyWeeklyToDailyCustomPlan(DateTime date) async {
    final dateStr = ScheduleStorage.formatDate(date);
    final weekday = date.weekday;
    final weeklyBlocks = _getWeeklyBlocksForWeekday(weekday);

    setState(() {
      for (final wb in weeklyBlocks) {
        _allBlocks.add(
          wb.copyWith(
            id: _uuid.v4(),
            weekdays: [],
            specificDate: dateStr,
          ),
        );
      }
      _customOverrideDates.add(dateStr);
    });

    await _persistAndBroadcastAllChanges();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          '오늘만의 일일 계획 모드로 전환되었습니다! S25와 탭 S10 Ultra에 동시 반영됩니다.',
        ),
      ),
    );
  }

  Future<void> _resetDailyCustomPlanToWeekly(DateTime date) async {
    final dateStr = ScheduleStorage.formatDate(date);
    setState(() {
      _allBlocks.removeWhere((b) => b.specificDate == dateStr);
      _customOverrideDates.remove(dateStr);
    });
    await _persistAndBroadcastAllChanges();
  }

  Future<void> _handlePomodoroSessionCompleted(
      String subject, int completedFocusMinutes) async {
    setState(() {
      _completedPomodoroCount++;
      _extraPomodoroMinutes[subject] =
          (_extraPomodoroMinutes[subject] ?? 0) + completedFocusMinutes;
    });
    await _persistAndBroadcastAllChanges();
  }

  @override
  Widget build(BuildContext context) {
    final todayBlocks = _getEffectiveBlocksForDate(_now);
    final currentBlock = _getCurrentActiveBlock(todayBlocks);
    final nextBlock = _getNextUpcomingBlock(todayBlocks);
    final underTargetWarnings = _getUnderTargetWarnings();

    return Stack(
      children: [
        Scaffold(
          backgroundColor: const Color(0xFFF8FAFC),
          appBar: AppBar(
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.white,
            elevation: 0,
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.indigo.shade600,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child:
                      const Icon(Icons.schedule, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '나만의 공부 시간표',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontWeight: FontWeight.w900, fontSize: 16.5),
                      ),
                      Text(
                        '${_now.month}/${_now.day}(${_weekdayNames[_now.weekday - 1]}) ${StudyBlock.formatMinutes(_now.hour * 60 + _now.minute)} • 🔗$_pairingCode 동기화중',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11, color: Colors.indigo.shade700),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              IconButton(
                tooltip: '손글씨 플래너 찍어서 스캔',
                onPressed: _openHandwrittenPlannerScanner,
                icon: const Icon(
                  Icons.document_scanner_rounded,
                  color: Color(0xFF4F46E5),
                ),
              ),
              IconButton(
                tooltip: 'S25 ↔ 탭 S10 즉시 동기화',
                onPressed: () {
                  final snap = _buildCurrentSyncSnapshotMap();
                  FocusLockService.instance.broadcastFullDataSync(snap);
                  FocusLockService.instance.requestFullSyncFromPeer();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                          '🔄 갤럭시 S25 ↔ 탭 S10 Ultra 전체 데이터(시간표·목표·통계)를 동기화했습니다.'),
                    ),
                  );
                },
                icon: const Icon(Icons.sync_rounded),
              ),
              IconButton(
                tooltip: '앱 안에서 바로 덮어쓰기 업데이트',
                onPressed: _openAppUpdateDialog,
                icon: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Icon(Icons.system_update_rounded),
                    if (_latestRelease != null &&
                        _latestRelease!.isNewerThan(
                            AppUpdateService.currentBuildNumber))
                      Positioned(
                        right: -2,
                        top: -2,
                        child: Container(
                          width: 9,
                          height: 9,
                          decoration: const BoxDecoration(
                            color: Color(0xFFEF4444),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '연동 코드 & 비상 키 설정',
                onPressed: _openSecurityAndSyncDialog,
                icon: const Icon(Icons.phonelink_lock_rounded),
              ),
              FilledButton.tonalIcon(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (_) => WidgetPreviewDialog(
                      currentBlock: currentBlock,
                      nextBlock: nextBlock,
                      todayBlocks: todayBlocks,
                      underTargetWarnings: underTargetWarnings,
                      now: _now,
                      onSyncWidget: () {
                        _syncNotificationsAndWidget();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('홈 화면 위젯과 알림이 최신 상태로 동기화되었습니다.'),
                          ),
                        );
                      },
                    ),
                  );
                },
                icon: const Icon(Icons.widgets_outlined, size: 18),
                label: const Text('위젯'),
              ),
              const SizedBox(width: 10),
            ],
          ),
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isTabletWide = constraints.maxWidth >= 840;
                if (isTabletWide) {
                  return _buildGalaxyTabS10UltraLayout(
                    currentBlock: currentBlock,
                    nextBlock: nextBlock,
                  );
                }
                return _buildGalaxyS25PhoneLayout(
                  currentBlock: currentBlock,
                  nextBlock: nextBlock,
                );
              },
            ),
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () {
              _openEditor(
                defaultToDailyPlan: _tabController.index == 0 &&
                    _customOverrideDates
                        .contains(ScheduleStorage.formatDate(_selectedDate)),
              );
            },
            backgroundColor: Colors.indigo.shade600,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.add_alarm),
            label: const Text(
              '내 마음대로 공부 시간 추가',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ),

        // 🔒 최대 집중 모드 작동 중일 때 전체화면 앱 차단 오버레이
        if (_isUltraFocusLocked)
          Positioned.fill(
            child: UltraFocusLockOverlay(
              subject: _lockedSubject,
              title: _lockedTitle,
              accentColor: _lockedColor,
              remainingSeconds: _lockRemainingSeconds,
              totalSeconds: _lockTotalSeconds,
              pairingCode: _pairingCode,
              syncBothDevices: _ultraSyncBothDevices,
              emergencyMasterKey: _emergencyMasterKey,
              activeBlock: currentBlock,
              onToggleChecklist: _toggleChecklistItem,
              onEmergencyUnlockSuccess: _unlockByEmergencyMasterKey,
            ),
          ),
      ],
    );
  }

  /// 📟 갤럭시 탭 S10 Ultra (14.6인치 WQXGA+ 대화면 / DeX 모드) 전용 2-Pane 대시보드 레이아웃
  Widget _buildGalaxyTabS10UltraLayout({
    required StudyBlock? currentBlock,
    required StudyBlock? nextBlock,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 430,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 100),
            children: [
              ActiveStudyHeroCard(
                currentBlock: currentBlock,
                nextBlock: nextBlock,
                now: _now,
                onToggleChecklist: _toggleChecklistItem,
                onEditCurrent: () {
                  if (currentBlock != null) {
                    _openEditor(
                      existing: currentBlock,
                      defaultToDailyPlan: currentBlock.specificDate != null,
                    );
                  }
                },
                onTestNotification: () =>
                    _triggerManualTestNotification(currentBlock),
              ),
              const SizedBox(height: 16),
              PomodoroTimerCard(
                currentBlock: currentBlock,
                pairingCode: _pairingCode,
                emergencyMasterKey: _emergencyMasterKey,
                completedPomodoros: _completedPomodoroCount,
                onOpenSecuritySettings: _openSecurityAndSyncDialog,
                onPomodoroSessionCompleted: _handlePomodoroSessionCompleted,
                onStartUltraFocusLock: ({
                  required String subject,
                  required String title,
                  required Color color,
                  required int durationSeconds,
                  required bool syncBothDevices,
                }) {
                  _startUltraFocusLock(
                    subject: subject,
                    title: title,
                    color: color,
                    durationSeconds: durationSeconds,
                    syncBothDevices: syncBothDevices,
                  );
                },
                onPhaseFinished: (title, msg, color) {
                  NotificationService.instance
                      .showTestNotification(currentBlock);
                  _showInAppAlertToast(
                    title: title,
                    message: msg,
                    color: color,
                  );
                },
              ),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: Column(
            children: [
              Container(
                color: Colors.white,
                child: TabBar(
                  controller: _tabController,
                  labelColor: Colors.indigo.shade700,
                  unselectedLabelColor: Colors.grey.shade600,
                  indicatorColor: Colors.indigo.shade700,
                  labelStyle: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                  tabs: const [
                    Tab(text: '📅 오늘/날짜별 공부 계획'),
                    Tab(text: '🔁 요일별 기본 시간표'),
                    Tab(text: '🎯 주간 목표 & 통계'),
                  ],
                ),
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildDailyScheduleTab(),
                    _buildWeeklyRoutineTab(),
                    WeeklySubjectStatsView(
                      getBlocksForWeekday: _getWeeklyBlocksForWeekday,
                      weeklyGoals: _weeklyGoals,
                      extraPomodoroMinutes: _extraPomodoroMinutes,
                      currentWeekday: _now.weekday,
                      onUpdateSubjectGoal: _updateSubjectWeeklyGoal,
                      onAssignDeficitBlockToday: _assignDeficitBlockToday,
                      onStartEnforcedFocusNow: (subj, mins, col) {
                        _startUltraFocusLock(
                          subject: subj,
                          title: '[$subj] 주간 목표 미달 강제 집중 학습',
                          color: Color(col),
                          durationSeconds: mins * 60,
                          syncBothDevices: true,
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 📱 갤럭시 S25 (스마트폰 한 손 조작 & 19.5:9 비율) 최적화 레이아웃
  Widget _buildGalaxyS25PhoneLayout({
    required StudyBlock? currentBlock,
    required StudyBlock? nextBlock,
  }) {
    return NestedScrollView(
      headerSliverBuilder: (context, innerBoxIsScrolled) {
        return [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                children: [
                  ActiveStudyHeroCard(
                    currentBlock: currentBlock,
                    nextBlock: nextBlock,
                    now: _now,
                    onToggleChecklist: _toggleChecklistItem,
                    onEditCurrent: () {
                      if (currentBlock != null) {
                        _openEditor(
                          existing: currentBlock,
                          defaultToDailyPlan: currentBlock.specificDate != null,
                        );
                      }
                    },
                    onTestNotification: () =>
                        _triggerManualTestNotification(currentBlock),
                  ),
                  const SizedBox(height: 12),
                  PomodoroTimerCard(
                    currentBlock: currentBlock,
                    pairingCode: _pairingCode,
                    emergencyMasterKey: _emergencyMasterKey,
                    completedPomodoros: _completedPomodoroCount,
                    onOpenSecuritySettings: _openSecurityAndSyncDialog,
                    onPomodoroSessionCompleted: _handlePomodoroSessionCompleted,
                    onStartUltraFocusLock: ({
                      required String subject,
                      required String title,
                      required Color color,
                      required int durationSeconds,
                      required bool syncBothDevices,
                    }) {
                      _startUltraFocusLock(
                        subject: subject,
                        title: title,
                        color: color,
                        durationSeconds: durationSeconds,
                        syncBothDevices: syncBothDevices,
                      );
                    },
                    onPhaseFinished: (title, msg, color) {
                      NotificationService.instance
                          .showTestNotification(currentBlock);
                      _showInAppAlertToast(
                        title: title,
                        message: msg,
                        color: color,
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          SliverPersistentHeader(
            pinned: true,
            delegate: _SliverTabBarDelegate(
              TabBar(
                controller: _tabController,
                labelColor: Colors.indigo.shade700,
                unselectedLabelColor: Colors.grey.shade600,
                indicatorColor: Colors.indigo.shade700,
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
                tabs: const [
                  Tab(text: '📅 오늘 계획'),
                  Tab(text: '🔁 요일 시간표'),
                  Tab(text: '🎯 목표 & 통계'),
                ],
              ),
            ),
          ),
        ];
      },
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildDailyScheduleTab(),
          _buildWeeklyRoutineTab(),
          WeeklySubjectStatsView(
            getBlocksForWeekday: _getWeeklyBlocksForWeekday,
            weeklyGoals: _weeklyGoals,
            extraPomodoroMinutes: _extraPomodoroMinutes,
            currentWeekday: _now.weekday,
            onUpdateSubjectGoal: _updateSubjectWeeklyGoal,
            onAssignDeficitBlockToday: _assignDeficitBlockToday,
            onStartEnforcedFocusNow: (subj, mins, col) {
              _startUltraFocusLock(
                subject: subj,
                title: '[$subj] 주간 목표 미달 강제 집중 학습',
                color: Color(col),
                durationSeconds: mins * 60,
                syncBothDevices: true,
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _triggerManualTestNotification(StudyBlock? currentBlock) async {
    await NotificationService.instance.showTestNotification(currentBlock);
    _showInAppAlertToast(
      title: currentBlock != null
          ? '📚 [${currentBlock.subject}] 지금 해야 할 공부 알림'
          : '🔔 공부 시간표 알림 테스트',
      message: currentBlock != null
          ? '${currentBlock.formattedTimeRange} | ${currentBlock.title}'
          : '시작 시간 정각 및 종료 전 알림이 사운드+팝업으로 울립니다!',
      color: currentBlock?.color ?? Colors.indigo,
    );
  }

  Widget _buildDailyScheduleTab() {
    final dateStr = ScheduleStorage.formatDate(_selectedDate);
    final isCustomOverride = _customOverrideDates.contains(dateStr);
    final blocks = _getEffectiveBlocksForDate(_selectedDate);
    final totalStudyMins =
        blocks.fold<int>(0, (sum, b) => sum + b.durationMinutes);
    final underTargetWarnings = _getUnderTargetWarnings();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      children: [
        if (underTargetWarnings.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.priority_high_rounded,
                    color: Colors.red.shade700, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '주간 목표 미달: ${underTargetWarnings.join(", ")}',
                    style: TextStyle(
                      color: Colors.red.shade900,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => _tabController.animateTo(2),
                  child: const Text(
                    '보충 배정 →',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),

        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: () {
                          setState(() {
                            _selectedDate = _selectedDate
                                .subtract(const Duration(days: 1));
                          });
                        },
                        icon: const Icon(Icons.chevron_left),
                      ),
                      Text(
                        '${_selectedDate.month}월 ${_selectedDate.day}일 (${_weekdayNames[_selectedDate.weekday - 1]}요일)',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: () {
                          setState(() {
                            _selectedDate =
                                _selectedDate.add(const Duration(days: 1));
                          });
                        },
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.indigo.shade50,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      '총 ${totalStudyMins ~/ 60}시간 ${totalStudyMins % 60}분',
                      style: TextStyle(
                        color: Colors.indigo.shade700,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const Divider(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      isCustomOverride
                          ? '✨ [오늘만의 일일 계획 모드] 기본 요일 시간표와 별개로 이 날짜만 자유롭게 편집 중입니다.'
                          : '🔁 기본 ${_weekdayNames[_selectedDate.weekday - 1]}요일 시간표 + 이 날짜 추가 계획이 함께 표시됩니다.',
                      style: TextStyle(
                        fontSize: 12,
                        color: isCustomOverride
                            ? Colors.indigo.shade800
                            : Colors.grey.shade700,
                        fontWeight: isCustomOverride
                            ? FontWeight.w700
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (!isCustomOverride)
                    OutlinedButton.icon(
                      onPressed: () =>
                          _copyWeeklyToDailyCustomPlan(_selectedDate),
                      icon: const Icon(Icons.edit_calendar, size: 16),
                      label: const Text(
                        '오늘만 따로 수정',
                        style: TextStyle(fontSize: 12),
                      ),
                    )
                  else
                    TextButton.icon(
                      onPressed: () =>
                          _resetDailyCustomPlanToWeekly(_selectedDate),
                      icon: const Icon(Icons.restore, size: 16),
                      label: const Text(
                        '요일 기본으로 복원',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _openHandwrittenPlannerScanner,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF4F46E5),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.document_scanner_rounded, size: 18),
                  label: const Text(
                    '📷 손으로 적은 플래너 찍어서 오늘의 스케줄표에 바로 넣기',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (blocks.isEmpty)
          _buildEmptySchedulePlaceholder()
        else
          ..._buildTimelineList(blocks, highlightCurrent: true),
      ],
    );
  }

  Widget _buildWeeklyRoutineTab() {
    final blocks = _getWeeklyBlocksForWeekday(_selectedWeekday);
    final totalMins =
        blocks.fold<int>(0, (sum, b) => sum + b.durationMinutes);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(7, (idx) {
            final day = idx + 1;
            final isSelected = day == _selectedWeekday;
            final isToday = day == _now.weekday;
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: InkWell(
                  onTap: () => setState(() => _selectedWeekday = day),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.indigo.shade600 : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected
                            ? Colors.indigo.shade600
                            : (isToday
                                ? Colors.indigo.shade300
                                : Colors.grey.shade300),
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(
                          _weekdayNames[idx],
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: isSelected ? Colors.white : Colors.black87,
                          ),
                        ),
                        if (isToday)
                          Text(
                            '오늘',
                            style: TextStyle(
                              fontSize: 10,
                              color: isSelected
                                  ? Colors.amberAccent
                                  : Colors.indigo,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '매주 ${_weekdayNames[_selectedWeekday - 1]}요일 고정 공부 시간표 (${blocks.length}개 블록)',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              Text(
                '총 ${totalMins ~/ 60}시간 ${totalMins % 60}분',
                style: TextStyle(
                  color: Colors.indigo.shade700,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        if (blocks.isEmpty)
          _buildEmptySchedulePlaceholder()
        else
          ..._buildTimelineList(
            blocks,
            highlightCurrent: _selectedWeekday == _now.weekday,
          ),
      ],
    );
  }

  List<Widget> _buildTimelineList(
    List<StudyBlock> blocks, {
    required bool highlightCurrent,
  }) {
    final List<Widget> items = [];

    for (int i = 0; i < blocks.length; i++) {
      final block = blocks[i];
      final isActive = highlightCurrent && block.isActiveAt(_now);

      if (i > 0) {
        final prevEnd = blocks[i - 1].endMinutes;
        final gap = block.startMinutes - prevEnd;
        if (gap > 0) {
          items.add(
            Padding(
              padding: const EdgeInsets.only(left: 24, bottom: 8),
              child: Row(
                children: [
                  Container(
                    width: 2,
                    height: 22,
                    color: Colors.grey.shade300,
                  ),
                  const SizedBox(width: 12),
                  Icon(Icons.coffee_outlined,
                      size: 14, color: Colors.grey.shade500),
                  const SizedBox(width: 6),
                  Text(
                    '쉬는 시간 / 여유 시간 (${gap}분: ${StudyBlock.formatMinutes(prevEnd)} ~ ${StudyBlock.formatMinutes(block.startMinutes)})',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          );
        } else if (gap < 0) {
          items.add(
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                '⚠️ 이전 공부 블록과 시간이 ${-gap}분 겹칩니다.',
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.redAccent,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          );
        }
      }

      items.add(_buildBlockTimelineCard(block, isActive: isActive));
    }

    return items;
  }

  Widget _buildBlockTimelineCard(StudyBlock block, {required bool isActive}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isActive ? block.color : Colors.grey.shade200,
          width: isActive ? 2.2 : 1,
        ),
        boxShadow: [
          if (isActive)
            BoxShadow(
              color: block.color.withValues(alpha: 0.16),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: block.color,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    block.subject,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  block.formattedTimeRange,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '(${block.formattedDuration})',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (isActive) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade100,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      '진행 중',
                      style: TextStyle(
                        color: Colors.amber.shade900,
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.edit_outlined, size: 19),
                  tooltip: '수정',
                  onPressed: () => _openEditor(
                    existing: block,
                    defaultToDailyPlan: block.specificDate != null,
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.delete_outline,
                      size: 19, color: Colors.redAccent),
                  tooltip: '삭제',
                  onPressed: () => _deleteBlock(block),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              block.title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (block.memo.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                block.memo,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade700,
                ),
              ),
            ],
            if (block.checklist.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: block.checklist.map((item) {
                    return InkWell(
                      onTap: () => _toggleChecklistItem(block, item.id),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            Icon(
                              item.isDone
                                  ? Icons.check_box
                                  : Icons.check_box_outline_blank,
                              size: 18,
                              color: item.isDone
                                  ? block.color
                                  : Colors.grey.shade500,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                item.text,
                                style: TextStyle(
                                  fontSize: 13,
                                  decoration: item.isDone
                                      ? TextDecoration.lineThrough
                                      : null,
                                  color: item.isDone
                                      ? Colors.grey.shade500
                                      : Colors.black87,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
            const SizedBox(height: 10),
            // 🔒 스케줄표별 강제집중 원터치 활성화 바 & 즉시 잠금 시작 버튼
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: block.autoFocusLock
                    ? const Color(0xFFFEF2F2)
                    : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: block.autoFocusLock
                      ? const Color(0xFFFCA5A5)
                      : Colors.grey.shade200,
                ),
              ),
              child: Row(
                children: [
                  InkWell(
                    onTap: () => _toggleBlockAutoFocusLock(block),
                    borderRadius: BorderRadius.circular(8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          block.autoFocusLock
                              ? Icons.lock_clock_rounded
                              : Icons.lock_open_rounded,
                          size: 17,
                          color: block.autoFocusLock
                              ? const Color(0xFFDC2626)
                              : Colors.blueGrey.shade600,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          block.autoFocusLock
                              ? '스케줄 강제집중 ON (시작 시 자동 잠금)'
                              : '스케줄 강제집중 OFF (눌러서 켜기)',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: block.autoFocusLock
                                ? const Color(0xFFDC2626)
                                : Colors.blueGrey.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  FilledButton.tonalIcon(
                    onPressed: () {
                      final durSecs = isActive
                          ? block.remainingSecondsAt(_now).clamp(60, 86400)
                          : (block.durationMinutes * 60).clamp(60, 86400);
                      _startUltraFocusLock(
                        subject: block.subject,
                        title: block.title,
                        color: block.color,
                        durationSeconds: durSecs,
                        syncBothDevices: block.lockSyncBothDevices,
                      );
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFFEE2E2),
                      foregroundColor: const Color(0xFFB91C1C),
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                    ),
                    icon: const Icon(Icons.bolt_rounded, size: 15),
                    label: Text(
                      isActive ? '남은 시간 강제집중' : '지금 강제집중 시작',
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                if (block.specificDate != null)
                  _miniInfoBadge(
                    Icons.today,
                    '${block.specificDate!.substring(5)} 일일 전용',
                  )
                else
                  _miniInfoBadge(
                    Icons.repeat,
                    '매주 ${block.weekdays.map((d) => _weekdayNames[d - 1]).join("·")}',
                  ),
                if (block.notifyOnStart)
                  _miniInfoBadge(
                      Icons.notifications_active_outlined, '시작 정각 알림'),
                if (block.notifyBeforeEndMinutes > 0)
                  _miniInfoBadge(
                    Icons.timer_outlined,
                    '종료 ${block.notifyBeforeEndMinutes}분 전 알림',
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniInfoBadge(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: Colors.grey.shade600),
        const SizedBox(width: 3),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
      ],
    );
  }

  Future<void> _openAppUpdateDialog() async {
    bool isChecking = true;
    bool isDownloading = false;
    double downloadProgress = 0.0;
    int receivedBytes = 0;
    int totalBytes = 0;
    String? errorMsg;
    ReleaseInfo? releaseInfo = _latestRelease;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            if (isChecking) {
              isChecking = false;
              AppUpdateService.instance.checkLatestRelease().then((info) {
                if (!ctx.mounted) return;
                setModalState(() {
                  releaseInfo = info;
                });
                if (mounted && info != null) {
                  setState(() {
                    _latestRelease = info;
                  });
                }
              });
            }

            final currentBuild = AppUpdateService.currentBuildNumber;
            final remoteBuild = releaseInfo?.remoteBuildNumber ?? currentBuild;
            final hasNewUpdate = remoteBuild > currentBuild;

            return AlertDialog(
              title: Row(
                children: [
                  Icon(Icons.system_update_alt_rounded,
                      color: Colors.indigo.shade700),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      '앱 자체 원클릭 덮어쓰기 업데이트',
                      style:
                          TextStyle(fontWeight: FontWeight.w900, fontSize: 16.5),
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: hasNewUpdate
                            ? const Color(0xFFEEF2FF)
                            : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: hasNewUpdate
                              ? const Color(0xFF6366F1)
                              : const Color(0xFFCBD5E1),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            hasNewUpdate
                                ? '🎉 새로운 업데이트가 준비되어 있습니다!'
                                : '✅ 현재 설치 버전: 빌드 #$currentBuild',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 13.5,
                              color: hasNewUpdate
                                  ? Colors.indigo.shade900
                                  : Colors.blueGrey.shade800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            releaseInfo != null
                                ? '서버 최신 패키지: ${releaseInfo!.title} (${releaseInfo!.sizeMbText})'
                                : 'GitHub 최신 릴리스 정보를 확인하고 있습니다...',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF334155),
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            '• 이제 PC에서 파일을 옮기거나 기존 앱을 지울 필요가 없습니다.\n'
                            '• 아래 버튼을 누르면 앱 안에서 바로 다운로드 후 시간표·목표·통계 데이터를 100% 유지한 채 덮어쓰기 업데이트됩니다!',
                            style: TextStyle(
                              fontSize: 11.5,
                              height: 1.45,
                              color: Color(0xFF475569),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isDownloading) ...[
                      const SizedBox(height: 16),
                      Text(
                        downloadProgress >= 0
                            ? '최신 APK 다운로드 중... ${(downloadProgress * 100).toStringAsFixed(0)}% (${(receivedBytes / (1024 * 1024)).toStringAsFixed(1)} / ${(totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB)'
                            : '최신 APK 다운로드 중... (${(receivedBytes / (1024 * 1024)).toStringAsFixed(1)} MB)',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 12.5,
                          color: Colors.indigo.shade700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: downloadProgress >= 0 ? downloadProgress : null,
                          minHeight: 10,
                          backgroundColor: Colors.indigo.shade50,
                          color: Colors.indigo.shade600,
                        ),
                      ),
                    ],
                    if (errorMsg != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        '⚠️ $errorMsg',
                        style: const TextStyle(
                          color: Color(0xFFDC2626),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isDownloading ? null : () => Navigator.pop(ctx),
                  child: const Text('닫기'),
                ),
                OutlinedButton.icon(
                  onPressed: isDownloading
                      ? null
                      : () {
                          AppUpdateService.instance.openDirectDownloadInBrowser(
                            releaseInfo?.downloadUrl,
                          );
                        },
                  icon: const Icon(Icons.open_in_browser, size: 16),
                  label: const Text(
                    '브라우저로 직접 받기',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
                FilledButton.icon(
                  onPressed: isDownloading
                      ? null
                      : () async {
                          setModalState(() {
                            isDownloading = true;
                            errorMsg = null;
                            downloadProgress = 0.0;
                          });
                          try {
                            final url = releaseInfo?.downloadUrl ??
                                AppUpdateService.fallbackDirectDownloadUrl;
                            await AppUpdateService.instance
                                .downloadAndInstallUpdate(
                              downloadUrl: url,
                              onProgress: (prog, recv, total) {
                                if (!ctx.mounted) return;
                                setModalState(() {
                                  downloadProgress = prog;
                                  receivedBytes = recv;
                                  totalBytes = total;
                                });
                              },
                            );
                            if (ctx.mounted) {
                              Navigator.pop(ctx);
                            }
                          } catch (e) {
                            if (!ctx.mounted) return;
                            setModalState(() {
                              isDownloading = false;
                              errorMsg =
                                  '다운로드 실패: $e\n우측 하단 [브라우저로 직접 받기]를 눌러 설치해 주세요.';
                            });
                          }
                        },
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF4F46E5),
                  ),
                  icon: const Icon(Icons.bolt_rounded, size: 18),
                  label: const Text(
                    '지금 바로 덮어쓰기 업데이트',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildEmptySchedulePlaceholder() {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Icon(Icons.more_time, size: 46, color: Colors.indigo.shade300),
          const SizedBox(height: 12),
          const Text(
            '아직 등록된 공부 시간 블록이 없습니다',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          const SizedBox(height: 6),
          Text(
            '정해진 1시간 단위가 아니라 09:15 ~ 10:40처럼 원하는 분 단위 시간대와 과목, 세부 할 일을 자유롭게 추가해보세요!',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}

class _SliverTabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  _SliverTabBarDelegate(this.tabBar);

  @override
  double get minExtent => tabBar.preferredSize.height;

  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: Colors.white,
      child: tabBar,
    );
  }

  @override
  bool shouldRebuild(_SliverTabBarDelegate oldDelegate) => false;
}
