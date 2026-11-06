import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class FocusLockPayload {
  final String
      type; // 'LOCK_START', 'EMERGENCY_UNLOCK', 'LOCK_COMPLETE', 'FULL_DATA_SYNC', 'SYNC_REQUEST'
  final String pairingCode;
  final String subject;
  final String title;
  final int remainingSeconds;
  final int totalSeconds;
  final String sourceDevice;
  final Map<String, dynamic>? syncData;

  const FocusLockPayload({
    required this.type,
    required this.pairingCode,
    this.subject = '',
    this.title = '',
    this.remainingSeconds = 0,
    this.totalSeconds = 0,
    this.sourceDevice = 'Galaxy',
    this.syncData,
  });

  Map<String, dynamic> toJson() => {
        'type': type,
        'pairingCode': pairingCode,
        'subject': subject,
        'title': title,
        'remainingSeconds': remainingSeconds,
        'totalSeconds': totalSeconds,
        'sourceDevice': sourceDevice,
        if (syncData != null) 'syncData': syncData,
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
      syncData: json['syncData'] as Map<String, dynamic>?,
    );
  }
}

/// 갤럭시 S25 <-> 갤럭시 탭 S10 Ultra 양방향 전체 데이터(시간표/오늘계획/주간목표/통계) 동기화 및 동시 앱 차단 서비스
class FocusLockService {
  FocusLockService._();
  static final FocusLockService instance = FocusLockService._();

  static const MethodChannel _channel =
      MethodChannel('com.example.study_planner_app/focus_lock');
  static const int _udpPort = 45454;
  static const int _httpPort = 45455;

  RawDatagramSocket? _udpSocket;
  HttpServer? _httpServer;
  String _pairingCode = 'S25-TAB10';
  final String _deviceId =
      'dev_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';

  void Function(FocusLockPayload payload)? _onRemoteEvent;
  Map<String, dynamic> Function()? _getLocalSnapshotCallback;

