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
  final String createdAt;

  User({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    this.avatar,
    this.avatarThumbnail,
    required this.role,
    required this.isVerified,
    required this.createdAt,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      email: json['email'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      avatar: json['avatar'] as String?,
      avatarThumbnail: json['avatar_thumbnail'] as String?,
      role: json['role'] as String? ?? 'student',
      isVerified: json['is_verified'] as bool? ?? false,
      createdAt: json['created_at'] as String? ?? '',
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
      'created_at': createdAt,
    };
  }
}

