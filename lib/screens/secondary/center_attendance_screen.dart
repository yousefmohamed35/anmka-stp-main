import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../core/design/app_colors.dart';
import '../../core/design/app_radius.dart';
import '../../services/qr_code_service.dart';
import '../../services/profile_service.dart';
import '../../services/teacher_dashboard_service.dart';
import '../../l10n/app_localizations.dart';

/// Center Attendance Screen - Display QR Code and Student Stats
class CenterAttendanceScreen extends StatefulWidget {
  const CenterAttendanceScreen({super.key});

  @override
  State<CenterAttendanceScreen> createState() => _CenterAttendanceScreenState();
}

class _CenterAttendanceScreenState extends State<CenterAttendanceScreen> {
  bool _isLoading = true;
  bool _isLoadingProfile = true;
  String? _qrCode;
  String? _error;
  Map<String, dynamic>? _profile;
  Map<String, dynamic>? _statistics;
  List<Map<String, dynamic>> _attendanceRecords = [];
  bool _loadingAttendance = true;
  String? _attendanceLoadError;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    await Future.wait([
      _loadQrCode(),
      _loadProfile(),
      _loadAttendanceHistory(),
    ]);
  }

  Future<void> _loadAttendanceHistory() async {
    if (mounted) {
      setState(() {
        _loadingAttendance = true;
        _attendanceLoadError = null;
      });
    }
    try {
      final data = await TeacherDashboardService.instance.getMyAttendance(
        limit: 50,
      );
      final raw = data['data'];
      final list = raw is List ? raw : const [];
      final records = <Map<String, dynamic>>[];
      for (final item in list) {
        if (item is Map) {
          records.add(Map<String, dynamic>.from(item));
        }
      }
      if (mounted) {
        setState(() {
          _attendanceRecords = records;
          _loadingAttendance = false;
        });
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error loading attendance history: $e');
      }
      if (mounted) {
        setState(() {
          _attendanceLoadError = e.toString().replaceFirst('Exception: ', '');
          _loadingAttendance = false;
        });
      }
    }
  }

  String _attendanceDateLine(Map<String, dynamic> m) {
    final raw = m['date'] ??
        m['createdAt'] ??
        m['attended_at'] ??
        m['checked_in_at'] ??
        '—';
    final s = raw.toString();
    if (s.length >= 10 && s.contains('-')) {
      return s.substring(0, 10);
    }
    return s;
  }

  String? _attendanceSubtitle(Map<String, dynamic> m) {
    final course = m['course'];
    String? courseTitle;
    if (course is Map) {
      courseTitle = course['title']?.toString();
    }
    courseTitle ??=
        m['course_title']?.toString() ?? m['courseTitle']?.toString();
    final session = m['session_title']?.toString() ??
        m['sessionTitle']?.toString() ??
        m['session']?.toString();
    final parts = <String>[];
    if (courseTitle != null && courseTitle.isNotEmpty) {
      parts.add(courseTitle);
    }
    if (session != null && session.isNotEmpty) parts.add(session);
    if (parts.isEmpty) return null;
    return parts.join(' · ');
  }

  Future<void> _loadQrCode() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final qrCode = await QrCodeService.instance.getMyQrCode();
      if (kDebugMode) {
        print(
            '✅ QR code loaded: ${qrCode.length > 20 ? qrCode.substring(0, 20) : qrCode}...');
      }
      setState(() {
        _qrCode = qrCode;
        _isLoading = false;
      });
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error loading QR code: $e');
      }
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  Future<void> _loadProfile() async {
    setState(() {
      _isLoadingProfile = true;
    });

    try {
      final profile = await ProfileService.instance.getProfile();
      if (kDebugMode) {
        print('✅ Profile loaded: ${profile['name']}');
      }
      setState(() {
        _profile = profile;
        _statistics = profile['statistics'] as Map<String, dynamic>?;
        _isLoadingProfile = false;
      });
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error loading profile: $e');
      }
      setState(() {
        _isLoadingProfile = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
    );

    final l10n = AppLocalizations.of(context)!;

    final enrolledCourses = _statistics?['enrolled_courses'] ?? 0;
    final certificates = _statistics?['certificates_earned'] ?? 0;
    final totalHours = _statistics?['total_learning_hours'] ?? 0;

    return Scaffold(
      backgroundColor: AppColors.beige,
      body: SafeArea(
        child: Column(
          children: [
            // Header with Profile and Stats
            _buildHeader(
                context, l10n, enrolledCourses, certificates, totalHours),

            // Content
            Expanded(
              child: _isLoading || _isLoadingProfile
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 16),
                          Text(
                            l10n.loadingQrCode,
                            style: GoogleFonts.cairo(
                              fontSize: 14,
                              color: AppColors.mutedForeground,
                            ),
                          ),
                        ],
                      ),
                    )
                  : _error != null
                      ? _buildErrorState(context, l10n)
                      : _buildContent(context, l10n, enrolledCourses,
                          certificates, totalHours),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    AppLocalizations l10n,
    int enrolledCourses,
    int certificates,
    int totalHours,
  ) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF7C3AED), Color(0xFF5B21B6)],
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(AppRadius.largeCard),
          bottomRight: Radius.circular(AppRadius.largeCard),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.purple.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          children: [
            // Top Row with Back and Refresh
            Row(
              children: [
                GestureDetector(
                  onTap: () => context.pop(),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l10n.centerAttendance,
                    style: GoogleFonts.cairo(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: _loadData,
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.refresh_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Profile Section
            Row(
              children: [
                // Avatar
                Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withOpacity(0.4),
                      width: 3,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: _profile?['avatar'] != null
                        ? Image.network(
                            _profile!['avatar']?.toString() ?? '',
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: Colors.white,
                              child: const Icon(
                                Icons.person,
                                size: 35,
                                color: AppColors.purple,
                              ),
                            ),
                          )
                        : Container(
                            color: Colors.white,
                            child: const Icon(
                              Icons.person,
                              size: 35,
                              color: AppColors.purple,
                            ),
                          ),
                  ),
                ),

                const SizedBox(width: 16),

                // Name and Email
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _profile?['name']?.toString() ?? l10n.user,
                        style: GoogleFonts.cairo(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _profile?['email']?.toString() ?? '',
                        style: GoogleFonts.cairo(
                          fontSize: 13,
                          color: Colors.white.withOpacity(0.8),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Stats Row
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStat(
                    '$enrolledCourses',
                    l10n.course,
                    Icons.play_circle_fill_rounded,
                  ),
                  Container(
                    width: 1,
                    height: 25,
                    color: Colors.white.withOpacity(0.3),
                  ),
                  _buildStat(
                    '$certificates',
                    l10n.certificates,
                    Icons.emoji_events_rounded,
                  ),
                  Container(
                    width: 1,
                    height: 25,
                    color: Colors.white.withOpacity(0.3),
                  ),
                  _buildStat(
                    '$totalHours',
                    l10n.hour,
                    Icons.access_time_filled_rounded,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStat(String value, String label, IconData icon) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: Colors.white.withOpacity(0.9)),
            const SizedBox(width: 4),
            Text(
              value,
              style: GoogleFonts.cairo(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: GoogleFonts.cairo(
            fontSize: 11,
            color: Colors.white.withOpacity(0.8),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorState(BuildContext context, AppLocalizations l10n) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.red[50],
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.error_outline_rounded,
                size: 40,
                color: Colors.red[600],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              l10n.errorLoadingQrCode,
              style: GoogleFonts.cairo(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.foreground,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? l10n.unknownError,
              style: GoogleFonts.cairo(
                fontSize: 14,
                color: AppColors.mutedForeground,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loadData,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.purple,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: Text(
                l10n.retry,
                style: GoogleFonts.cairo(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    AppLocalizations l10n,
    int enrolledCourses,
    int certificates,
    int totalHours,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      physics: const BouncingScrollPhysics(),
      child: Column(
        children: [
          // Info Card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                const Icon(
                  Icons.qr_code_scanner_rounded,
                  size: 48,
                  color: AppColors.purple,
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.centerAttendanceDescription,
                  style: GoogleFonts.cairo(
                    fontSize: 14,
                    color: AppColors.mutedForeground,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // QR Code Card
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              children: [
                // QR Code
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppColors.purple.withOpacity(0.2),
                      width: 2,
                    ),
                  ),
                  child: QrImageView(
                    data: _qrCode ?? '',
                    version: QrVersions.auto,
                    size: 250,
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.purple,
                    errorCorrectionLevel: QrErrorCorrectLevel.H,
                  ),
                ),

                const SizedBox(height: 24),

                // Instructions
                Text(
                  l10n.scanQrCodeInstruction,
                  style: GoogleFonts.cairo(
                    fontSize: 13,
                    color: AppColors.mutedForeground,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          _buildAttendanceHistoryCard(context, l10n),

          const SizedBox(height: 24),

          // Refresh Button
          OutlinedButton.icon(
            onPressed: _loadQrCode,
            icon: const Icon(Icons.refresh_rounded, size: 20),
            label: Text(
              l10n.refreshQrCode,
              style: GoogleFonts.cairo(
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.purple,
              side: const BorderSide(color: AppColors.purple, width: 1.5),
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 16,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttendanceHistoryCard(
    BuildContext context,
    AppLocalizations l10n,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.history_rounded,
                color: AppColors.purple,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  l10n.attendanceHistory,
                  style: GoogleFonts.cairo(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: AppColors.foreground,
                  ),
                ),
              ),
              if (!_loadingAttendance && _attendanceLoadError == null)
                IconButton(
                  tooltip: l10n.retry,
                  onPressed: _loadAttendanceHistory,
                  icon: Icon(
                    Icons.refresh_rounded,
                    color: AppColors.purple.withOpacity(0.85),
                    size: 22,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (_loadingAttendance)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_attendanceLoadError != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.errorLoadingAttendanceHistory,
                  style: GoogleFonts.cairo(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.foreground,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _attendanceLoadError!,
                  style: GoogleFonts.cairo(
                    fontSize: 13,
                    color: AppColors.mutedForeground,
                  ),
                ),
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: _loadAttendanceHistory,
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                  label: Text(
                    l10n.retry,
                    style: GoogleFonts.cairo(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            )
          else if (_attendanceRecords.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  l10n.noAttendanceRecords,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.cairo(
                    fontSize: 14,
                    color: AppColors.mutedForeground,
                  ),
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _attendanceRecords.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final m = _attendanceRecords[i];
                final subtitle = _attendanceSubtitle(m);
                final type =
                    m['type']?.toString() ?? m['status']?.toString() ?? '';
                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.purple.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppColors.purple.withOpacity(0.12),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.check_circle_rounded,
                        color: AppColors.purple,
                        size: 22,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _attendanceDateLine(m),
                              style: GoogleFonts.cairo(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppColors.foreground,
                              ),
                            ),
                            if (subtitle != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                subtitle,
                                style: GoogleFonts.cairo(
                                  fontSize: 12,
                                  color: AppColors.mutedForeground,
                                ),
                              ),
                            ],
                            if (type.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                type,
                                style: GoogleFonts.cairo(
                                  fontSize: 11,
                                  color: AppColors.mutedForeground,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
