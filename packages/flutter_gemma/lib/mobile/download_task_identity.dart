import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Object identity for a download URL — never tokens, query, or auth.
///
/// Uses scheme + host + path (query/fragment stripped). Supabase signed URLs
/// keep a stable path under `/storage/v1/object/sign/<bucket>/...`; rotating
/// `token` query params does not change identity.
String downloadObjectIdentityKey(String url) {
  final uri = Uri.parse(url);
  return uri.replace(queryParameters: const {}, fragment: '').toString();
}

String downloadUrlIdentityBase(String url) => downloadObjectIdentityKey(url);

/// Legacy task id (full URL string hash + target path).
String legacyDownloadTaskId({
  required String url,
  required String targetPath,
}) {
  return '${url.hashCode.toUnsigned(32).toRadixString(16)}_'
      '${targetPath.hashCode.toUnsigned(32).toRadixString(16)}';
}

/// Stable task id for a model file download.
String stableDownloadTaskId({
  required String url,
  required String targetPath,
}) {
  final material = '${downloadObjectIdentityKey(url)}|$targetPath';
  final digest = sha256.convert(utf8.encode(material));
  return 'sd_${digest.toString().substring(0, 16)}';
}

/// Ordered ids to probe when attaching to persisted background_downloader tasks.
List<String> downloadTaskIdsToProbe({
  required String url,
  required String targetPath,
}) {
  final stable = stableDownloadTaskId(url: url, targetPath: targetPath);
  final legacy = legacyDownloadTaskId(url: url, targetPath: targetPath);
  if (stable == legacy) {
    return [stable];
  }
  return [stable, legacy];
}

/// HTTP codes that should trigger URL/auth re-bind when partial bytes exist.
///
/// [400] is included only when [detail] looks auth- or expiry-related; a bare
/// generic 400 does not re-bind.
bool isAuthOrExpiryRebindHttpCode(int? code, {String? detail}) {
  if (code == null) return false;
  if (code == 401 || code == 403) return true;
  if (code != 400) return false;
  if (detail == null || detail.trim().isEmpty) {
    return false;
  }
  final lower = detail.toLowerCase();
  const needles = [
    'expired',
    'expire',
    'token',
    'signature',
    'signed url',
    'unauthorized',
    'forbidden',
    'invalid jwt',
    'bad signature',
    'access denied',
    'auth',
  ];
  for (final needle in needles) {
    if (lower.contains(needle)) {
      return true;
    }
  }
  return false;
}

@Deprecated('Use isAuthOrExpiryRebindHttpCode')
bool isSignedUrlExpiryHttpCode(int? code) =>
    isAuthOrExpiryRebindHttpCode(code);

enum ResumeValidationDecision {
  /// Safe to continue from existing partial bytes.
  resumeFromPartial,

  /// Server proved the object changed (ETag mismatch, size, full 200 on If-Range).
  objectChanged,

  /// HEAD/network inconclusive — keep partial, try Range or retry later.
  inconclusive,
}

/// Whether a remote fingerprint still matches stored resume metadata.
ResumeValidationDecision validateRemoteAgainstResume({
  required int? remoteContentLength,
  required String? remoteEtag,
  required String? storedEtag,
  required int localPartialBytes,
}) {
  if (localPartialBytes <= 0) {
    return ResumeValidationDecision.resumeFromPartial;
  }

  if (storedEtag != null &&
      storedEtag.isNotEmpty &&
      remoteEtag != null &&
      remoteEtag.isNotEmpty &&
      storedEtag != remoteEtag) {
    return ResumeValidationDecision.objectChanged;
  }

  if (remoteContentLength != null &&
      remoteContentLength > 0 &&
      localPartialBytes > remoteContentLength) {
    return ResumeValidationDecision.objectChanged;
  }

  return ResumeValidationDecision.resumeFromPartial;
}

/// Interprets a HEAD probe for resume (or HEAD failure / unsupported HEAD).
ResumeValidationDecision evaluateHeadProbeForResume({
  required bool headAttempted,
  required int? headStatusCode,
  required int? remoteContentLength,
  required String? remoteEtag,
  required int localPartialBytes,
  required String? storedEtag,
}) {
  if (localPartialBytes <= 0) {
    return ResumeValidationDecision.resumeFromPartial;
  }
  if (!headAttempted) {
    return ResumeValidationDecision.inconclusive;
  }
  if (headStatusCode == null) {
    return ResumeValidationDecision.inconclusive;
  }
  if (headStatusCode == 405 || headStatusCode == 501) {
    return ResumeValidationDecision.inconclusive;
  }
  if (headStatusCode >= 400) {
    return ResumeValidationDecision.inconclusive;
  }
  return validateRemoteAgainstResume(
    remoteContentLength: remoteContentLength,
    remoteEtag: remoteEtag,
    storedEtag: storedEtag,
    localPartialBytes: localPartialBytes,
  );
}

enum ManualRangeResult {
  completed,
  retryLater,
  objectChanged,
}
