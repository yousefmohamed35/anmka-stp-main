import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:skeletonizer/skeletonizer.dart';
import '../../core/design/app_colors.dart';
import '../../core/design/app_radius.dart';
import '../../core/navigation/route_names.dart';
import '../../data/sample_teachers.dart';
import '../../l10n/app_localizations.dart';
import '../../services/teachers_service.dart';

class TeachersScreen extends StatefulWidget {
  const TeachersScreen({super.key, this.teachers});

  final List<Map<String, dynamic>>? teachers;

  @override
  State<TeachersScreen> createState() => _TeachersScreenState();
}

class _TeachersScreenState extends State<TeachersScreen> {
  bool _isLoading = false;
  String? _errorMessage;
  List<Map<String, dynamic>> _teachers = [];
  int _currentPage = 1;
  bool _hasMore = true;
  bool _isLoadingMore = false;

  @override
  void initState() {
    super.initState();
    // If teachers are passed, use them; otherwise load from API
    if (widget.teachers != null && widget.teachers!.isNotEmpty) {
      _teachers = List<Map<String, dynamic>>.from(widget.teachers!);
    } else {
      _loadTeachers();
    }
  }

  Future<void> _loadTeachers({bool loadMore = false}) async {
    if (loadMore) {
      if (!_hasMore || _isLoadingMore) return;
      setState(() => _isLoadingMore = true);
    } else {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
        _currentPage = 1;
        _hasMore = true;
      });
    }

    try {
      final response = await TeachersService.instance.getTeachers(
        page: _currentPage,
        perPage: 20,
        sort: 'rating',
      );

      final data = response['data'];
      List<Map<String, dynamic>> newTeachers = [];

      if (data is Map<String, dynamic> && data['teachers'] != null) {
        newTeachers = List<Map<String, dynamic>>.from(data['teachers']);
        final meta = data['meta'] as Map<String, dynamic>?;
        if (meta != null) {
          _hasMore = (meta['current_page'] as int? ?? 1) <
              (meta['last_page'] as int? ?? 1);
        }
      } else if (data is List) {
        newTeachers = List<Map<String, dynamic>>.from(data);
        _hasMore = false; // No pagination info, assume no more
      }

      setState(() {
        if (loadMore) {
          _teachers.addAll(newTeachers);
          _currentPage++;
        } else {
          _teachers = newTeachers;
          _currentPage = 2; // Next page for load more
        }
        _isLoading = false;
        _isLoadingMore = false;
        _errorMessage = null;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _isLoadingMore = false;
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
        // Fallback to sample teachers if API fails and no data loaded
        if (_teachers.isEmpty) {
          _teachers = List<Map<String, dynamic>>.from(kSampleTeachers);
        }
      });
    }
  }

  List<Map<String, dynamic>> get _data => _teachers;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColors.beige,
      appBar: AppBar(
        title: Text(
          l10n.allTeachers,
          style: GoogleFonts.cairo(fontWeight: FontWeight.w700),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: AppColors.foreground,
        elevation: 0.5,
      ),
      body: _isLoading && _teachers.isEmpty
          ? _buildTeachersSkeleton()
          : _errorMessage != null && _teachers.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _errorMessage!,
                        style: GoogleFonts.cairo(color: Colors.red),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () => _loadTeachers(),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : NotificationListener<ScrollNotification>(
                  onNotification: (ScrollNotification scrollInfo) {
                    if (scrollInfo.metrics.pixels ==
                        scrollInfo.metrics.maxScrollExtent) {
                      // User scrolled to bottom, load more
                      _loadTeachers(loadMore: true);
                    }
                    return false;
                  },
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _data.length + (_hasMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == _data.length) {
                        // Load more indicator
                        if (_isLoadingMore) {
                          return const Padding(
                            padding: EdgeInsets.all(16.0),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        return const SizedBox.shrink();
                      }
                      final teacher = _data[index];
                      return GestureDetector(
                        onTap: () => context.push(
                          RouteNames.teacherDetails,
                          extra: teacher,
                        ),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(AppRadius.card),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.04),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(18),
                                child: Image.network(
                                  teacher['avatar']?.toString() ?? '',
                                  width: 70,
                                  height: 70,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(
                                    width: 70,
                                    height: 70,
                                    color: AppColors.purple.withOpacity(0.1),
                                    child: const Icon(Icons.person,
                                        color: AppColors.purple),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      teacher['name']?.toString() ?? '',
                                      style: GoogleFonts.cairo(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.foreground,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      teacher['title']?.toString() ?? '',
                                      style: GoogleFonts.cairo(
                                        fontSize: 12,
                                        color: AppColors.mutedForeground,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        const Icon(Icons.star_rounded,
                                            size: 16, color: Colors.amber),
                                        const SizedBox(width: 4),
                                        Text(
                                          (teacher['rating'] ?? 0).toString(),
                                          style: GoogleFonts.cairo(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        const Icon(Icons.people_alt_rounded,
                                            size: 16, color: AppColors.purple),
                                        const SizedBox(width: 4),
                                        Text(
                                          l10n.studentsCount(
                                              (teacher['students'] as int?) ??
                                                  0),
                                          style: GoogleFonts.cairo(
                                            fontSize: 12,
                                            color: AppColors.mutedForeground,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: AppColors.purple.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  l10n.coursesCount(
                                    (teacher['courses_count'] as int?) ??
                                        (teacher['courses'] as List?)?.length ??
                                        0,
                                  ),
                                  style: GoogleFonts.cairo(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.purple,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }

  Widget _buildTeachersSkeleton() {
    return Skeletonizer(
      enabled: true,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: 5,
        itemBuilder: (context, index) {
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppRadius.card),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 14,
                        width: 120,
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        height: 12,
                        width: 80,
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Container(
                            height: 16,
                            width: 30,
                            decoration: BoxDecoration(
                              color: Colors.grey[300],
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Container(
                            height: 16,
                            width: 50,
                            decoration: BoxDecoration(
                              color: Colors.grey[300],
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 60,
                  height: 28,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
