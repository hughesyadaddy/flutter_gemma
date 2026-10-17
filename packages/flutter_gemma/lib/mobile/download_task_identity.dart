import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

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

/// HTTP codes that usually mean an expired or invalid signed URL mid-resume.
bool isSignedUrlExpiryHttpCode(int? code) {
  if (code == null) return false;
  return code == 400 || code == 401 || code == 403;
}

/// Whether a remote fingerprint still matches stored resume metadata.
ResumeValidationDecision validateRemoteAgainstResume({
  required int? remoteContentLength,
  required String? remoteEtag,
  required String? storedEtag,
  required int localPartialBytes,
}) {
  if (localPartialBytes <= 0) {
    return ResumeValidationDecision.restartFromZero;
  }

  if (storedEtag != null &&
      storedEtag.isNotEmpty &&
      remoteEtag != null &&
      remoteEtag.isNotEmpty &&
      storedEtag != remoteEtag) {
    return ResumeValidationDecision.restartFromZero;
  }

  if (remoteContentLength != null &&
      remoteContentLength > 0 &&
      localPartialBytes > remoteContentLength) {
    return ResumeValidationDecision.restartFromZero;
  }

  return ResumeValidationDecision.resumeFromPartial;
}

enum ResumeValidationDecision {
  resumeFromPartial,
  restartFromZero,
}
