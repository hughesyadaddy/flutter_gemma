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

  group('isAuthOrExpiryRebindHttpCode', () {
    test('401 and 403 always re-bind when partial exists', () {
      expect(isAuthOrExpiryRebindHttpCode(401), isTrue);
      expect(isAuthOrExpiryRebindHttpCode(403), isTrue);
    });

    test('generic 400 without detail does not re-bind', () {
      expect(isAuthOrExpiryRebindHttpCode(400), isFalse);
      expect(isAuthOrExpiryRebindHttpCode(400, detail: 'malformed field'), isFalse);
    });

    test('expiry-shaped 400 re-binds', () {
      expect(
        isAuthOrExpiryRebindHttpCode(
          400,
          detail: 'InvalidJWT: token is expired',
        ),
        isTrue,
      );
    });
  });

  group('validateRemoteAgainstResume', () {
    test('etag mismatch proves object changed', () {
      expect(
        validateRemoteAgainstResume(
          remoteContentLength: 1000,
          remoteEtag: '"b"',
          storedEtag: '"a"',
          localPartialBytes: 500,
        ),
        ResumeValidationDecision.objectChanged,
      );
    });

    test('partial larger than remote length proves object changed', () {
      expect(
        validateRemoteAgainstResume(
          remoteContentLength: 100,
          remoteEtag: '"a"',
          storedEtag: '"a"',
          localPartialBytes: 500,
        ),
        ResumeValidationDecision.objectChanged,
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

  group('evaluateHeadProbeForResume', () {
    test('HEAD failure keeps partial (inconclusive)', () {
      expect(
        evaluateHeadProbeForResume(
          headAttempted: true,
          headStatusCode: null,
          remoteContentLength: null,
          remoteEtag: null,
          localPartialBytes: 512_000,
          storedEtag: '"gemma"',
        ),
        ResumeValidationDecision.inconclusive,
      );
    });

    test('HEAD unsupported keeps partial (inconclusive)', () {
      expect(
        evaluateHeadProbeForResume(
          headAttempted: true,
          headStatusCode: 405,
          remoteContentLength: null,
          remoteEtag: null,
          localPartialBytes: 100,
          storedEtag: '"gemma"',
        ),
        ResumeValidationDecision.inconclusive,
      );
    });

    test('HEAD 403 with partial is inconclusive (try Range, not truncate)', () {
      expect(
        evaluateHeadProbeForResume(
          headAttempted: true,
          headStatusCode: 403,
          remoteContentLength: null,
          remoteEtag: null,
          localPartialBytes: 100,
          storedEtag: '"gemma"',
        ),
        ResumeValidationDecision.inconclusive,
      );
    });
  });
}
