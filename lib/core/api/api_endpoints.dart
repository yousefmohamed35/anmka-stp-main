/// API Endpoints Configuration
class ApiEndpoints {
  ApiEndpoints._();

  static const String baseUrl = 'https://stp.anmka.com/v1';

  /// Base URL for images and media files
  static const String imageBaseUrl = 'https://stp.anmka.com';

  /// Helper method to convert relative image path to full URL
  static String getImageUrl(String? imagePath) {
    if (imagePath == null || imagePath.isEmpty) {
      return '';
    }
    // If already a full URL, return as is
    if (imagePath.startsWith('http://') || imagePath.startsWith('https://')) {
      return imagePath;
    }
    // Remove leading slash if present to avoid double slashes
    final cleanPath =
        imagePath.startsWith('/') ? imagePath.substring(1) : imagePath;
    return '$imageBaseUrl/$cleanPath';
  }

  // App Configuration
  static String get appConfig => '$baseUrl/config/app';

  // Authentication
  static String get login => '$baseUrl/auth/login';
  static String get register => '$baseUrl/auth/register';
  static String get logout => '$baseUrl/auth/logout';
  static String get forgotPassword => '$baseUrl/auth/forgot-password';
  static String get refreshToken => '$baseUrl/auth/refresh';
  static String get me => '$baseUrl/auth/me';
  static String get profile => '$baseUrl/auth/profile';
  static String get changePassword => '$baseUrl/auth/change-password';
  static String get socialLogin => '$baseUrl/auth/social-login';

  // Home Page
  static String get home => '$baseUrl/home';

  // Categories
  static String get categories => '$baseUrl/categories';
  static String categoryCourses(String id) => '$baseUrl/categories/$id/courses';

  // Courses
  static String get courses => '$baseUrl/courses';
  static String course(String id) => '$baseUrl/courses/$id';
  static String courseReviews(String id) => '$baseUrl/courses/$id/reviews';
  static String courseLesson(String courseId, String lessonId) =>
      '$baseUrl/courses/$courseId/lessons/$lessonId';
  static String courseLessonContent(String courseId, String lessonId) =>
      '$baseUrl/courses/$courseId/lessons/$lessonId/content';
  static String courseLessonProgress(String courseId, String lessonId) =>
      '$baseUrl/courses/$courseId/lessons/$lessonId/progress';

  // Enrollment
  static String enrollCourse(String id) => '$baseUrl/courses/$id/enroll';
  static String get enrollments => '$baseUrl/enrollments';

  // Payments & Checkout
  static String get payments => '$baseUrl/admin/payments';
  static String confirmPayment(String id) =>
      '$baseUrl/admin/payments/$id/confirm';
  static String get validateCoupon =>
      '$baseUrl/admin/payments/coupons/validate';

  // Exams
  static String get exams => '$baseUrl/admin/exams';
  static String exam(String id) => '$baseUrl/admin/exams/$id';
  static String startExam(String id) => '$baseUrl/admin/exams/$id/start';
  static String submitExam(String id) => '$baseUrl/admin/exams/$id/submit';

  // Course Exams
  static String courseExams(String courseId) =>
      '$baseUrl/courses/$courseId/exams';
  static String courseExamDetails(String courseId, String examId) =>
      '$baseUrl/courses/$courseId/exams/$examId';

  // Certificates
  static String get certificates => '$baseUrl/certificates';
  static String certificate(String id) => '$baseUrl/admin/certificates/$id';

  // Live Courses
  static String get liveCourses => '$baseUrl/live-courses';
  static String liveSession(String id) => '$baseUrl/admin/live-sessions/$id';

  // Notifications
  static String get notifications => '$baseUrl/notifications';
  static String markNotificationRead(String id) =>
      '$baseUrl/notifications/$id/read';
  static String get markAllNotificationsRead =>
      '$baseUrl/notifications/read-all';

  // Downloads
  static String get curriculum => '$baseUrl/admin/curriculum';
  static String curriculumItem(String id) => '$baseUrl/admin/curriculum/$id';

  // Search
  static String get search => '$baseUrl/search';

  // Wishlist
  static String get wishlist => '$baseUrl/wishlist';
  static String wishlistItem(String courseId) => '$baseUrl/wishlist/$courseId';

  // QR Code
  static String get myQrCode => '$baseUrl/my-qr-code';

  // Progress
  static String progress(String period) =>
      'https://stp.anmka.com/api/progress?period=$period';

  // Teachers
  static String get teachers => '$baseUrl/teachers';
  static String teacher(String id) => '$baseUrl/teachers/$id';
  static String teacherCourses(String id) => '$baseUrl/teachers/$id/courses';
}
