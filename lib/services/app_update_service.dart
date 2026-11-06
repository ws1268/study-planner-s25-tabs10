import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class ReleaseInfo {
  final int remoteBuildNumber;
  final String title;
  final String notes;
  final String downloadUrl;
  final int sizeBytes;
  final String publishedAt;

  const ReleaseInfo({
    required this.remoteBuildNumber,
    required this.title,
    required this.notes,
    required this.downloadUrl,
    required this.sizeBytes,
    required this.publishedAt,
  });

  bool isNewerThan(int currentBuild) => remoteBuildNumber > currentBuild;

  String get sizeMbText =>
      sizeBytes > 0 ? '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB' : '약 56.9 MB';
}

/// 앱을 삭제하거나 PC에서 파일을 옮길 필요 없이,
/// S25 / 탭 S10 Ultra 앱 내부에서 바로 최신 APK를 받아 덮어쓰기 업데이트하는 서비스
class AppUpdateService {
  AppUpdateService._();
  static final AppUpdateService instance = AppUpdateService._();

  static const int currentBuildNumber =
      int.fromEnvironment('APP_BUILD_NUMBER', defaultValue: 5);

  static const String repoOwner = 'ws1268';
  static const String repoName = 'study-planner-s25-tabs10';
  static const String fallbackDirectDownloadUrl =
      'https://github.com/$repoOwner/$repoName/releases/latest/download/study-planner-s25-tabs10.apk';

  static const MethodChannel _channel =
      MethodChannel('com.example.study_planner_app/focus_lock');

  /// GitHub Releases에서 최신 빌드 정보 조회
  Future<ReleaseInfo?> checkLatestRelease() async {
    if (kIsWeb) return null;
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 8);
    try {
      final uri = Uri.parse(
        'https://api.github.com/repos/$repoOwner/$repoName/releases/latest',
      );
      final req = await client.getUrl(uri);
      req.headers.set('Accept', 'application/vnd.github+json');
      req.headers.set('User-Agent', 'StudyPlannerApp-Updater');
      final resp = await req.close();
      if (resp.statusCode != 200) {
        return null;
      }
      final body = await resp.transform(utf8.decoder).join();
      final data = jsonDecode(body) as Map<String, dynamic>;

      final title = (data['name'] as String?) ?? '최신 버전';
      final notes = (data['body'] as String?) ?? '';
      final publishedAt = (data['published_at'] as String?) ?? '';

      // 제목 또는 본문에서 Run #숫자 추출
      int remoteBuild = currentBuildNumber;
      final match = RegExp(r'Run #(\d+)').firstMatch('$title $notes');
      if (match != null) {
        remoteBuild = int.tryParse(match.group(1) ?? '') ?? currentBuildNumber;
      }

      String downloadUrl = fallbackDirectDownloadUrl;
      int sizeBytes = 0;
      final assets = data['assets'];
      if (assets is List && assets.isNotEmpty) {
        for (final asset in assets) {
          if (asset is Map<String, dynamic>) {
            final name = (asset['name'] as String?) ?? '';
            if (name.endsWith('.apk')) {
              downloadUrl =
                  (asset['browser_download_url'] as String?) ?? fallbackDirectDownloadUrl;
              sizeBytes = (asset['size'] as int?) ?? 0;
              break;
            }
          }
        }
      }

      return ReleaseInfo(
        remoteBuildNumber: remoteBuild,
        title: title,
        notes: notes,
        downloadUrl: downloadUrl,
        sizeBytes: sizeBytes,
        publishedAt: publishedAt,
      );
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// 앱 내부 캐시 폴더로 최신 APK를 다운로드한 뒤 안드로이드 패키지 인스톨러(덮어쓰기 업데이트) 실행
  Future<bool> downloadAndInstallUpdate({
    required String downloadUrl,
    required void Function(double progress, int receivedBytes, int totalBytes)
        onProgress,
  }) async {
    if (kIsWeb || !Platform.isAndroid) return false;

    final String? targetPath =
        await _channel.invokeMethod<String>('getCacheApkPath');
    if (targetPath == null || targetPath.isEmpty) {
      throw Exception('업데이트 저장 경로를 가져올 수 없습니다.');
    }

    final apkFile = File(targetPath);
    if (await apkFile.exists()) {
      await apkFile.delete();
    }

    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.getUrl(Uri.parse(downloadUrl));
      req.followRedirects = true;
      req.maxRedirects = 8;
      req.headers.set('User-Agent', 'StudyPlannerApp-Updater');

      final resp = await req.close();
      if (resp.statusCode != 200) {
        throw Exception('서버 응답 오류 (HTTP ${resp.statusCode})');
      }

      final totalBytes = resp.contentLength;
      int receivedBytes = 0;
      final sink = apkFile.openWrite();

      await for (final chunk in resp) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        final progress =
            totalBytes > 0 ? (receivedBytes / totalBytes).clamp(0.0, 1.0) : -1.0;
        onProgress(progress, receivedBytes, totalBytes);
      }

      await sink.flush();
      await sink.close();

      // 안드로이드 시스템 덮어쓰기 업데이트 창 호출
      await _channel.invokeMethod('installApk');
      return true;
    } finally {
      client.close(force: true);
    }
  }

  /// 브라우저로 직접 다운로드 링크 열기 (보조 수단)
  Future<void> openDirectDownloadInBrowser([String? url]) async {
    if (kIsWeb || !Platform.isAndroid) return;
    await _channel.invokeMethod('openBrowserUrl', {
      'url': url ?? fallbackDirectDownloadUrl,
    });
  }
}
