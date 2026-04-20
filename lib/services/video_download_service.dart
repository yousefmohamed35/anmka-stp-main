import 'dart:developer';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import '../core/services/download_manager.dart';
import '../models/download_model.dart';
import 'profile_service.dart';
import 'token_storage_service.dart';

class VideoDownloadService {
  static final VideoDownloadService _instance =
      VideoDownloadService._internal();
  factory VideoDownloadService() => _instance;
  VideoDownloadService._internal();

  static Database? _database;
  static const String _tableName = 'downloaded_videos';
  static const int _dbVersion = 2;
  static const String _prefLegacyOwnerAssignedOnce =
      'offline_downloads_owner_v2_assigned_once';

  // Initialize the download service
  Future<void> initialize() async {
    await _initializeDatabase();
    await _ensureLoggedInUserIdCached();
    await _assignLegacyDownloadsOwnerOnce();
  }

  /// Fills [TokenStorageService] user id when the user already had a session
  /// from before the app stored id on login.
  Future<void> _ensureLoggedInUserIdCached() async {
    try {
      final existing = await TokenStorageService.instance.getLoggedInUserId();
      if (existing != null && existing.isNotEmpty) return;
      final token = await TokenStorageService.instance.getAccessToken();
      if (token == null || token.isEmpty) return;
      final profile = await ProfileService.instance.getProfile();
      final id = profile['id']?.toString();
      if (id != null && id.isNotEmpty) {
        await TokenStorageService.instance.saveLoggedInUserId(id);
      }
    } catch (e) {
      print('⚠️ _ensureLoggedInUserIdCached: $e');
    }
  }

  Future<String?> _loggedInUserId() async {
    final id = await TokenStorageService.instance.getLoggedInUserId();
    if (id == null || id.isEmpty) return null;
    return id;
  }

