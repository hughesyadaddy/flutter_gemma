import 'package:flutter_gemma/mobile/download_task_identity.dart';
import 'package:flutter_gemma/mobile/smart_downloader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const objectBase =
      'https://example.supabase.co/storage/v1/object/sign/models/gemma/model.task';
  const targetPath = '/data/models/gemma-3.task';

  group('SmartDownloader auth/url rebind policy', () {
    tearDown(SmartDownloader.debugResetConcurrencyAndProbe);

    test('token-only URL change keeps stable task id', () {
      final urlA = '$objectBase?token=signed-a';
      final urlB = '$objectBase?token=signed-b';
      expect(
        SmartDownloader.debugStableTaskId(url: urlA, targetPath: targetPath),
        SmartDownloader.debugStableTaskId(url: urlB, targetPath: targetPath),
      );
    });

    test('auth token change updates headers but not task id', () {
      const url = '$objectBase?token=signed-a';
      final headersA = SmartDownloader.debugDownloadHeaders('stale-token');
      final headersB = SmartDownloader.debugDownloadHeaders('fresh-token');
      expect(headersA['Authorization'], 'Bearer stale-token');
      expect(headersB['Authorization'], 'Bearer fresh-token');
      expect(
        stableDownloadTaskId(url: url, targetPath: targetPath),
        stableDownloadTaskId(url: url, targetPath: targetPath),
      );
    });

    test('signed URL expiry with partial bytes plans resume not hard fail', () {
      expect(isSignedUrlExpiryHttpCode(403), isTrue);
      expect(
        validateRemoteAgainstResume(
          remoteContentLength: 1_000_000,
          remoteEtag: '"gemma-v1"',
          storedEtag: '"gemma-v1"',
          localPartialBytes: 512_000,
        ),
        ResumeValidationDecision.resumeFromPartial,
      );
    });

    test('legacy task id is probed after stable id', () {
      final url = '$objectBase?token=a';
      final ids = downloadTaskIdsToProbe(url: url, targetPath: targetPath);
      expect(ids.first, stableDownloadTaskId(url: url, targetPath: targetPath));
      expect(ids, contains(legacyDownloadTaskId(url: url, targetPath: targetPath)));
    });
  });
}
