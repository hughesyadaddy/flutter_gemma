import 'package:flutter_gemma/mobile/download_task_identity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const base =
      'https://example.supabase.co/storage/v1/object/sign/models/gemma/task';
  const target = '/data/models/gemma-3.task';
  final urlA = '$base?token=signed-a&X-Amz-Signature=aaa';
  final urlB = '$base?token=signed-b&X-Amz-Signature=bbb';

  group('download object identity', () {
    test('token-only URL change keeps the same stable task id', () {
      expect(
        stableDownloadTaskId(url: urlA, targetPath: target),
        stableDownloadTaskId(url: urlB, targetPath: target),
      );
    });

    test('token rotation differs from legacy full-url task id', () {
      expect(
        stableDownloadTaskId(url: urlA, targetPath: target),
        isNot(legacyDownloadTaskId(url: urlA, targetPath: target)),
      );
      expect(
        legacyDownloadTaskId(url: urlA, targetPath: target),
        isNot(legacyDownloadTaskId(url: urlB, targetPath: target)),
      );
    });

    test('object identity ignores query and fragment', () {
      expect(downloadObjectIdentityKey(urlA), downloadObjectIdentityKey(urlB));
      expect(
        downloadObjectIdentityKey('$base?token=x#frag'),
        downloadObjectIdentityKey(base),
      );
      expect(downloadObjectIdentityKey(urlA), isNot(contains('token=')));
    });

    test('different target paths produce different task ids', () {
      expect(
        stableDownloadTaskId(url: urlA, targetPath: target),
        isNot(
          stableDownloadTaskId(
            url: urlA,
            targetPath: '/data/models/other.task',
          ),
        ),
      );
    });
  });

  group('validateRemoteAgainstResume', () {
    test('etag mismatch restarts from zero', () {
      expect(
        validateRemoteAgainstResume(
          remoteContentLength: 1000,
          remoteEtag: '"b"',
          storedEtag: '"a"',
          localPartialBytes: 500,
        ),
        ResumeValidationDecision.restartFromZero,
      );
    });

    test('matching etag resumes from partial', () {
      expect(
        validateRemoteAgainstResume(
          remoteContentLength: 1000,
          remoteEtag: '"a"',
          storedEtag: '"a"',
          localPartialBytes: 500,
        ),
        ResumeValidationDecision.resumeFromPartial,
      );
    });
  });
}