  /// One-time: rows created before [owner_user_id] existed are attributed to the
  /// first signed-in account that opens the DB after upgrade (shared-tablet edge case).
  Future<void> _assignLegacyDownloadsOwnerOnce() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_prefLegacyOwnerAssignedOnce) == true) return;
      final uid = await _loggedInUserId();
      if (uid == null || _database == null) return;
      await _database!.rawUpdate(
        'UPDATE $_tableName SET owner_user_id = ? WHERE owner_user_id IS NULL',
        [uid],
      );
      await prefs.setBool(_prefLegacyOwnerAssignedOnce, true);
    } catch (e) {
      print('❌ _assignLegacyDownloadsOwnerOnce: $e');
    }
  }

  String _sanitizeFileName(String input) {
    var sanitized = input.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    if (sanitized.isEmpty) return 'video';
    // اختصار الاسم الطويل جداً
    if (sanitized.length > 60) {
      sanitized = sanitized.substring(0, 60);
    }
    return sanitized;
  }

  // Initialize local database for downloaded videos
  Future<void> _initializeDatabase() async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final path = join(documentsDirectory.path, 'downloaded_videos.db');

    _database = await openDatabase(
      path,
      version: _dbVersion,
      onCreate: (db, version) {
        return db.execute(
          '''
          CREATE TABLE $_tableName(
            id TEXT PRIMARY KEY,
            lesson_id TEXT,
            course_id TEXT,
            course_title TEXT,
            title TEXT,
            description TEXT,
            video_url TEXT,
            local_path TEXT,
            file_size INTEGER,
            file_size_mb REAL,
            file_type TEXT,
            duration INTEGER,
            duration_text TEXT,
            video_source TEXT,
            downloaded_at TEXT,
            thumbnail_path TEXT,
            owner_user_id TEXT
          )
          ''',
        );
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          try {
            await db.execute(
              'ALTER TABLE $_tableName ADD COLUMN owner_user_id TEXT',
            );
          } catch (e) {
            print('ALTER owner_user_id (may already exist): $e');
          }
        }
      },
    );
  }

  /// Downloads are stored under the app support directory ([DownloadManager]);
  /// no READ_MEDIA_* or legacy storage permission is required.
  Future<bool> requestPermission() async => true;

  Future<bool> hasStoragePermission() async => true;

  /// تحميل فيديو باستخدام DownloadManager
  Future<String?> downloadVideoWithManager({
    required String videoUrl,
    required String lessonId,
    required String courseId,
    required String title,
    String? courseTitle,
    String? description,
    double? fileSizeMb,
    String? durationText,
    String? videoSource,
    Function(int progress)? onProgress,
  }) async {
    try {
      if (_database == null) {
        await _initializeDatabase();
      }

      print('🎬 Starting video download with DownloadManager');
      print('Video URL: $videoUrl');
      print('Lesson ID: $lessonId');

      // الحصول على token للمصادقة
      final token = await TokenStorageService.instance.getAccessToken();
      final ownerUserId = await _loggedInUserId();

      // إنشاء اسم ملف فريد يعتمد على اسم الكورس واسم الدرس
      final safeCourseTitle =
          _sanitizeFileName(courseTitle ?? 'course_$courseId');
      final safeLessonTitle = _sanitizeFileName(title);
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = '${safeCourseTitle}_${safeLessonTitle}_$timestamp.mp4';

      // تحميل الفيديو باستخدام DownloadManager
      String? localPath = await DownloadManager.download(
        videoUrl,
        name: fileName,
        onDownload: (progress) {
          print('Download progress: $progress%');
          // استدعاء callback التقدم إذا كان موجوداً
          if (onProgress != null) {
            onProgress(progress);
          }
        },
        isOpen: false,
        authToken: token,
      );

      if (localPath != null) {
        log(localPath);
        //print('✅ Video downloaded successfully to: $localPath');

        // حفظ معلومات الفيديو في قاعدة البيانات
        String videoId = DateTime.now().millisecondsSinceEpoch.toString();

        await _database?.insert(
          _tableName,
          {
            'id': videoId,
            'lesson_id': lessonId,
            'course_id': courseId,
            'course_title': courseTitle ?? 'كورس $courseId',
            'title': title,
            'description': description ?? '',
            'video_url': videoUrl,
            'local_path': localPath,
            'file_size': 0, // سيتم حسابه لاحقاً
            'file_size_mb': fileSizeMb ?? 0.0,
            'file_type': 'video/mp4',
            'duration': 0,
            'duration_text': durationText ?? '',
            'video_source': videoSource ?? 'server',
            'downloaded_at': DateTime.now().toIso8601String(),
            'thumbnail_path': '',
            'owner_user_id': ownerUserId,
          },
        );

        print('✅ Video info saved to database');
        return videoId;
      } else {
        print('❌ Video download failed');
        return null;
      }
    } catch (e) {
      print('❌ Error downloading video with DownloadManager: $e');
      return null;
    }
  }

  /// حفظ فيديو تم تحميله مسبقاً (مثلاً من YouTube) في قاعدة البيانات
  Future<String?> saveDownloadedVideoRecord({
    required String lessonId,
    required String courseId,
    required String title,
    required String videoUrl,
    required String localPath,
    String? courseTitle,
    String? description,
    double? fileSizeMb,
    String? durationText,
    String videoSource = 'server',
  }) async {
    try {
      if (_database == null) {
        await _initializeDatabase();
      }

      final videoId = DateTime.now().millisecondsSinceEpoch.toString();
      final ownerUserId = await _loggedInUserId();

      await _database?.insert(
        _tableName,
        {
          'id': videoId,
          'lesson_id': lessonId,
          'course_id': courseId,
          'course_title': courseTitle ?? 'كورس $courseId',
          'title': title,
          'description': description ?? '',
          'video_url': videoUrl,
          'local_path': localPath,
          'file_size': 0,
          'file_size_mb': fileSizeMb ?? 0.0,
          'file_type': 'video/mp4',
          'duration': 0,
          'duration_text': durationText ?? '',
          'video_source': videoSource,
          'downloaded_at': DateTime.now().toIso8601String(),
          'thumbnail_path': '',
          'owner_user_id': ownerUserId,
        },
      );

      print('✅ External video info saved to database (source: $videoSource)');
      return videoId;
    } catch (e) {
      print('❌ Error saving downloaded video record: $e');
      return null;
    }
  }

  /// الحصول على معلومات التحميل من API
  Future<DownloadData?> getDownloadInfo(String lessonId) async {
    try {
      // TODO: إضافة endpoint للتحميل في API إذا كان موجوداً
      // حالياً سنستخدم lesson content للحصول على معلومات الفيديو
      // يمكن تعديل هذا لاحقاً إذا كان هناك endpoint مخصص للتحميل

      // يمكن إضافة endpoint مثل: ApiEndpoints.downloadLesson(lessonId)
      return null;
    } catch (e) {
      print('❌ Error getting download info: $e');
      return null;
    }
  }

  /// التحقق من وجود ملف محمل مسبقاً
  Future<String?> checkLocalVideoFile(String lessonId) async {
    if (_database == null) {
      await _initializeDatabase();
    }
    final uid = await _loggedInUserId();
    if (uid == null) return null;

    // البحث في قاعدة البيانات أولاً
    final result = await _database?.query(
      _tableName,
      where: 'lesson_id = ? AND owner_user_id = ?',
      whereArgs: [lessonId, uid],
      limit: 1,
    );

    if (result?.isNotEmpty ?? false) {
      final localPath = result!.first['local_path'] as String;

      // التحقق من وجود الملف فعلياً
      final file = File(localPath);
      if (await file.exists()) {
        print('✅ Local video file exists: $localPath');
        return localPath;
      } else {
        print('🚫 Local video file not found, cleaning database entry');
        // حذف السجل من قاعدة البيانات إذا كان الملف غير موجود
        await _database?.delete(
          _tableName,
          where: 'lesson_id = ? AND owner_user_id = ?',
          whereArgs: [lessonId, uid],
        );
      }
    }

    return null;
  }

  /// الحصول على جميع الفيديوهات المحملة
  Future<List<DownloadedVideoModel>> getDownloadedVideosWithManager() async {
    try {
      print('Getting downloaded videos from database...');

      if (_database == null) {
        await _initializeDatabase();
      }

      final uid = await _loggedInUserId();
      if (uid == null) {
        print('No logged-in user id; skipping downloaded videos list');
        return [];
      }

      final results = await _database?.query(
        _tableName,
        where: 'owner_user_id = ?',
        whereArgs: [uid],
      );

      if (results == null || results.isEmpty) {
        print('No downloaded videos found in database');
        return [];
      }

      print('Found ${results.length} videos in database');

      List<DownloadedVideoModel> videos = [];

      for (final row in results) {
        final localPath = row['local_path'] as String;
        final file = File(localPath);

        // التحقق من وجود الملف
        if (await file.exists()) {
          print('✅ Video file exists: $localPath');

          // حساب حجم الملف الفعلي
          int fileSize = await file.length();
          double fileSizeMb = fileSize / (1024 * 1024);

          videos.add(DownloadedVideoModel(
            id: row['id'] as String,
            lessonId: row['lesson_id'] as String,
            courseId: row['course_id'] as String,
            courseTitle:
                row['course_title'] as String? ?? 'كورس ${row['course_id']}',
            title: row['title'] as String,
            description: row['description'] as String,
            videoUrl: row['video_url'] as String,
            localPath: localPath,
            fileSize: fileSize,
            fileSizeMb: fileSizeMb,
            fileType: row['file_type'] as String,
            duration: row['duration'] as int,
            durationText: row['duration_text'] as String,
            videoSource: row['video_source'] as String,
            downloadedAt: DateTime.parse(row['downloaded_at'] as String),
            thumbnailPath: row['thumbnail_path'] as String? ?? '',
          ));
        } else {
          print('🚫 Video file not found, removing from database: $localPath');
          // حذف السجل إذا كان الملف غير موجود
          await _database?.delete(
            _tableName,
            where: 'id = ? AND owner_user_id = ?',
            whereArgs: [row['id'], uid],
          );
        }
      }

      print('Returning ${videos.length} valid videos');
      return videos;
    } catch (e) {
      print('Error getting downloaded videos: $e');
      return [];
    }
  }

  /// حذف فيديو محمل
  Future<bool> deleteDownloadedVideo(String videoId) async {
    try {
      if (_database == null) {
        await _initializeDatabase();
      }
      final uid = await _loggedInUserId();
      if (uid == null) return false;

      // الحصول على معلومات الفيديو من قاعدة البيانات
      final result = await _database?.query(
        _tableName,
        where: 'id = ? AND owner_user_id = ?',
        whereArgs: [videoId, uid],
        limit: 1,
      );

      if (result?.isNotEmpty ?? false) {
        final localPath = result!.first['local_path'] as String;
        final fileName = basename(localPath);

        // حذف الملف من التخزين
        await DownloadManager.deleteFile(fileName);

        // حذف السجل من قاعدة البيانات
        await _database?.delete(
          _tableName,
          where: 'id = ? AND owner_user_id = ?',
          whereArgs: [videoId, uid],
        );

        print('✅ Video deleted successfully');
        return true;
      } else {
        print('🚫 Video not found in database');
        return false;
      }
    } catch (e) {
      print('❌ Error deleting video: $e');
      return false;
    }
  }

  /// Deletes every offline lesson video for the **currently signed-in student**
  /// on this device and removes their rows from the local DB.
  /// Returns how many download records were cleared.
  Future<int> clearAllDownloadedVideos() async {
    try {
      if (_database == null) {
        await _initializeDatabase();
      }

      final uid = await _loggedInUserId();
      if (uid == null) {
        return 0;
      }

      final results = await _database?.query(
            _tableName,
            where: 'owner_user_id = ?',
            whereArgs: [uid],
          ) ??
          [];
      final rowCount = results.length;

      for (final row in results) {
        final localPath = row['local_path'] as String?;
        if (localPath == null || localPath.isEmpty) continue;
        try {
          final file = File(localPath);
          if (await file.exists()) {
            await file.delete();
          }
        } catch (e) {
          print('clearAllDownloadedVideos: could not delete $localPath: $e');
        }
      }

      await _database?.delete(
        _tableName,
        where: 'owner_user_id = ?',
        whereArgs: [uid],
      );
      return rowCount;
    } catch (e) {
      print('❌ clearAllDownloadedVideos: $e');
      rethrow;
    }
  }

  /// التحقق من أن الفيديو محمل
  Future<bool> isVideoDownloaded(String lessonId) async {
    if (_database == null) {
      await _initializeDatabase();
    }
    final uid = await _loggedInUserId();
    if (uid == null) return false;

    final result = await _database?.query(
      _tableName,
      where: 'lesson_id = ? AND owner_user_id = ?',
      whereArgs: [lessonId, uid],
      limit: 1,
    );

    if (result?.isNotEmpty ?? false) {
      final localPath = result!.first['local_path'] as String;
      final file = File(localPath);
      return await file.exists();
    }

    return false;
  }
}
