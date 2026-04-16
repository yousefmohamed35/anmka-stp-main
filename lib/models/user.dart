import 'package:flutter/foundation.dart';

/// User Model
class User {
  final String id;
  final String name;
  final String email;
  final String phone;
  final String? avatar;
  final String? avatarThumbnail;
  final String role;
  final bool isVerified;

  /// Whether the user has verified their email (see `email_verified` from API).
  /// When the API omits this field, defaults to true for backward compatibility.
  final bool emailVerified;
  final String createdAt;
  final String? studentType; // "online" or "offline"

  User({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    this.avatar,
    this.avatarThumbnail,
    required this.role,
    required this.isVerified,
    required this.emailVerified,
    required this.createdAt,
    this.studentType,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    if (kDebugMode) {
      print('👤 Parsing User from JSON...');
      print('  json keys: ${json.keys.toList()}');
      print('  id: ${json['id']}');
      print('  email: ${json['email']}');
      print('  name: ${json['name']}');
      print('  status: ${json['status']}');
    }

    final hasEmailVerifiedKey =
        json.containsKey('email_verified') || json.containsKey('emailVerified');
    final emailVerified = hasEmailVerifiedKey
        ? (json['email_verified'] as bool? ??
            json['emailVerified'] as bool? ??
            false)
        : true;

    return User(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? json['nameAr'] as String? ?? '',
      email: json['email'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      avatar: json['avatar'] as String?,
      avatarThumbnail: json['avatar_thumbnail'] as String?,
      role: json['role'] as String? ?? 'student',
      isVerified: json['is_verified'] as bool? ?? false,
      emailVerified: emailVerified,
      createdAt: json['created_at'] as String? ?? '',
      studentType:
          json['studentType'] as String? ?? json['student_type'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'phone': phone,
      'avatar': avatar,
      'avatar_thumbnail': avatarThumbnail,
      'role': role,
      'is_verified': isVerified,
      'email_verified': emailVerified,
      'created_at': createdAt,
      'studentType': studentType,
    };
  }
}
