import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'models.dart';

/// A single mobile audience transport. Tokens live only in this instance and
/// are never written to preferences, logs, URLs, or a bundled configuration.
class OpcApiClient {
  OpcApiClient({
    required String baseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 30),
    this.onUnauthorized,
  }) : _client = client ?? http.Client(),
       _base = Uri.parse(baseUrl.endsWith('/') ? baseUrl : '$baseUrl/') {
    if (!['http', 'https'].contains(_base.scheme) ||
        _base.host.isEmpty ||
        _base.userInfo.isNotEmpty ||
        _base.hasQuery ||
        _base.hasFragment) {
      throw ArgumentError.value(baseUrl, 'baseUrl', 'Invalid API origin');
    }
  }

  final http.Client _client;
  final Uri _base;
  final Duration timeout;
  final void Function()? onUnauthorized;
  String? _token;
  int _generation = 0;

  void setToken(String? token) {
    _token = token;
    _generation++;
  }

  void close() {
    setToken(null);
    _client.close();
  }

  Uri _uri(String path, Map<String, String>? query) {
    final prefix = _base.path.endsWith('/api/v1/') ? '' : 'api/v1/';
    return _base.resolve('$prefix$path').replace(queryParameters: query);
  }

  Future<http.Response> send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
    String? idempotencyKey,
    bool authenticated = true,
    String? fileName,
    Uint8List? bytes,
    Duration? requestTimeout,
  }) async {
    final generation = _generation;
    final token = _token;
    if (authenticated && token == null) {
      throw const RepositoryException('unauthenticated', 'Login required');
    }
    final uri = _uri(path, query);
    final http.BaseRequest request;
    if (fileName != null && bytes != null) {
      request = http.MultipartRequest(method, uri)
        ..files.add(
          http.MultipartFile.fromBytes('file', bytes, filename: fileName),
        );
    } else {
      final jsonRequest = http.Request(method, uri);
      if (body != null) {
        jsonRequest.headers['Content-Type'] = 'application/json; charset=utf-8';
        jsonRequest.body = jsonEncode(body);
      }
      request = jsonRequest;
    }
    request.followRedirects = false;
    request.headers['Accept'] = 'application/json';
    if (authenticated) request.headers['Authorization'] = 'Bearer $token';
    if (idempotencyKey != null) {
      request.headers['Idempotency-Key'] = idempotencyKey;
    }
    try {
      final response = await _client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(requestTimeout ?? timeout);
      if (generation != _generation) {
        throw const RepositoryException('session_changed', 'Session changed');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        var code = 'request_failed';
        var message = 'Request failed';
        try {
          final data = jsonDecode(utf8.decode(response.bodyBytes));
          if (data is Map && data['error'] is Map) {
            code = (data['error']['code'] as String? ?? code).toLowerCase();
            message = data['error']['message'] as String? ?? message;
          }
        } catch (_) {
          /* Proxies may return HTML; never display it as UI content. */
        }
        if (response.statusCode == 401 && authenticated) {
          setToken(null);
          onUnauthorized?.call();
          code = 'unauthenticated';
        }
        if (response.statusCode == 503 && code == 'request_failed') {
          code = 'network_unavailable';
        }
        throw RepositoryException(code, message);
      }
      return response;
    } on RepositoryException {
      rethrow;
    } on TimeoutException {
      throw const RepositoryException(
        'network_unavailable',
        'Request timed out',
      );
    } on http.ClientException {
      throw const RepositoryException(
        'network_unavailable',
        'Network unavailable',
      );
    }
  }

  Future<Map<String, dynamic>> json(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
    String? idempotencyKey,
    bool authenticated = true,
  }) async {
    final response = await send(
      method,
      path,
      body: body,
      query: query,
      idempotencyKey: idempotencyKey,
      authenticated: authenticated,
    );
    return decode(response);
  }

  Map<String, dynamic> decode(http.Response response) {
    try {
      final value = jsonDecode(utf8.decode(response.bodyBytes));
      if (value is Map<String, dynamic>) return value;
    } catch (_) {
      /* Fail closed on malformed or unexpected service output. */
    }
    throw const RepositoryException(
      'invalid_response',
      'Invalid service response',
    );
  }
}
