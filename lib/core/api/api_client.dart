import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../../services/token_storage_service.dart';

/// API Client for making HTTP requests
class ApiClient {
  ApiClient._();

  static final ApiClient instance = ApiClient._();

  /// Log API request
  void _logRequest(String method, String url, Map<String, String>? headers,
      Map<String, dynamic>? body) {
    if (kDebugMode) {
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print('📤 API REQUEST');
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print('Method: $method');
      print('URL: $url');
      if (headers != null && headers.isNotEmpty) {
        print('Headers:');
        headers.forEach((key, value) {
          // Hide sensitive data
          if (key.toLowerCase() == 'authorization') {
            print(
                '  $key: Bearer ${value.length > 20 ? "${value.substring(0, 20)}..." : value}');
          } else {
            print('  $key: $value');
          }
        });

        // Check if Authorization header exists
        if (!headers.containsKey('Authorization')) {
          print('  ⚠️ WARNING: Authorization header is MISSING!');
          print('  💡 This request will likely fail with 401 Unauthorized');
        }
      } else {
        print('⚠️ WARNING: No headers provided!');
      }
      if (body != null && body.isNotEmpty) {
        print('Body:');
        try {
          final prettyJson = const JsonEncoder.withIndent('  ').convert(body);
          print(prettyJson);
        } catch (e) {
          print('  $body');
        }
      }
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    }
  }

  /// Log API response
  void _logResponse(String method, String url, int statusCode,
      Map<String, dynamic>? response, String? error) {
    if (kDebugMode) {
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print('📥 API RESPONSE');
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print('Method: $method');
      print('URL: $url');
      print('Status Code: $statusCode');
      if (error != null) {
        print('❌ Error: $error');
      } else if (response != null) {
        print('Response:');
        try {
          final prettyJson =
              const JsonEncoder.withIndent('  ').convert(response);
          print(prettyJson);
        } catch (e) {
          print('  $response');
        }
      }
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    }
  }

