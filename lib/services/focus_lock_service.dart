import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class FocusLockPayload {
  final String type; // 'LOCK_START', 'LOCK_TICK', 'EMERGENCY_UNLOCK', 'LOCK_COMPLETE'
  final String pairingCode;
  final String subject;
  final String title;
  final int remainingSeconds;
  final int totalSeconds;
  final String sourceDevice;

  const FocusLockPayload({
    required this.type,
    required this.pairingCode,
    required this.subject,
    required this.title,
    required this.remainingSeconds,
    required this.totalSeconds,
    required this.sourceDevice,
  });

  Map<String, dynamic> toJson() => {
        'type': type,
        'pairingCode': pairingCode,
        'subject': subject,
        'title': title,
        'remainingSeconds': remainingSeconds,
        'totalSeconds': totalSeconds,
        'sourceDevice': sourceDevice,
      };

  factory FocusLockPayload.fromJson(Map<String, dynamic> json) {
    return FocusLockPayload(
      type: json['type'] as String? ?? 'LOCK_START',
      pairingCode: json['pairingCode'] as String? ?? 'S25-TAB10',
      subject: json['subject'] as String? ?? '집중 학습',
      title: json['title'] as String? ?? '최대 집중 모드 진행 중',
      remainingSeconds: json['remainingSeconds'] as int? ?? 1500,
      totalSeconds: json['totalSeconds'] as int? ?? 1500,
      sourceDevice: json['sourceDevice'] as String? ?? 'Galaxy Device',
    );
  }
}

/// 갤럭시 S25 <-> 갤럭시 탭 S10 Ultra 양방향 동시 앱 차단 및 네이티브 화면 고정(LockTask) 서비스
class FocusLockService {
  FocusLockService._();
  static final FocusLockService instance = FocusLockService._();

  static const MethodChannel _channel =
      MethodChannel('com.example.study_planner_app/focus_lock');
  static const int _udpPort = 45454;

  RawDatagramSocket? _udpSocket;
  String _pairingCode = 'S25-TAB10';
  void Function(FocusLockPayload payload)? _onRemoteLockEvent;

  Future<void> initialize({
    required String pairingCode,
    required void Function(FocusLockPayload payload) onRemoteLockEvent,
  }) async {
    _pairingCode = pairingCode.trim().toUpperCase();
    _onRemoteLockEvent = onRemoteLockEvent;

    if (kIsWeb) return;

    try {
      _udpSocket?.close();
      _udpSocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        _udpPort,
        reuseAddress: true,
        reusePort: false,
      );
      _udpSocket!.broadcastEnabled = true;
      _udpSocket!.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          final dg = _udpSocket?.receive();
          if (dg == null) return;
          try {
            final msg = utf8.decode(dg.data);
            final json = jsonDecode(msg) as Map<String, dynamic>;
            final payload = FocusLockPayload.fromJson(json);
            if (payload.pairingCode.toUpperCase() == _pairingCode) {
              _onRemoteLockEvent?.call(payload);
            }
          } catch (_) {}
        }
      });
    } catch (e) {
      debugPrint('기기간 동기화 소켓 초기화 생략/오류: $e');
    }
  }

  void updatePairingCode(String newCode) {
    _pairingCode = newCode.trim().toUpperCase();
  }

  /// Android 네이티브 LockTask(화면 고정 / 다른 앱 실행 차단) 활성화
  Future<void> enableNativeAppLock() async {
    if (kIsWeb) return;
    try {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      await _channel.invokeMethod('enableLockTask');
    } catch (e) {
      debugPrint('LockTask 활성화 안내: $e');
    }
  }

  /// Android 네이티브 LockTask(화면 고정 / 다른 앱 실행 차단) 해제
  Future<void> disableNativeAppLock() async {
    if (kIsWeb) return;
    try {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      await _channel.invokeMethod('disableLockTask');
    } catch (e) {
      debugPrint('LockTask 해제 안내: $e');
    }
  }

  /// 동일 네트워크(Wi-Fi / 핫스팟)에 있는 갤럭시 S25 & 갤럭시 탭 S10 Ultra로 잠금/해제 신호 브로드캐스트
  void broadcastLockSignal(FocusLockPayload payload) {
    if (kIsWeb || _udpSocket == null) return;
    try {
      final bytes = utf8.encode(jsonEncode(payload.toJson()));
      _udpSocket!.send(
        bytes,
        InternetAddress('255.255.255.255'),
        _udpPort,
      );
    } catch (e) {
      debugPrint('기기간 브로드캐스트 생략: $e');
    }
  }
}
