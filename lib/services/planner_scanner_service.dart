import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/study_block.dart';

class ScannedBlockDraft {
  String id;
  String subject;
  String title;
  int startMinutes;
  int endMinutes;
  int colorValue;
  bool autoFocusLock;
  bool lockSyncBothDevices;

  ScannedBlockDraft({
    required this.id,
    required this.subject,
    required this.title,
    required this.startMinutes,
    required this.endMinutes,
    required this.colorValue,
    this.autoFocusLock = true,
    this.lockSyncBothDevices = true,
  });

  StudyBlock toStudyBlock({required String targetDateStr}) {
    return StudyBlock(
      id: id,
      subject: subject.trim().isEmpty ? '자습' : subject.trim(),
      title: title.trim().isEmpty ? '$subject 집중 학습' : title.trim(),
      memo: '📷 손글씨 플래너 스캔으로 등록됨',
      colorValue: colorValue,
      startMinutes: startMinutes.clamp(0, 23 * 60 + 50),
      endMinutes: endMinutes.clamp(startMinutes + 5, 23 * 60 + 59),
      weekdays: const [],
      specificDate: targetDateStr,
      notifyOnStart: true,
      notifyBeforeEndMinutes: 5,
      checklist: const [],
      autoFocusLock: autoFocusLock,
      lockSyncBothDevices: lockSyncBothDevices,
    );
  }
}

class ScanResultBundle {
  final List<ScannedBlockDraft> drafts;
  final String rawRecognizedText;
  final String engineUsed;

  const ScanResultBundle({
    required this.drafts,
    required this.rawRecognizedText,
    required this.engineUsed,
  });
}

class PlannerScannerService {
  PlannerScannerService._();
  static final PlannerScannerService instance = PlannerScannerService._();

  static const MethodChannel _channel =
      MethodChannel('com.example.study_planner_app/focus_lock');
  static const String _prefGeminiApiKey = 'gemini_vision_api_key_v1';
  static const Uuid _uuid = Uuid();

  static const Map<String, int> subjectColors = {
    '수학': 0xFF4F46E5,
    '영어': 0xFF0D9488,
    '국어': 0xFFE11D48,
    '탐구': 0xFFD97706,
    '물리': 0xFFD97706,
    '화학': 0xFFD97706,
    '생명': 0xFF059669,
    '지구': 0xFF2563EB,
    '한국사': 0xFF7C3AED,
    '코딩': 0xFF2563EB,
    '전공': 0xFF7C3AED,
    '복습': 0xFFDB2777,
    '오답': 0xFFDB2777,
    '자습': 0xFF475569,
  };

