import 'package:flutter/foundation.dart';
import '../core/api/api_client.dart';
import '../core/api/api_endpoints.dart';

/// Service for QR code operations
class QrCodeService {
  QrCodeService._();

  static final QrCodeService instance = QrCodeService._();

  /// Get user's QR code
  Future<String> getMyQrCode() async {
    try {
      if (kDebugMode) {
        print('📱 Fetching QR code from: ${ApiEndpoints.myQrCode}');
      }

      final response = await ApiClient.instance.get(
        ApiEndpoints.myQrCode,
        requireAuth: true,
      );

      if (kDebugMode) {
        print('📱 QR code response:');
        print('  success: ${response['success']}');
        print('  data: ${response['data']}');
      }

      if (response['success'] == true && response['data'] != null) {
        final data = response['data'] as Map<String, dynamic>?;
        
        // Get userId from user object
        final user = data?['user'] as Map<String, dynamic>?;
        final userId = user?['id']?.toString();
        
        if (userId == null || userId.isEmpty) {
          throw Exception('User ID not found in response');
        }
        
        if (kDebugMode) {
          print('✅ User ID extracted: $userId');
        }
        
        // Return userId as string for QR code
        return userId;
      } else {
        final errorMsg = response['message'] ?? 'Failed to fetch QR code';
        if (kDebugMode) {
          print('❌ QR code API error: $errorMsg');
        }
        throw Exception(errorMsg);
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ QrCodeService.getMyQrCode error: $e');
      }
      rethrow;
    }
  }
}

