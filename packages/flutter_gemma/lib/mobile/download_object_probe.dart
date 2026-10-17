import 'dart:io';

import 'package:meta/meta.dart';

/// Lightweight HEAD probe for resume safety (ETag + Content-Length).
class RemoteObjectProbe {
  const RemoteObjectProbe({HttpClient? httpClient})
    : _httpClient = httpClient;

  final HttpClient? _httpClient;

  Future<RemoteObjectFingerprint?> head({
    required String url,
    Map<String, String> headers = const {},
  }) async {
    final client = _httpClient ?? HttpClient();
    final ownsClient = _httpClient == null;
    try {
      final request = await client.headUrl(Uri.parse(url));
      for (final entry in headers.entries) {
        request.headers.set(entry.key, entry.value);
      }
      final response = await request.close();
      await response.drain<void>();
      final etag = response.headers.value(HttpHeaders.etagHeader);
      final lengthHeader = response.headers.value(HttpHeaders.contentLengthHeader);
      final contentLength = lengthHeader == null
          ? null
          : int.tryParse(lengthHeader);
      return RemoteObjectFingerprint(
        etag: etag,
        contentLength: contentLength,
        statusCode: response.statusCode,
      );
    } on Object {
      return null;
    } finally {
      if (ownsClient) {
        client.close(force: true);
      }
    }
  }
}

@immutable
class RemoteObjectFingerprint {
  const RemoteObjectFingerprint({
    required this.statusCode,
    this.etag,
    this.contentLength,
  });

  final int statusCode;
  final String? etag;
  final int? contentLength;
}