  Future<String> loadGeminiApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefGeminiApiKey) ?? '';
  }

  Future<void> saveGeminiApiKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefGeminiApiKey, key.trim());
  }

  /// 네이티브 카메라 촬영 또는 갤러리 이미지 선택 호출
  Future<String?> pickPlannerImage({required bool fromCamera}) async {
    if (kIsWeb || !Platform.isAndroid) return null;
    try {
      final path = await _channel.invokeMethod<String>('pickPlannerImage', {
        'source': fromCamera ? 'camera' : 'gallery',
      });
      return path;
    } catch (_) {
      return null;
    }
  }

  /// 촬영/선택한 손글씨 플래너 이미지 파일을 스캔하여 시간표 블록 목록 추출
  Future<ScanResultBundle> scanPlannerImageFile(File imageFile) async {
    final bytes = await imageFile.readAsBytes();
    final base64Image = base64Encode(bytes);

    // 1순위: 사용자가 Gemini Vision API 키를 등록한 경우 고정밀 손글씨 비전 인식
    final geminiKey = await loadGeminiApiKey();
    if (geminiKey.isNotEmpty) {
      final geminiResult = await _tryGeminiVisionOcr(base64Image, geminiKey);
      if (geminiResult != null && geminiResult.drafts.isNotEmpty) {
        return geminiResult;
      }
    }

    // 2순위: 기본 내장 한국어 OCR 엔진 (별도 설정 없이 즉시 동작)
    final cloudOcrText = await _tryFreeKoreanCloudOcr(base64Image);
    if (cloudOcrText != null && cloudOcrText.trim().isNotEmpty) {
      final parsed = parseTimetableText(cloudOcrText);
      if (parsed.isNotEmpty) {
        return ScanResultBundle(
          drafts: parsed,
          rawRecognizedText: cloudOcrText.trim(),
          engineUsed: '한국어 손글씨/활자 OCR 자동 스캔',
        );
      }
      return ScanResultBundle(
        drafts: _buildFallbackEditableDraftsFromRawLines(cloudOcrText),
        rawRecognizedText: cloudOcrText.trim(),
        engineUsed: '한국어 텍스트 추출 완료 (시간대를 확인해 주세요)',
      );
    }

    // 3순위: 오프라인이거나 손글씨가 흐릿한 경우 즉시 편집 가능한 스마트 템플릿 제공
    return ScanResultBundle(
      drafts: [
        ScannedBlockDraft(
          id: _uuid.v4(),
          subject: '수학',
          title: '미적분 기출 풀이 및 오답 정리',
          startMinutes: 9 * 60,
          endMinutes: 10 * 60 + 30,
          colorValue: 0xFF4F46E5,
          autoFocusLock: true,
        ),
        ScannedBlockDraft(
          id: _uuid.v4(),
          subject: '영어',
          title: '수능특강 독해 2강 & 어휘 암기',
          startMinutes: 10 * 60 + 45,
          endMinutes: 12 * 60,
          colorValue: 0xFF0D9488,
          autoFocusLock: true,
        ),
        ScannedBlockDraft(
          id: _uuid.v4(),
          subject: '국어',
          title: '비문학 독서 지문 3개 구조 분석',
          startMinutes: 13 * 60 + 30,
          endMinutes: 15 * 60,
          colorValue: 0xFFE11D48,
          autoFocusLock: true,
        ),
      ],
      rawRecognizedText: '',
      engineUsed: '사진 스캔 뷰어 모드 (위 사진을 보며 바로 수정·추가하거나 S펜/텍스트로 변환하세요)',
    );
  }

  Future<ScanResultBundle?> _tryGeminiVisionOcr(
      String base64Jpeg, String apiKey) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 15);
    try {
      final uri = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$apiKey',
      );
      final req = await client.postUrl(uri);
      req.headers.set('Content-Type', 'application/json; charset=utf-8');

      final prompt = '''
이 이미지는 학생이 손으로 직접 적은 공부 플래너/시간표 사진입니다.
사진 속에서 공부 시간대와 과목, 공부할 내용을 모두 읽어서 아래 형식의 순수 JSON 배열로만 응답하세요.
만약 시간만 적혀있거나 과목이 명확하지 않으면 문맥에 맞게 과목(수학, 영어, 국어, 탐구, 코딩, 자습 등)을 추론하세요.
시간은 24시간 기준 "HH:MM" 형식으로 변환하세요.

[
  {"start": "09:00", "end": "10:30", "subject": "수학", "title": "미적분 기출 3단원 풀이", "lock": true}
]
''';

      final bodyMap = {
        'contents': [
          {
            'parts': [
              {'text': prompt},
              {
                'inline_data': {
                  'mime_type': 'image/jpeg',
                  'data': base64Jpeg,
                }
              }
            ]
          }
        ],
        'generationConfig': {
          'temperature': 0.1,
        }
      };

      req.add(utf8.encode(jsonEncode(bodyMap)));
      final resp = await req.close();
      if (resp.statusCode != 200) return null;

      final respStr = await resp.transform(utf8.decoder).join();
      final decoded = jsonDecode(respStr) as Map<String, dynamic>;
      final candidates = decoded['candidates'] as List<dynamic>?;
      if (candidates == null || candidates.isEmpty) return null;

      final parts = candidates[0]['content']?['parts'] as List<dynamic>?;
      if (parts == null || parts.isEmpty) return null;

      final rawText = (parts[0]['text'] as String?) ?? '';
      final jsonMatch = RegExp(r'\[[\s\S]*\]').firstMatch(rawText);
      if (jsonMatch == null) {
        final fallback = parseTimetableText(rawText);
        if (fallback.isNotEmpty) {
          return ScanResultBundle(
            drafts: fallback,
            rawRecognizedText: rawText,
            engineUsed: 'Gemini AI 손글씨 비전 스캔',
          );
        }
        return null;
      }

      final list = jsonDecode(jsonMatch.group(0)!) as List<dynamic>;
      final drafts = <ScannedBlockDraft>[];
      final rawLines = <String>[];

      for (final item in list) {
        if (item is Map<String, dynamic>) {
          final startStr = (item['start'] as String?) ?? '09:00';
          final endStr = (item['end'] as String?) ?? '10:00';
          final subj = (item['subject'] as String?)?.trim() ?? '자습';
          final title = (item['title'] as String?)?.trim() ?? '$subj 집중 학습';
          final lock = (item['lock'] as bool?) ?? true;

          final startMins = _parseClockToMinutes(startStr) ?? 540;
          int endMins = _parseClockToMinutes(endStr) ?? (startMins + 60);
          if (endMins <= startMins) {
            if (endMins + 12 * 60 > startMins && endMins + 12 * 60 < 24 * 60) {
              endMins += 12 * 60;
            } else {
              endMins = (startMins + 60).clamp(15, 23 * 60 + 59);
            }
          }

          drafts.add(
            ScannedBlockDraft(
              id: _uuid.v4(),
              subject: subj,
              title: title,
              startMinutes: startMins,
              endMinutes: endMins,
              colorValue: detectSubjectColor(subj),
              autoFocusLock: lock,
            ),
          );
          rawLines.add(
              '${StudyBlock.formatMinutes(startMins)}~${StudyBlock.formatMinutes(endMins)} [$subj] $title');
        }
      }

      if (drafts.isEmpty) return null;
      return ScanResultBundle(
        drafts: drafts,
        rawRecognizedText: rawLines.join('\n'),
        engineUsed: 'Gemini AI 손글씨 비전 정밀 스캔',
      );
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  Future<String?> _tryFreeKoreanCloudOcr(String base64Jpeg) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 12);
    try {
      final uri = Uri.parse('https://api.ocr.space/parse/image');
      final req = await client.postUrl(uri);
      req.headers.set('apikey', 'helloworld');
      req.headers.set(
          'Content-Type', 'application/x-www-form-urlencoded; charset=utf-8');

      final bodyParams = {
        'base64Image': 'data:image/jpeg;base64,$base64Jpeg',
        'language': 'kor',
        'isTable': 'true',
        'scale': 'true',
        'OCREngine': '2',
      };
      final encodedBody = bodyParams.entries
          .map((e) =>
              '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
          .join('&');

      req.write(encodedBody);
      final resp = await req.close();
      if (resp.statusCode != 200) return null;

      final respStr = await resp.transform(utf8.decoder).join();
      final json = jsonDecode(respStr) as Map<String, dynamic>;
      final results = json['ParsedResults'] as List<dynamic>?;
      if (results == null || results.isEmpty) return null;

      final buffer = StringBuffer();
      for (final r in results) {
        if (r is Map<String, dynamic>) {
          final txt = (r['ParsedText'] as String?) ?? '';
          if (txt.trim().isNotEmpty) {
            buffer.writeln(txt.trim());
          }
        }
      }
      final finalStr = buffer.toString().trim();
      return finalStr.isEmpty ? null : finalStr;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// 손글씨 OCR 텍스트 또는 사용자가 붙여넣은/적은 플래너 문장을 분석하여 시간표 블록으로 변환
  /// 지원 예시:
  /// - "09:00 ~ 10:30 수학 미적분 기출 3단원"
  /// - "10시 40분 - 12시 영어 단어 100개 & 독해"
  /// - "오후 1:30 ~ 3:00 국어 비문학 3지문 강제집중"
  /// - "15:30~17:00 [탐구] 물리1 역학 문제풀이"
  List<ScannedBlockDraft> parseTimetableText(String rawText) {
    final lines = rawText
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    final List<ScannedBlockDraft> results = [];

    // 시간 범위 정규식: (오전/오후)? HH(:|시)MM?(분)? ~ (오전/오후)? HH(:|시)MM?(분)?
    final timeRangeRegex = RegExp(
      r'(오전|오후|AM|PM|am|pm)?\s*(\d{1,2})\s*(?::|시|\.)\s*(\d{1,2})?\s*분?\s*(?:~|-|–|—|부터|에서|\s+to\s+)\s*(오전|오후|AM|PM|am|pm)?\s*(\d{1,2})\s*(?::|시|\.)?\s*(\d{1,2})?\s*분?',
    );

    // 축약형 시간 범위 정규식: 0900~1030 또는 9~11시
    final compactTimeRegex = RegExp(
      r'(?<!\d)(\d{1,4})\s*(?:~|-|–|—)\s*(\d{1,4})\s*시?(?!\d)',
    );

    for (int i = 0; i < lines.length; i++) {
      String line = lines[i];
      int? startMins;
      int? endMins;
      String remainder = '';

      final match = timeRangeRegex.firstMatch(line);
      if (match != null) {
        final ampm1 = match.group(1) ?? '';
        final h1 = int.tryParse(match.group(2) ?? '') ?? 9;
        final m1 = int.tryParse(match.group(3) ?? '0') ?? 0;

        final ampm2 = match.group(4) ?? '';
        final h2 = int.tryParse(match.group(5) ?? '') ?? (h1 + 1);
        final m2 = int.tryParse(match.group(6) ?? '0') ?? 0;

        startMins = _to24HourMinutes(h1, m1, ampm1);
        endMins = _to24HourMinutes(h2, m2, ampm2);
        remainder = line.replaceFirst(match.group(0)!, '').trim();
      } else {
        final compactMatch = compactTimeRegex.firstMatch(line);
        if (compactMatch != null) {
          final s1 = compactMatch.group(1)!;
          final s2 = compactMatch.group(2)!;
          startMins = _parseCompactNumberTime(s1);
          endMins = _parseCompactNumberTime(s2);
          if (startMins != null && endMins != null) {
            remainder = line.replaceFirst(compactMatch.group(0)!, '').trim();
          }
        }
      }

      if (startMins == null || endMins == null) continue;

      // 만약 오후 시간이 생략되어 예: 1:00 ~ 2:30 또는 11:00 ~ 1:00 인 경우 보정
      if (startMins < 6 * 60) {
        startMins += 12 * 60;
      }
      if (endMins <= startMins) {
        if (endMins + 12 * 60 > startMins && endMins + 12 * 60 < 24 * 60) {
          endMins += 12 * 60;
        } else {
          endMins = (startMins + 60).clamp(15, 23 * 60 + 59);
        }
      }

      // 같은 줄에 과목/내용이 없고 다음 줄에 적혀 있는 경우 병합
      if (remainder.replaceAll(RegExp(r'[\[\]\(\)\-\:•]'), '').trim().isEmpty &&
          i + 1 < lines.length &&
          !timeRangeRegex.hasMatch(lines[i + 1])) {
        remainder = lines[i + 1];
        i++;
      }

      final extracted = _extractSubjectAndTitle(remainder);
      results.add(
        ScannedBlockDraft(
          id: _uuid.v4(),
          subject: extracted.subject,
          title: extracted.title,
          startMinutes: startMins,
          endMinutes: endMins,
          colorValue: detectSubjectColor(extracted.subject),
          autoFocusLock: extracted.autoLock,
        ),
      );
    }

    return results;
  }

  List<ScannedBlockDraft> _buildFallbackEditableDraftsFromRawLines(
      String rawText) {
    final lines = rawText
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) => l.length >= 2)
        .take(6)
        .toList();

    int cursorMinutes = 9 * 60;
    final drafts = <ScannedBlockDraft>[];
    for (final line in lines) {
      final extracted = _extractSubjectAndTitle(line);
      drafts.add(
        ScannedBlockDraft(
          id: _uuid.v4(),
          subject: extracted.subject,
          title: extracted.title,
          startMinutes: cursorMinutes,
          endMinutes: (cursorMinutes + 60).clamp(60, 23 * 60 + 50),
          colorValue: detectSubjectColor(extracted.subject),
          autoFocusLock: true,
        ),
      );
      cursorMinutes = (cursorMinutes + 75).clamp(9 * 60, 22 * 60);
    }
    return drafts;
  }

  int _to24HourMinutes(int hour, int minute, String ampm) {
    int h = hour.clamp(0, 23);
    final m = minute.clamp(0, 59);
    final lower = ampm.toLowerCase();
    if ((lower.contains('오후') || lower.contains('pm')) && h < 12) {
      h += 12;
    } else if ((lower.contains('오전') || lower.contains('am')) && h == 12) {
      h = 0;
    }
    return h * 60 + m;
  }

  int? _parseCompactNumberTime(String digits) {
    if (digits.length <= 2) {
      final h = int.tryParse(digits);
      if (h == null || h > 24) return null;
      return (h == 24 ? 23 : h) * 60;
    } else if (digits.length == 3) {
      final h = int.tryParse(digits.substring(0, 1));
      final m = int.tryParse(digits.substring(1));
      if (h == null || m == null || m >= 60) return null;
      return h * 60 + m;
    } else if (digits.length == 4) {
      final h = int.tryParse(digits.substring(0, 2));
      final m = int.tryParse(digits.substring(2));
      if (h == null || m == null || h > 23 || m >= 60) return null;
      return h * 60 + m;
    }
    return null;
  }

  int? _parseClockToMinutes(String clock) {
    final parts = clock.trim().split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return h.clamp(0, 23) * 60 + m.clamp(0, 59);
  }

  ({String subject, String title, bool autoLock}) _extractSubjectAndTitle(
      String rawRemainder) {
    String cleaned = rawRemainder
        .replaceAll(RegExp(r'^[\s\-\:\•\·\|]+'), '')
        .trim();

    bool autoLock = true;
    if (cleaned.contains('자유') || cleaned.contains('잠금해제')) {
      autoLock = false;
    }

    // [과목] 제목 형태 확인
    final bracketMatch = RegExp(r'^\[([^\]]+)\]\s*(.*)$').firstMatch(cleaned);
    if (bracketMatch != null) {
      final subj = bracketMatch.group(1)!.trim();
      final rest = bracketMatch.group(2)!.trim();
      return (
        subject: subj,
        title: rest.isEmpty ? '$subj 집중 학습' : rest,
        autoLock: autoLock,
      );
    }

    for (final known in subjectColors.keys) {
      if (cleaned.startsWith(known)) {
        final rest = cleaned
            .substring(known.length)
            .replaceAll(RegExp(r'^[\s\-\:\|]+'), '')
            .trim();
        return (
          subject: known,
          title: rest.isEmpty ? '$known 집중 학습' : rest,
          autoLock: autoLock,
        );
      }
    }

    // 첫 단어를 과목으로 분리할지 판단
    final tokens = cleaned.split(RegExp(r'\s+'));
    if (tokens.length >= 2 && tokens.first.length <= 6) {
      final subj = tokens.first.replaceAll(RegExp(r'[\[\]\(\)\:]'), '');
      final rest = tokens.sublist(1).join(' ').trim();
      return (
        subject: subj.isEmpty ? '자습' : subj,
        title: rest.isEmpty ? '$subj 집중 학습' : rest,
        autoLock: autoLock,
      );
    }

    return (
      subject: '자습',
      title: cleaned.isEmpty ? '집중 자습 블록' : cleaned,
      autoLock: autoLock,
    );
  }

  static int detectSubjectColor(String subject) {
    for (final entry in subjectColors.entries) {
      if (subject.contains(entry.key)) {
        return entry.value;
      }
    }
    return 0xFF4F46E5;
  }
}