  /// Base headers for all requests
  Future<Map<String, String>> _getHeaders({
    Map<String, String>? additionalHeaders,
    bool requireAuth = true,
  }) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    // Add authentication token from cache if required (like Dio interceptor)
    if (requireAuth) {
      // Always read token from cache (like Dio onRequest interceptor)
      final token = await TokenStorageService.instance.getAccessToken();

      if (kDebugMode) {
        print('🔑 Token Check (from cache):');
        print('  requireAuth: $requireAuth');
        print('  token exists: ${token != null}');
        print('  token length: ${token?.length ?? 0}');
      }

      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
        if (kDebugMode) {
          print('  ✅ Authorization header added from cache');
          print(
              '  token preview: ${token.length > 20 ? "${token.substring(0, 20)}..." : token}');
        }
      } else {
        if (kDebugMode) {
          print('  ⚠️ WARNING: No token found in cache');
          print(
              '  💡 Make sure you are logged in and token is cached correctly');
        }
      }
    } else {
      if (kDebugMode) {
        print('🔓 Auth not required for this request');
      }
    }

    // Add any additional headers
    if (additionalHeaders != null) {
      headers.addAll(additionalHeaders);
      // If additional headers contain Authorization, it will override the one we set
      if (additionalHeaders.containsKey('Authorization')) {
        if (kDebugMode) {
          print('  ℹ️ Authorization header provided in additionalHeaders');
        }
      }
    }

    if (kDebugMode) {
      print('📋 Final headers: ${headers.keys.toList()}');
    }

    return headers;
  }

  /// GET request
  Future<Map<String, dynamic>> get(
    String url, {
    Map<String, String>? headers,
    bool requireAuth = true,
  }) async {
    try {
      final finalHeaders = await _getHeaders(
        additionalHeaders: headers,
        requireAuth: requireAuth,
      );

      final response = await http
          .get(
            Uri.parse(url),
            headers: finalHeaders,
          )
          .timeout(const Duration(seconds: 30));

      return _handleResponse(response);
    } catch (e) {
      throw ApiException('Network error: ${e.toString()}');
    }
  }

  /// POST request
  Future<Map<String, dynamic>> post(
    String url, {
    Map<String, String>? headers,
    Map<String, dynamic>? body,
    bool requireAuth = true,
  }) async {
    try {
      final finalHeaders = await _getHeaders(
        additionalHeaders: headers,
        requireAuth: requireAuth,
      );

      // Log request AFTER getting headers (so we can see the token)
      _logRequest('POST', url, finalHeaders, body);

      final response = await http
          .post(
            Uri.parse(url),
            headers: finalHeaders,
            body: body != null ? jsonEncode(body) : null,
          )
          .timeout(const Duration(seconds: 30));

      final responseData = _handleResponse(response);
      _logResponse('POST', url, response.statusCode, responseData, null);
      return responseData;
    } catch (e) {
      _logResponse('POST', url, 0, null, e.toString());
      throw ApiException('Network error: ${e.toString()}');
    }
  }

  /// PUT request
  Future<Map<String, dynamic>> put(
    String url, {
    Map<String, String>? headers,
    Map<String, dynamic>? body,
    bool requireAuth = true,
  }) async {
    try {
      final finalHeaders = await _getHeaders(
        additionalHeaders: headers,
        requireAuth: requireAuth,
      );

      _logRequest('PUT', url, finalHeaders, body);

      final response = await http
          .put(
            Uri.parse(url),
            headers: finalHeaders,
            body: body != null ? jsonEncode(body) : null,
          )
          .timeout(const Duration(seconds: 30));

      final responseData = _handleResponse(response);
      _logResponse('PUT', url, response.statusCode, responseData, null);
      return responseData;
    } catch (e) {
      _logResponse('PUT', url, 0, null, e.toString());
      throw ApiException('Network error: ${e.toString()}');
    }
  }

  /// DELETE request
  Future<Map<String, dynamic>> delete(
    String url, {
    Map<String, String>? headers,
    bool requireAuth = true,
  }) async {
    try {
      final finalHeaders = await _getHeaders(
        additionalHeaders: headers,
        requireAuth: requireAuth,
      );

      _logRequest('DELETE', url, finalHeaders, null);

      final response = await http
          .delete(
            Uri.parse(url),
            headers: finalHeaders,
          )
          .timeout(const Duration(seconds: 30));

      final responseData = _handleResponse(response);
      _logResponse('DELETE', url, response.statusCode, responseData, null);
      return responseData;
    } catch (e) {
      _logResponse('DELETE', url, 0, null, e.toString());
      throw ApiException('Network error: ${e.toString()}');
    }
  }

  /// Multipart POST request for file uploads
  Future<Map<String, dynamic>> postMultipart(
    String url, {
    required Map<String, String> fields,
    required Map<String, File> files,
    bool requireAuth = true,
  }) async {
    try {
      final request = http.MultipartRequest('POST', Uri.parse(url));

      // Add headers (but NOT Content-Type - it will be set automatically by multipart)
      request.headers['Accept'] = 'application/json';

      // Add authentication token
      if (requireAuth) {
        final token = await TokenStorageService.instance.getAccessToken();
        if (token != null && token.isNotEmpty) {
          request.headers['Authorization'] = 'Bearer $token';
          if (kDebugMode) {
            print('🔑 Avatar Upload - Token added: ${token.length > 20 ? "${token.substring(0, 20)}..." : token}');
          }
        } else {
          if (kDebugMode) {
            print('⚠️ Avatar Upload - No token found!');
          }
        }
      }

      // Add fields
      request.fields.addAll(fields);

      // Add files
      for (var entry in files.entries) {
        final file = entry.value;
        final fieldName = entry.key;
        final fileName = file.path.split(Platform.pathSeparator).last;
        
        if (kDebugMode) {
          print('📎 Adding file: $fieldName = $fileName (${file.path})');
        }
        
        request.files.add(
          await http.MultipartFile.fromPath(
            fieldName,
            file.path,
            filename: fileName,
          ),
        );
      }

      _logRequest('POST (Multipart)', url, request.headers, {
        'fields': fields,
        'files': files.keys.toList(),
      });

      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 60),
      );

      final response = await http.Response.fromStream(streamedResponse);
      
      if (kDebugMode) {
        print('📥 Avatar Upload Response Status: ${response.statusCode}');
        print('📥 Avatar Upload Response Body: ${response.body}');
      }
      
      final responseData = _handleResponse(response);
      _logResponse('POST (Multipart)', url, response.statusCode, responseData, null);
      return responseData;
    } catch (e) {
      _logResponse('POST (Multipart)', url, 0, null, e.toString());
      if (kDebugMode) {
        print('❌ Avatar Upload Error: $e');
      }
      throw ApiException('Network error: ${e.toString()}');
    }
  }

  /// Handle HTTP response
  /// Automatically handles 401 errors by clearing cached tokens (like Dio interceptor)
  Map<String, dynamic> _handleResponse(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      try {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } catch (e) {
        if (kDebugMode) {
          print('⚠️ Failed to parse JSON response: ${response.body}');
        }
        throw ApiException('Invalid JSON response: ${e.toString()}');
      }
    } else {
      String errorMessage = 'Request failed with status ${response.statusCode}';
      Map<String, dynamic>? errorData;

      try {
        errorData = jsonDecode(response.body) as Map<String, dynamic>;
        errorMessage = errorData['message'] as String? ?? errorMessage;
      } catch (e) {
        // Not JSON, use raw body
      }

      if (kDebugMode) {
        print('❌ Error Response Body: ${response.body}');
      }

      // Handle 401 Unauthorized - token expired or invalid (like Dio onError interceptor)
      if (response.statusCode == 401) {
        if (kDebugMode) {
          print('🔒 401 Unauthorized - Token may be expired or invalid');
        }

        // Check if it's a real auth error (not validation error)
        bool isAuthError = true;
        if (errorData != null) {
          final message = errorData['message']?.toString().toLowerCase() ?? '';
          // Don't treat validation/parameter errors as auth errors
          if (message.contains('invalid') ||
              message.contains('validation') ||
              message.contains('parameter') ||
              message.contains('date') ||
              message.contains('format')) {
            isAuthError = false;
            if (kDebugMode) {
              print(
                  '  ℹ️ This appears to be a validation error, not auth error');
            }
          }
        }

        if (isAuthError) {
          // Clear cached tokens (like Dio _handleTokenExpiry)
          TokenStorageService.instance.clearTokens().then((_) {
            if (kDebugMode) {
              print(
                  '🗑️ Cleared cached tokens due to 401 authentication error');
            }
          });
        }
      }

      throw ApiException(errorMessage);
    }
  }
}

/// API Exception class
class ApiException implements Exception {
  final String message;

  ApiException(this.message);

  @override
  String toString() => message;
}
