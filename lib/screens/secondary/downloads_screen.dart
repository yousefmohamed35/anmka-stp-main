import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:skeletonizer/skeletonizer.dart';
import '../../core/design/app_colors.dart';
import '../../core/design/app_text_styles.dart';
import '../../core/design/app_radius.dart';
import '../../core/localization/localization_helper.dart';
import '../../services/downloads_service.dart';

/// Downloads Screen - Pixel-perfect match to React version
/// Matches: components/screens/downloads-screen.tsx
class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _files = [];
  double _storageUsedMB = 0;
  double _storageLimitMB = 500;
  double _storagePercentage = 0;

  @override
  void initState() {
    super.initState();
    _loadDownloads();
  }

  Future<void> _loadDownloads() async {
    setState(() => _isLoading = true);
    try {
      final response = await DownloadsService.instance.getDownloads();

      if (kDebugMode) {
        print('✅ Downloads loaded:');
        print('  storage_used_mb: ${response['storage_used_mb']}');
        print('  storage_limit_mb: ${response['storage_limit_mb']}');
        print('  files: ${response['files']?.length ?? 0}');
      }

      setState(() {
        _storageUsedMB = (response['storage_used_mb'] as num?)?.toDouble() ?? 0;
        _storageLimitMB =
            (response['storage_limit_mb'] as num?)?.toDouble() ?? 500;
        _storagePercentage =
            (response['storage_percentage'] as num?)?.toDouble() ?? 0;

        if (response['files'] is List) {
          _files = List<Map<String, dynamic>>.from(
            response['files'] as List,
          );
        } else {
          _files = [];
        }
        _isLoading = false;
      });
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error loading downloads: $e');
      }
      setState(() {
        _files = [];
        _storageUsedMB = 0;
        _storageLimitMB = 500;
        _storagePercentage = 0;
        _isLoading = false;
      });
    }
  }

  String _formatSize(double sizeMB) {
    if (sizeMB >= 1024) {
      return '${(sizeMB / 1024).toStringAsFixed(1)} GB';
    } else {
      return '${sizeMB.toStringAsFixed(0)} MB';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.beige,
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            // Header - Purple gradient like Home
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF7C3AED), Color(0xFF5B21B6)],
                ),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(AppRadius.largeCard),
                  bottomRight: Radius.circular(AppRadius.largeCard),
                ),
              ),
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 16, // pt-4
                bottom: 32, // pb-8
                left: 16, // px-4
                right: 16,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Back button and title - matches React: gap-4 mb-4
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () => context.pop(),
                        child: Container(
                          width: 40, // w-10
                          height: 40, // h-10
                          decoration: const BoxDecoration(
                            color: AppColors.whiteOverlay20, // bg-white/20
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.chevron_right,
                            color: Colors.white,
                            size: 20, // w-5 h-5
                          ),
                        ),
                      ),
                      const SizedBox(width: 16), // gap-4
                      Text(
                        context.l10n.downloads,
                        style: AppTextStyles.h3(color: Colors.white),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16), // mb-4
                  // Download count - matches React: gap-2
                  Row(
                    children: [
                      Icon(
                        Icons.download,
                        size: 20, // w-5 h-5
                        color: Colors.white.withOpacity(0.7), // white/70
                      ),
                      const SizedBox(width: 8), // gap-2
                      Text(
                        context.l10n.downloadedFiles(_files.length),
                        style: AppTextStyles.bodyMedium(
                          color: Colors.white.withOpacity(0.7), // white/70
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Content - matches React: px-4 -mt-4 space-y-4
            Expanded(
              child: Transform.translate(
                offset: const Offset(0, -16), // -mt-4
                child: _isLoading
                    ? _buildLoadingState()
                    : RefreshIndicator(
                        onRefresh: _loadDownloads,
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16), // px-4
                          physics: const AlwaysScrollableScrollPhysics(),
                          child: Column(
                            children: [
                              // Storage Card - matches React: bg-white rounded-3xl p-5 shadow-lg
                              _buildStorageCard(),

                              // Downloaded Files List
                              if (_files.isEmpty)
                                _buildEmptyState()
                              else
                                ..._files.asMap().entries.map((entry) {
                                  final index = entry.key;
                                  final file = entry.value;
                                  return TweenAnimationBuilder<double>(
                                    tween: Tween(begin: 0.0, end: 1.0),
                                    duration: Duration(
                                        milliseconds: 400 + (index * 100)),
                                    curve: Curves.easeOut,
                                    builder: (context, value, child) {
                                      return Transform.translate(
                                        offset: Offset(0, 20 * (1 - value)),
                                        child: Opacity(
                                          opacity: value,
                                          child: child,
                                        ),
                                      );
                                    },
                                    child: _buildDownloadCard(context, file),
                                  );
                                }),

                              const SizedBox(height: 32),
                            ],
                          ),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStorageCard() {
    final usedGB = _storageUsedMB / 1024;
    final limitGB = _storageLimitMB / 1024;
    final percentage = _storagePercentage / 100;

    return Container(
      margin: const EdgeInsets.only(bottom: 16), // space-y-4
      padding: const EdgeInsets.all(20), // p-5
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24), // rounded-3xl
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          // Storage icon and info - matches React: gap-3 mb-4
          Padding(
            padding: const EdgeInsets.only(bottom: 16), // mb-4
            child: Row(
              children: [
                Container(
                  width: 48, // w-12
                  height: 48, // h-12
                  decoration: BoxDecoration(
                    color: AppColors.purple.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12), // rounded-xl
                  ),
                  child: const Icon(
                    Icons.storage,
                    size: 24, // w-6 h-6
                    color: AppColors.purple,
                  ),
                ),
                const SizedBox(width: 12), // gap-3
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10n.storage,
                        style: AppTextStyles.bodyMedium(
                          color: AppColors.foreground,
                        ).copyWith(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        context.l10n.storageUsed(
                          usedGB.toStringAsFixed(1),
                          limitGB.toStringAsFixed(1),
                        ),
                        style: AppTextStyles.bodySmall(
                          color: AppColors.mutedForeground,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Progress bar - matches React: h-3 bg-gray-100 rounded-full
          Container(
            height: 12, // h-3
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(999), // rounded-full
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerRight,
              widthFactor:
                  percentage > 1 ? 1 : (percentage < 0 ? 0 : percentage),
              child: Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.purple, AppColors.orange],
                  ),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDownloadCard(BuildContext context, Map<String, dynamic> file) {
    // Extract data from API
    final course = file['course'] as Map<String, dynamic>?;
    final title = course?['title']?.toString() ??
        file['title']?.toString() ??
        context.l10n.file;
    final thumbnail = course?['thumbnail']?.toString() ??
        file['thumbnail']?.toString() ??
        file['image']?.toString();
    final sizeMB = (file['size_mb'] as num?)?.toDouble() ??
        (file['size'] as num?)?.toDouble() ??
        0;
    final sizeStr =
        sizeMB > 0 ? _formatSize(sizeMB) : context.l10n.undefinedSize;
    final lessons = (file['lessons'] as num?)?.toInt() ??
        (file['total_lessons'] as num?)?.toInt() ??
        0;
    final downloadedLessons = (file['downloaded_lessons'] as num?)?.toInt() ??
        (file['completed_lessons'] as num?)?.toInt() ??
        lessons;
    final isComplete = downloadedLessons >= lessons && lessons > 0;
    final progress = lessons > 0 ? downloadedLessons / lessons : 1.0;
    final fileId = file['id']?.toString() ?? '';
    final resourceId = file['resource_id']?.toString() ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12), // space-y-3
      padding: const EdgeInsets.all(16), // p-4
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16), // rounded-2xl
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Course info row - matches React: flex items-center gap-4
          Row(
            children: [
              // Course image - matches React: w-16 h-16 rounded-xl
              Container(
                width: 64, // w-16
                height: 64, // h-16
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12), // rounded-xl
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: thumbnail != null && thumbnail.isNotEmpty
                      ? Image.network(
                          thumbnail,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              Container(
                            color: AppColors.purple.withOpacity(0.1),
                            child: const Icon(
                              Icons.image,
                              color: AppColors.purple,
                            ),
                          ),
                        )
                      : Container(
                          color: AppColors.purple.withOpacity(0.1),
                          child: const Icon(
                            Icons.image,
                            color: AppColors.purple,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 16), // gap-4

              // Course info - matches React: flex-1
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTextStyles.bodyMedium(
                        color: AppColors.foreground,
                      ).copyWith(fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4), // mb-1
                    Row(
                      children: [
                        if (lessons > 0)
                          Text(
                            '$downloadedLessons/$lessons درس',
                            style: AppTextStyles.labelSmall(
                              color: AppColors.mutedForeground,
                            ),
                          ),
                        if (lessons > 0) ...[
                          const SizedBox(width: 8),
                          Text(
                            '•',
                            style: AppTextStyles.labelSmall(
                              color: AppColors.mutedForeground,
                            ),
                          ),
                        ],
                        const SizedBox(width: 8),
                        Text(
                          sizeStr,
                          style: AppTextStyles.labelSmall(
                            color: AppColors.mutedForeground,
                          ),
                        ),
                      ],
                    ),
                    // Partial download progress bar
                    if (!isComplete) ...[
                      const SizedBox(height: 8), // mt-2
                      Container(
                        height: 6, // h-1.5
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: FractionallySizedBox(
                          alignment: Alignment.centerRight,
                          widthFactor: progress,
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppColors.orange,
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // Action buttons - matches React: flex flex-col gap-2
              Column(
                children: [
                  // Status/Download button - matches React: w-10 h-10 rounded-xl
                  if (isComplete)
                    Container(
                      width: 40, // w-10
                      height: 40, // h-10
                      decoration: BoxDecoration(
                        color: Colors.green[100],
                        borderRadius: BorderRadius.circular(12), // rounded-xl
                      ),
                      child: Icon(
                        Icons.check_circle,
                        size: 20, // w-5 h-5
                        color: Colors.green[600],
                      ),
                    )
                  else
                    GestureDetector(
                      onTap: () => _handleDownload(file, resourceId),
                      child: Container(
                        width: 40, // w-10
                        height: 40, // h-10
                        decoration: BoxDecoration(
                          color: AppColors.orange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12), // rounded-xl
                        ),
                        child: const Icon(
                          Icons.download,
                          size: 20, // w-5 h-5
                          color: AppColors.orange,
                        ),
                      ),
                    ),
                  const SizedBox(height: 8), // gap-2
                  // Delete button - matches React: w-10 h-10 rounded-xl bg-red-50
                  GestureDetector(
                    onTap: () => _handleDelete(file, fileId),
                    child: Container(
                      width: 40, // w-10
                      height: 40, // h-10
                      decoration: BoxDecoration(
                        color: Colors.red[50],
                        borderRadius: BorderRadius.circular(12), // rounded-xl
                      ),
                      child: Icon(
                        Icons.delete,
                        size: 20, // w-5 h-5
                        color: Colors.red[500],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 12), // mt-3

          // Play button - matches React: w-full py-3 rounded-xl bg-[var(--purple)]
          GestureDetector(
            onTap: () => _handlePlayOffline(file),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12), // py-3
              decoration: BoxDecoration(
                color: AppColors.purple,
                borderRadius: BorderRadius.circular(12), // rounded-xl
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.play_arrow,
                    size: 20, // w-5 h-5
                    color: Colors.white,
                  ),
                  const SizedBox(width: 8), // gap-2
                  Text(
                    context.l10n.watchOffline,
                    style: AppTextStyles.bodyMedium(
                      color: Colors.white,
                    ).copyWith(fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleDownload(
      Map<String, dynamic> file, String resourceId) async {
    if (resourceId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.l10n.fileIdNotAvailable,
              style: GoogleFonts.cairo(),
            ),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
      return;
    }

    try {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  context.l10n.gettingDownloadLink,
                  style: GoogleFonts.cairo(),
                ),
              ],
            ),
            backgroundColor: AppColors.purple,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 30),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }

      final response = await DownloadsService.instance.downloadFile(resourceId);
      final downloadUrl = response['download_url']?.toString();

      if (downloadUrl == null || downloadUrl.isEmpty) {
        throw Exception(context.l10n.downloadLinkNotAvailable);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.l10n.downloadLinkObtained,
              style: GoogleFonts.cairo(),
            ),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }

      // TODO: Implement actual file download using the download_url
      // This would require downloading the file and saving it locally
      if (kDebugMode) {
        print('📥 Download URL: $downloadUrl');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error downloading file: $e');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.l10n.errorDownloading(
                  e.toString().replaceFirst('Exception: ', '')),
              style: GoogleFonts.cairo(),
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    }
  }

  Future<void> _handleDelete(Map<String, dynamic> file, String fileId) async {
    if (fileId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.l10n.fileIdNotAvailable,
              style: GoogleFonts.cairo(),
            ),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
      return;
    }

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          context.l10n.deleteFile,
          style: GoogleFonts.cairo(),
        ),
        content: Text(
          context.l10n.confirmDeleteFile,
          style: GoogleFonts.cairo(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              context.l10n.cancel,
              style: GoogleFonts.cairo(),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              context.l10n.delete,
              style: GoogleFonts.cairo(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final response = await DownloadsService.instance.deleteDownload(fileId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              response['message']?.toString() ?? context.l10n.fileDeleted,
              style: GoogleFonts.cairo(),
            ),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }

      // Refresh the list
      _loadDownloads();
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error deleting file: $e');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.l10n
                  .errorDeleting(e.toString().replaceFirst('Exception: ', '')),
              style: GoogleFonts.cairo(),
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    }
  }

  void _handlePlayOffline(Map<String, dynamic> file) {
    final courseId =
        file['course']?['id']?.toString() ?? file['course_id']?.toString();

    if (courseId != null && courseId.isNotEmpty) {
      // TODO: Navigate to offline course viewer
      if (kDebugMode) {
        print('📱 Play offline course: $courseId');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.l10n.courseWillOpenOffline,
              style: GoogleFonts.cairo(),
            ),
            backgroundColor: AppColors.purple,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.l10n.courseIdNotAvailable,
              style: GoogleFonts.cairo(),
            ),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    }
  }

  Widget _buildLoadingState() {
    return Skeletonizer(
      enabled: true,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              height: 150,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
              ),
            ),
            ...List.generate(
                3,
                (index) => Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      height: 200,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                    )),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 80),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 96, // w-24
            height: 96, // h-24
            decoration: const BoxDecoration(
              color: AppColors.lavenderLight,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.download,
              size: 48, // w-12 h-12
              color: AppColors.purple,
            ),
          ),
          const SizedBox(height: 16), // mb-4
          Text(
            context.l10n.noDownloads,
            style: AppTextStyles.h4(
              color: AppColors.foreground,
            ),
          ),
          const SizedBox(height: 8), // mb-2
          Text(
            context.l10n.downloadCoursesToWatchOffline,
            style: AppTextStyles.bodyMedium(
              color: AppColors.mutedForeground,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