  Future<void> initialize({
    required String pairingCode,
    required void Function(FocusLockPayload payload) onRemoteEvent,
    required Map<String, dynamic> Function() getLocalSnapshotCallback,
  }) async {
    _pairingCode = pairingCode.trim().toUpperCase();
    _onRemoteEvent = onRemoteEvent;
    _getLocalSnapshotCallback = getLocalSnapshotCallback;

    if (kIsWeb) return;

    // 1) 로컬 HTTP 동기화 서버 기동 (대용량 시간표/통계 JSON 무손실 전송용)
    try {
      await _httpServer?.close(force: true);
      _httpServer = await HttpServer.bind(
        InternetAddress.anyIPv4,
        _httpPort,
        shared: true,
      );
      _httpServer!.listen((HttpRequest req) async {
        try {
          if (req.method == 'GET' && req.uri.path == '/sync') {
            final snap = _getLocalSnapshotCallback?.call() ?? {};
            final body = jsonEncode({
              'pairingCode': _pairingCode,
              'sourceDevice': _deviceId,
              'syncData': snap,
            });
            req.response
              ..statusCode = HttpStatus.ok
              ..headers.contentType = ContentType.json
              ..write(body);
            await req.response.close();
          } else if (req.method == 'POST' && req.uri.path == '/sync') {
            final content = await utf8.decoder.bind(req).join();
            final json = jsonDecode(content) as Map<String, dynamic>;
            final payload = FocusLockPayload.fromJson(json);
            if (payload.pairingCode.toUpperCase() == _pairingCode &&
                payload.sourceDevice != _deviceId) {
              _onRemoteEvent?.call(payload);
            }
            req.response
              ..statusCode = HttpStatus.ok
              ..write('OK');
            await req.response.close();
          } else {
            req.response.statusCode = HttpStatus.notFound;
            await req.response.close();
          }
        } catch (_) {
          try {
            await req.response.close();
          } catch (_) {}
        }
      });
    } catch (e) {
      debugPrint('HTTP 동기화 서버 시작 생략: $e');
    }

    // 2) UDP 브로드캐스트 소켓 기동 (즉시 발견 + 잠금 신호 + 실시간 동기화 트리거)
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

            if (payload.pairingCode.toUpperCase() != _pairingCode ||
                payload.sourceDevice == _deviceId) {
              return;
            }

            if (payload.type == 'SYNC_PING') {
              // 상대 기기(S25 또는 탭S10)가 발견되면 HTTP로 전체 데이터 스냅샷 가져오기
              _pullSnapshotFromPeer(dg.address.address);
            } else if (payload.type == 'SYNC_REQUEST') {
              // 내 최신 데이터를 브로드캐스트 및 상대방에게 전송
              final snap = _getLocalSnapshotCallback?.call();
              if (snap != null) {
                _pushSnapshotToPeer(dg.address.address, snap);
              }
            } else {
              _onRemoteEvent?.call(payload);
            }
          } catch (_) {}
        }
      });

      // 앱 시작 시 같은 네트워크의 S25 / 탭 S10 Ultra에 동기화 요청 전송
      requestFullSyncFromPeer();
    } catch (e) {
      debugPrint('기기간 동기화 소켓 초기화 생략/오류: $e');
    }
  }

  String get deviceId => _deviceId;

  void updatePairingCode(String newCode) {
    _pairingCode = newCode.trim().toUpperCase();
    requestFullSyncFromPeer();
  }

  Future<void> _pullSnapshotFromPeer(String peerIp) async {
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 3);
      final req =
          await client.getUrl(Uri.parse('http://$peerIp:$_httpPort/sync'));
      final resp = await req.close();
      if (resp.statusCode == HttpStatus.ok) {
        final body = await utf8.decoder.bind(resp).join();
        final json = jsonDecode(body) as Map<String, dynamic>;
        if ((json['pairingCode'] as String?)?.toUpperCase() == _pairingCode &&
            json['sourceDevice'] != _deviceId &&
            json['syncData'] != null) {
          _onRemoteEvent?.call(
            FocusLockPayload(
              type: 'FULL_DATA_SYNC',
              pairingCode: _pairingCode,
              sourceDevice: json['sourceDevice'] as String? ?? 'Peer',
              syncData: json['syncData'] as Map<String, dynamic>,
            ),
          );
        }
      }
      client.close();
    } catch (_) {}
  }

  Future<void> _pushSnapshotToPeer(
      String peerIp, Map<String, dynamic> snap) async {
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 3);
      final req =
          await client.postUrl(Uri.parse('http://$peerIp:$_httpPort/sync'));
      req.headers.contentType = ContentType.json;
      final payload = FocusLockPayload(
        type: 'FULL_DATA_SYNC',
        pairingCode: _pairingCode,
        sourceDevice: _deviceId,
        syncData: snap,
      );
      req.write(jsonEncode(payload.toJson()));
      final resp = await req.close();
      await resp.drain();
      client.close();
    } catch (_) {}
  }

  /// 시간표, 오늘의 계획, 주간 목표, 통계가 변경될 때마다 S25 <-> 탭 S10 Ultra 즉시 동기화
  void broadcastFullDataSync(Map<String, dynamic> snapshot) {
    if (kIsWeb || _udpSocket == null) return;
    try {
      // 1) UDP로 즉시 전송 (데이터 크기가 60KB 이하인 경우 한 번에 도달)
      final payload = FocusLockPayload(
        type: 'FULL_DATA_SYNC',
        pairingCode: _pairingCode,
        sourceDevice: _deviceId,
        syncData: snapshot,
      );
      final bytes = utf8.encode(jsonEncode(payload.toJson()));
      if (bytes.length < 60000) {
        _udpSocket!.send(
          bytes,
          InternetAddress('255.255.255.255'),
          _udpPort,
        );
      }
      // 2) 대용량일 경우를 대비해 SYNC_PING도 함께 보내 상대 기기가 HTTP로 풀어가도록 유도
      final ping = FocusLockPayload(
        type: 'SYNC_PING',
        pairingCode: _pairingCode,
        sourceDevice: _deviceId,
      );
      _udpSocket!.send(
        utf8.encode(jsonEncode(ping.toJson())),
        InternetAddress('255.255.255.255'),
        _udpPort,
      );
    } catch (e) {
      debugPrint('전체 데이터 동기화 브로드캐스트 생략: $e');
    }
  }

  /// 상대 기기(S25 또는 탭 S10 Ultra)에 최신 시간표/목표/통계 요청
  void requestFullSyncFromPeer() {
    if (kIsWeb || _udpSocket == null) return;
    try {
      final req = FocusLockPayload(
        type: 'SYNC_REQUEST',
        pairingCode: _pairingCode,
        sourceDevice: _deviceId,
      );
      _udpSocket!.send(
        utf8.encode(jsonEncode(req.toJson())),
        InternetAddress('255.255.255.255'),
        _udpPort,
      );
    } catch (_) {}
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

  /// 동일 네트워크에 있는 갤럭시 S25 & 갤럭시 탭 S10 Ultra로 잠금/해제 신호 브로드캐스트
  void broadcastLockSignal(FocusLockPayload payload) {
    if (kIsWeb || _udpSocket == null) return;
    try {
      final map = payload.toJson();
      map['sourceDevice'] = _deviceId;
      final bytes = utf8.encode(jsonEncode(map));
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
