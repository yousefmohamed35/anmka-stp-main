import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:pod_player/pod_player.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../../core/design/app_colors.dart';
import '../../core/navigation/route_names.dart';
import '../../services/courses_service.dart';
import '../../services/token_storage_service.dart';
import '../../services/video_download_service.dart';
import '../../services/youtube_video_service.dart';
import '../../utils/lesson_access.dart';

/// Lesson Viewer Screen - Modern & Eye-Friendly Design
class LessonViewerScreen extends StatefulWidget {
  final Map<String, dynamic>? lesson;
  final String? courseId;

  /// Flat course lesson list (same order as course details) for prev/next.
  final List<Map<String, dynamic>>? allLessons;

  /// Index of [lesson] inside [allLessons], if known.
  final int? lessonIndexInCourse;

  const LessonViewerScreen({
    super.key,
    this.lesson,
    this.courseId,
    this.allLessons,
    this.lessonIndexInCourse,
  });

  @override
  State<LessonViewerScreen> createState() => _LessonViewerScreenState();
}

class _LessonViewerScreenState extends State<LessonViewerScreen> {
  /// Working copy so we can switch lessons without a new route.
  Map<String, dynamic>? _lessonState;
  List<Map<String, dynamic>>? _allLessons;
  int? _lessonIndexInCourse;

  Map<String, dynamic>? get _lesson => _lessonState;

  PodPlayerController? _controller;
  WebViewController? _webViewController;
  bool _isVideoLoading = true;
  bool _isLoadingContent = true;
  bool _useWebViewFallback = false;
  Map<String, dynamic>? _lessonContent;
  File? _tempVideoFile;
  final VideoDownloadService _downloadService = VideoDownloadService();
  bool _isDownloading = false;
  int _downloadProgress = 0;
  bool _isDownloaded = false;
  String? _lastYoutubeUrl;
  Map<String, String> _youtubeQualityUrls = {};

  /// API `video_qualities` (see mobile lesson payload: auto | 1080p | 720p | …).
  Map<String, String> _serverQualityUrls = {};
  List<String> _serverQualityOrder = [];
  String? _selectedQuality;
  bool _isLoadingQualities = false;

  String _youtubeQualityHeightLabel(String heightKey) {
    final h = int.tryParse(heightKey) ?? 0;
    switch (h) {
      case 1080:
        return '1080p FHD';
      case 720:
        return '720p HD';
      case 480:
        return '480p';
      case 360:
        return '360p';
      case 240:
        return '240p';
      case 144:
        return '144p';
      default:
        return '${h}p';
    }
  }

  String _qualityPickerButtonLabel() {
    if (_selectedQuality != null) {
      if (_serverQualityUrls.containsKey(_selectedQuality)) {
        return _serverQualityDisplayLabel(_selectedQuality!);
      }
      return _youtubeQualityHeightLabel(_selectedQuality!);
    }
    if (_serverQualityUrls.isNotEmpty) {
      final order = _serverQualityOrder
          .where((k) => _serverQualityUrls.containsKey(k))
          .toList();
      final keys = order.isNotEmpty ? order : _serverQualityUrls.keys.toList();
      return _serverQualityDisplayLabel(keys.first);
    }
    if (_youtubeQualityUrls.isNotEmpty) {
      final heights = _youtubeQualityUrls.keys.map(int.parse).toList()
        ..sort((a, b) => b.compareTo(a));
      return _youtubeQualityHeightLabel(heights.first.toString());
    }
    return 'الجودة';
  }

  String _serverQualityDisplayLabel(String key) {
    switch (key) {
      case 'auto':
        return 'تلقائي';
      case '1080p':
        return '1080p FHD';
      case '720p':
        return '720p HD';
      case '480p':
        return '480p';
      case '360p':
        return '360p';
      default:
        return key;
    }
  }

  void _ingestVideoQualitiesMap(
    Map<String, dynamic> root,
    Map<String, String> into,
  ) {
    void merge(dynamic raw) {
      if (raw is! Map) return;
      for (final e in raw.entries) {
        final u = _cleanVideoUrl(e.value?.toString());
        if (u != null) into[e.key.toString()] = u;
      }
    }

    merge(root['video_qualities']);
    merge(root['videoQualities']);
    final vid = root['video'];
    if (vid is Map) {
      final nested = Map<String, dynamic>.from(vid);
      merge(nested['video_qualities']);
      merge(nested['videoQualities']);
    }
  }

  String? _readNestedDefaultQuality(Map<String, dynamic> m) {
    String? d = m['default_quality']?.toString();
    d ??= m['defaultQuality']?.toString();
    if (d != null && d.isNotEmpty) return d;
    final v = m['video'];
    if (v is Map) {
      final vm = Map<String, dynamic>.from(v);
      return vm['default_quality']?.toString() ??
          vm['defaultQuality']?.toString();
    }
    return null;
  }

  List<String>? _readNestedQualityOptions(Map<String, dynamic> m) {
    dynamic qo = m['quality_options'];
    if (qo is! List || qo.isEmpty) qo = m['qualityOptions'];
    if (qo is! List || qo.isEmpty) {
      final v = m['video'];
      if (v is Map) {
        final vm = Map<String, dynamic>.from(v);
        qo = vm['quality_options'];
        if (qo is! List || qo.isEmpty) qo = vm['qualityOptions'];
      }
    }
    if (qo is! List) return null;
    return qo.map((e) => e.toString()).toList();
  }

  bool _isApiStreamUrl(String url) {
    try {
      final p = Uri.parse(url).path;
      return p.contains('/videos/') && p.contains('/stream');
    } catch (_) {
      return false;
    }
  }

  ({
    Map<String, String> qualities,
    List<String> orderedOptions,
    String? defaultQuality,
  }) _mergeApiVideoQualities(
    Map<String, dynamic> lesson,
    Map<String, dynamic>? content,
  ) {
    final qualities = <String, String>{};
    _ingestVideoQualitiesMap(lesson, qualities);
    if (content != null) {
      _ingestVideoQualitiesMap(content, qualities);
    }

    final defaultQuality = _readNestedDefaultQuality(content ?? {}) ??
        _readNestedDefaultQuality(lesson);

    List<String> ordered = [];
    final fromContent =
        content != null ? _readNestedQualityOptions(content) : null;
    final fromLesson = _readNestedQualityOptions(lesson);
    final qo = fromContent ?? fromLesson;
    if (qo != null) {
      for (final k in qo) {
        if (qualities.containsKey(k)) ordered.add(k);
      }
    }
    if (ordered.isEmpty) {
      const preferred = ['auto', '1080p', '720p', '480p', '360p'];
      for (final k in preferred) {
        if (qualities.containsKey(k)) ordered.add(k);
      }
      for (final k in qualities.keys) {
        if (!ordered.contains(k)) ordered.add(k);
      }
    }

    // `quality=auto` is often HLS (.m3u8); ExoPlayer via video_player can fail while MP4 variants work.
    if (qualities.containsKey('auto') && qualities.length > 1) {
      const fixed = {'1080p', '720p', '480p', '360p'};
      if (qualities.keys.any(fixed.contains)) {
        qualities.remove('auto');
        ordered.remove('auto');
      }
    }

    var resolvedDefault = defaultQuality;
    if (resolvedDefault != null && !qualities.containsKey(resolvedDefault)) {
      resolvedDefault = null;
    }

    return (
      qualities: qualities,
      orderedOptions: ordered,
      defaultQuality: resolvedDefault,
    );
  }

  bool _urlsEqualIgnoringAuth(String a, String b) {
    String norm(String u) {
      final uri = Uri.parse(u);
      final q = Map<String, String>.from(uri.queryParameters)..remove('token');
      final query = Uri(queryParameters: q).query;
      return '${uri.scheme}://${uri.host}${uri.path}${query.isNotEmpty ? '?$query' : ''}';
    }

    try {
      return norm(a) == norm(b);
    } catch (_) {
      return false;
    }
  }

  String? _findQualityKeyForUrl(Map<String, String> qualities, String url) {
    for (final e in qualities.entries) {
      if (_urlsEqualIgnoringAuth(e.value, url)) return e.key;
    }
    return null;
  }

  String? _pickInitialDirectPlayUrl(
    String? lessonVideoUrl,
    ({
      Map<String, String> qualities,
      List<String> orderedOptions,
      String? defaultQuality,
    }) bundle,
  ) {
    final q = bundle.qualities;
    if (q.isEmpty) return _cleanVideoUrl(lessonVideoUrl);

    final def = bundle.defaultQuality;
    if (def != null && q.containsKey(def)) {
      return q[def];
    }

    final cleaned = _cleanVideoUrl(lessonVideoUrl);
    if (cleaned != null) {
      for (final e in q.entries) {
        if (_urlsEqualIgnoringAuth(cleaned, e.value)) return e.value;
      }
      final allStreamVariants = q.values.every((u) => _isApiStreamUrl(u));
      final cleanedIsStream = _isApiStreamUrl(cleaned);
      if (q.isNotEmpty && allStreamVariants && !cleanedIsStream) {
        final d = bundle.defaultQuality;
        if (d != null && q.containsKey(d)) return q[d];
        for (final k in bundle.orderedOptions) {
          final u = q[k];
          if (u != null) return u;
        }
        for (final k in ['720p', '1080p', '480p', '360p', 'auto']) {
          final u = q[k];
          if (u != null) return u;
        }
        return q.values.first;
      }
      return cleaned;
    }

    for (final k in bundle.orderedOptions) {
      final u = q[k];
      if (u != null) return u;
    }
    for (final k in ['720p', '1080p', '480p', '360p', 'auto']) {
      final u = q[k];
      if (u != null) return u;
    }
    return q.values.first;
  }

  Future<String> _videoUrlWithAccessToken(String videoUrl) async {
    final token = await TokenStorageService.instance.getAccessToken();
    if (token == null || token.isEmpty) return videoUrl;
    final uri = Uri.parse(videoUrl);
    return uri.replace(queryParameters: {
      ...uri.queryParameters,
      'token': token,
    }).toString();
  }

  /// Many LMS streams require `Authorization` on Range requests; query `token` alone can 403.
  Future<Map<String, String>> _videoBearerHeaders() async {
    final token = await TokenStorageService.instance.getAccessToken();
    if (token == null || token.isEmpty) return <String, String>{};
    return {'Authorization': 'Bearer $token'};
  }

  Future<void> _initPodNetworkFromUrl(
    String videoUrl, {
    Duration seekTo = Duration.zero,
  }) async {
    final withToken = await _videoUrlWithAccessToken(videoUrl);
    final headers = await _videoBearerHeaders();
    _controller?.dispose();
    _controller = null;
    _controller = PodPlayerController(
      playVideoFrom: PlayVideoFrom.network(
        withToken,
        httpHeaders: headers,
      ),
      podPlayerConfig: const PodPlayerConfig(
        autoPlay: false,
        isLooping: false,
      ),
    );
    await _controller!.initialise();
    if (seekTo > Duration.zero) {
      await _controller!.videoSeekTo(seekTo);
    }
  }

  Future<void> _fetchYoutubeQualities(String youtubeUrl) async {
    YoutubeExplode? yt;
    try {
      if (!mounted) return;
      setState(() {
        _isLoadingQualities = true;
        _youtubeQualityUrls = {};
        _serverQualityUrls = {};
        _serverQualityOrder = [];
      });

      yt = YoutubeExplode();
      final video = await yt.videos.get(youtubeUrl);
      final manifest = await yt.videos.streamsClient.getManifest(video.id);
      final muxedList = List<MuxedStreamInfo>.from(manifest.muxed);

      muxedList.sort((a, b) {
        final h = b.videoResolution.height.compareTo(a.videoResolution.height);
        if (h != 0) return h;
        return b.bitrate.bitsPerSecond.compareTo(a.bitrate.bitsPerSecond);
      });

      final seenHeights = <int>{};
      final urlMap = <String, String>{};
      for (final s in muxedList) {
        final height = s.videoResolution.height;
        if (seenHeights.contains(height)) continue;
        seenHeights.add(height);
        urlMap[height.toString()] = s.url.toString();
      }

      if (urlMap.isEmpty) {
        if (kDebugMode) {
          print('⚠️ No muxed streams for YouTube video; using pod fallback.');
        }
        if (!mounted) return;
        setState(() {
          _isLoadingQualities = false;
        });
        await _playYoutubeDefault(youtubeUrl);
        return;
      }

      if (!mounted) return;
      setState(() {
        _isLoadingQualities = false;
        _youtubeQualityUrls = urlMap;
      });

      final sortedKeys = urlMap.keys.map(int.parse).toList()
        ..sort((a, b) => b.compareTo(a));
      final bestKey = sortedKeys.first.toString();
      await _switchToQuality(bestKey);
    } catch (e, st) {
      if (kDebugMode) {
        print('❌ _fetchYoutubeQualities failed: $e');
        print(st);
      }
      if (!mounted) return;
      setState(() {
        _isLoadingQualities = false;
      });
      await _playYoutubeDefault(youtubeUrl);
    } finally {
      yt?.close();
    }
  }

  Future<void> _switchToServerQuality(String qualityKey) async {
    final url = _serverQualityUrls[qualityKey];
    if (url == null || url.isEmpty) return;

    final savedPosition =
        _controller?.videoPlayerValue?.position ?? Duration.zero;
    final revertToKey = _selectedQuality;

    if (!mounted) return;
    setState(() {
      _isVideoLoading = true;
      _selectedQuality = qualityKey;
    });

    try {
      await _initPodNetworkFromUrl(url, seekTo: savedPosition);
      if (!mounted) return;
      setState(() {
        _isVideoLoading = false;
        _useWebViewFallback = false;
      });
    } catch (e, st) {
      if (kDebugMode) {
        print('❌ _switchToServerQuality failed: $e');
        print(st);
      }
      if (!mounted) return;

      if (revertToKey != null &&
          revertToKey != qualityKey &&
          _serverQualityUrls.containsKey(revertToKey)) {
        final revertUrl = _serverQualityUrls[revertToKey]!;
        setState(() {
          _selectedQuality = revertToKey;
        });
        try {
          await _initPodNetworkFromUrl(revertUrl, seekTo: savedPosition);
          if (mounted) {
            setState(() {
              _isVideoLoading = false;
              _useWebViewFallback = false;
            });
          }
          return;
        } catch (e2, st2) {
          if (kDebugMode) {
            print('❌ Revert to previous quality failed: $e2');
            print(st2);
          }
        }
      }

      if (mounted) {
        setState(() {
          _isVideoLoading = false;
        });
      }
    }
  }

  Future<void> _switchToQuality(String qualityKey) async {
    if (_serverQualityUrls.containsKey(qualityKey)) {
      await _switchToServerQuality(qualityKey);
      return;
    }

    final url = _youtubeQualityUrls[qualityKey];
    if (url == null || url.isEmpty) return;

    final savedPosition =
        _controller?.videoPlayerValue?.position ?? Duration.zero;

    _controller?.dispose();
    _controller = null;

    if (!mounted) return;
    setState(() {
      _isVideoLoading = true;
      _selectedQuality = qualityKey;
    });

    try {
      _controller = PodPlayerController(
        playVideoFrom: PlayVideoFrom.network(url),
        podPlayerConfig: const PodPlayerConfig(
          autoPlay: false,
          isLooping: false,
        ),
      );
      await _controller!.initialise();
      if (savedPosition > Duration.zero) {
        await _controller!.videoSeekTo(savedPosition);
      }
      if (!mounted) return;
      setState(() {
        _isVideoLoading = false;
      });
    } catch (e, st) {
      if (kDebugMode) {
        print('❌ _switchToQuality failed: $e');
        print(st);
      }
      if (!mounted) return;
      setState(() {
        _isVideoLoading = false;
      });
      final fallbackUrl = _lastYoutubeUrl;
      if (fallbackUrl != null && fallbackUrl.isNotEmpty) {
        await _playYoutubeDefault(fallbackUrl);
      }
    }
  }

  Widget _buildQualityPicker() {
    final heights = _youtubeQualityUrls.keys.map(int.parse).toList()
      ..sort((a, b) => b.compareTo(a));

    final selected = _selectedQuality;
    final borderAccent = selected != null
        ? AppColors.purple
        : Colors.white.withValues(alpha: 0.7);

    return PopupMenuButton<String>(
      tooltip: 'الجودة',
      color: const Color(0xFF1A1A2E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: (q) => _switchToQuality(q),
      itemBuilder: (context) {
        return heights.map((h) {
          final q = h.toString();
          final isSelected = selected == q;
          return PopupMenuItem<String>(
            value: q,
            child: Row(
              children: [
                Icon(
                  isSelected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: isSelected ? AppColors.purple : Colors.white54,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _youtubeQualityHeightLabel(q),
                    style: GoogleFonts.cairo(
                      color: Colors.white,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.normal,
                      fontSize: 14,
                    ),
                  ),
                ),
                if (h == 720 || h == 1080)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.purple.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'HD',
                      style: GoogleFonts.cairo(
                        color: AppColors.purple,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          );
        }).toList();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: borderAccent, width: 1.2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.hd_rounded,
              color: selected != null ? AppColors.purple : Colors.white,
              size: 22,
            ),
            const SizedBox(width: 6),
            Text(
              _qualityPickerButtonLabel(),
              style: GoogleFonts.cairo(
                color: selected != null ? AppColors.purple : Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Icon(Icons.arrow_drop_down, color: Colors.white70),
          ],
        ),
      ),
    );
  }

  Widget _buildServerQualityPicker() {
    final keys = _serverQualityOrder
        .where((k) => _serverQualityUrls.containsKey(k))
        .toList();
    final ordered = keys.isNotEmpty ? keys : _serverQualityUrls.keys.toList();

    final selected = _selectedQuality;
    final borderAccent = selected != null
        ? AppColors.purple
        : Colors.white.withValues(alpha: 0.7);

    return PopupMenuButton<String>(
      tooltip: 'الجودة',
      color: const Color(0xFF1A1A2E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: (q) => _switchToQuality(q),
      itemBuilder: (context) {
        return ordered.map((k) {
          final isSelected = selected == k;
          final showHd = k == '720p' || k == '1080p';
          return PopupMenuItem<String>(
            value: k,
            child: Row(
              children: [
                Icon(
                  isSelected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: isSelected ? AppColors.purple : Colors.white54,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _serverQualityDisplayLabel(k),
                    style: GoogleFonts.cairo(
                      color: Colors.white,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.normal,
                      fontSize: 14,
                    ),
                  ),
                ),
                if (showHd)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.purple.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'HD',
                      style: GoogleFonts.cairo(
                        color: AppColors.purple,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          );
        }).toList();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: borderAccent, width: 1.2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.hd_rounded,
              color: selected != null ? AppColors.purple : Colors.white,
              size: 22,
            ),
            const SizedBox(width: 6),
            Text(
              _qualityPickerButtonLabel(),
              style: GoogleFonts.cairo(
                color: selected != null ? AppColors.purple : Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Icon(Icons.arrow_drop_down, color: Colors.white70),
          ],
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    final w = widget.lesson;
    _lessonState = w == null ? null : Map<String, dynamic>.from(w);
    _allLessons = widget.allLessons;
    _lessonIndexInCourse = widget.lessonIndexInCourse ??
        (_allLessons != null && _lessonState != null
            ? indexOfLessonInList(_allLessons!, _lessonState!)
            : null);
    _initializeDownloadService();
    _loadLessonContent().then((_) {
      // Initialize video after content is loaded (or failed)
      // This ensures we can use video data from the API response
      _initializeVideo();
      _checkIfDownloaded();
    });
  }

  @override
  void deactivate() {
    _controller?.pause();
    super.deactivate();
  }

  Future<void> _initializeDownloadService() async {
    await _downloadService.initialize();
  }

  Future<void> _checkIfDownloaded() async {
    final lesson = _lesson;
    if (lesson == null) return;

    final lessonId = lesson['id']?.toString();
    if (lessonId == null || lessonId.isEmpty) return;

    final isDownloaded = await _downloadService.isVideoDownloaded(lessonId);
    if (mounted) {
      setState(() {
        _isDownloaded = isDownloaded;
      });
    }
  }

  Future<void> _loadLessonContent() async {
    final lesson = _lesson;
    if (lesson == null) {
      setState(() {
        _isLoadingContent = false;
      });
      return;
    }

    // Get courseId from widget or extract from lesson
    String? courseId = widget.courseId;
    if (courseId == null || courseId.isEmpty) {
      courseId =
          lesson['course_id']?.toString() ?? lesson['courseId']?.toString();
    }

    final lessonId = lesson['id']?.toString();

    if (courseId == null ||
        courseId.isEmpty ||
        lessonId == null ||
        lessonId.isEmpty) {
      setState(() {
        _isLoadingContent = false;
      });
      return;
    }

    try {
      final content = await CoursesService.instance.getLessonContent(
        courseId,
        lessonId,
      );

      if (mounted) {
        setState(() {
          _lessonContent = content;
          _isLoadingContent = false;
        });
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error loading lesson content: $e');
      }
      if (mounted) {
        setState(() {
          _isLoadingContent = false;
        });
      }
    }
  }

  /// Clean and normalize video URL
  String? _cleanVideoUrl(String? url) {
    if (url == null || url.isEmpty) return null;

    // Remove any blob: prefix if present at the start
    url = url.replaceFirst(RegExp(r'^blob:'), '').trim();

    // Fix URLs that have blob: in the middle (like "https://domain.com/blob:https://...")
    if (url.contains('blob:')) {
      final blobIndex = url.indexOf('blob:');
      if (blobIndex != -1) {
        final afterBlob =
            url.substring(blobIndex + 5).trim(); // 5 is length of "blob:"
        // If the part after blob: starts with http/https, use it directly
        if (afterBlob.startsWith('http://') ||
            afterBlob.startsWith('https://')) {
          url = afterBlob;
        } else {
          // Otherwise, remove the blob: part and keep everything before and after
          url = url.substring(0, blobIndex).trim() + afterBlob;
        }
      }
    }

    // Ensure URL is valid
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      if (kDebugMode) {
        print('⚠️ Invalid video URL format: $url');
      }
      return null;
    }

    return url.trim();
  }

  Future<void> _initializeVideo() async {
    final lesson = _lesson;
    if (lesson == null) {
      setState(() => _isVideoLoading = false);
      return;
    }

    // Wait for content to load, then use it for video
    // If content is already loaded, use it; otherwise use lesson data
    final videoData = _lessonContent?['video'] ?? lesson['video'];

    // Extract video ID from lesson content or lesson - try all possible fields
    String? videoId;
    String? videoUrl;

    // 1. Try video_url field directly from lesson (highest priority)
    videoUrl = _cleanVideoUrl(lesson['video_url']?.toString());

    // 2. Try video object with youtube_id from content
    if (videoUrl == null && videoData is Map) {
      videoId = videoData['youtube_id']?.toString();
      videoUrl = _cleanVideoUrl(videoData['url']?.toString());
    }

    // 3. Try video object with youtube_id from lesson
    if (videoUrl == null && lesson['video'] is Map) {
      videoId = lesson['video']?['youtube_id']?.toString();
      videoUrl = _cleanVideoUrl(lesson['video']?['url']?.toString());
    }

    // 4. Try direct youtube_id field
    videoId = videoId ?? lesson['youtube_id']?.toString();

    // 5. Try youtubeVideoId field
    videoId = videoId ?? lesson['youtubeVideoId']?.toString();

    // 6. If no video object, use lesson id as video id
    if (videoId == null || videoId.isEmpty) {
      videoId = lesson['id']?.toString();
    }

    videoId = videoId ?? '';

    final qb = _mergeApiVideoQualities(lesson, _lessonContent);

    String? resolvedUrl = videoUrl;
    if (resolvedUrl == null || resolvedUrl.isEmpty) {
      if (qb.qualities.isNotEmpty) {
        resolvedUrl = _pickInitialDirectPlayUrl(null, qb);
      }
    } else if (qb.qualities.isNotEmpty &&
        !resolvedUrl.contains('youtube.com') &&
        !resolvedUrl.contains('youtu.be')) {
      resolvedUrl = _pickInitialDirectPlayUrl(resolvedUrl, qb);
    }

    if (kDebugMode) {
      print('═══════════════════════════════════════════════════════════');
      print('🎥 INITIALIZING VIDEO IN LESSON VIEWER');
      print('═══════════════════════════════════════════════════════════');
      print('Video ID: $videoId');
      print('Video URL (cleaned): $videoUrl');
      print('Resolved play URL: $resolvedUrl');
      print('API video_qualities: ${qb.qualities.keys.toList()}');
      print('Lesson ID: ${lesson['id']}');
      print('Lesson Title: ${lesson['title']}');
      print('Video Object: $videoData');
      print('Raw video_url: ${lesson['video_url']}');
      print('All Lesson Keys: ${lesson.keys.toList()}');
      print('═══════════════════════════════════════════════════════════');
    }

    try {
      // Use video URL if available, otherwise use YouTube ID
      if (resolvedUrl != null && resolvedUrl.isNotEmpty) {
        // Check if it's a YouTube URL
        if (resolvedUrl.contains('youtube.com') ||
            resolvedUrl.contains('youtu.be')) {
          if (mounted) {
            setState(() {
              _serverQualityUrls = {};
              _serverQualityOrder = [];
            });
          }
          if (kDebugMode) {
            print('📺 Using YouTube URL: $resolvedUrl');
          }
          await _initializeYoutubeVideo(resolvedUrl);
        } else {
          final playUrl = resolvedUrl;
          if (mounted) {
            setState(() {
              if (qb.qualities.isEmpty) {
                _serverQualityUrls = {};
                _serverQualityOrder = [];
                _selectedQuality = null;
              } else {
                _serverQualityUrls = qb.qualities;
                _serverQualityOrder = qb.orderedOptions;
                _selectedQuality =
                    _findQualityKeyForUrl(qb.qualities, playUrl) ??
                        (qb.defaultQuality != null &&
                                qb.qualities.containsKey(qb.defaultQuality!)
                            ? qb.defaultQuality
                            : null) ??
                        (qb.orderedOptions.isNotEmpty
                            ? qb.orderedOptions.first
                            : qb.qualities.keys.first);
              }
              _youtubeQualityUrls = {};
              _isLoadingQualities = false;
            });
          }
          if (kDebugMode) {
            print('📹 Using pod_player for direct video URL: $playUrl');
          }
          await _initializeDirectVideo(playUrl);
        }
      } else if (videoId.isNotEmpty) {
        if (mounted) {
          setState(() {
            _serverQualityUrls = {};
            _serverQualityOrder = [];
          });
        }
        // Fallback to YouTube ID
        if (kDebugMode) {
          print('📺 Using YouTube ID fallback: $videoId');
        }
        final youtubeUrl = 'https://www.youtube.com/watch?v=$videoId';
        await _initializeYoutubeVideo(youtubeUrl);
      } else {
        // No valid video source
        if (kDebugMode) {
          print('⚠️ No valid video source found');
        }
        if (mounted) {
          setState(() => _isVideoLoading = false);
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error initializing video: $e');
      }
      if (mounted) {
        setState(() => _isVideoLoading = false);
      }
    }
  }

  Future<void> _initializeYoutubeVideo(String youtubeUrl) async {
    try {
      final canonical = canonicalYoutubeWatchUrl(youtubeUrl);
      if (kDebugMode && canonical != youtubeUrl) {
        print(
            '📺 Normalized YouTube URL for playback: $youtubeUrl → $canonical');
      }
      youtubeUrl = canonical;
      _lastYoutubeUrl = youtubeUrl;
      _controller?.dispose();
      _controller = null;
      if (!mounted) return;
      setState(() {
        _useWebViewFallback = false;
        _isVideoLoading = true;
        _youtubeQualityUrls = {};
        _serverQualityUrls = {};
        _serverQualityOrder = [];
        _selectedQuality = null;
      });

      if (kDebugMode) {
        print('═══════════════════════════════════════════════════════════');
        print('📺 YouTube: fetching muxed qualities (youtube_explode_dart)');
        print('Source URL: $youtubeUrl');
        print('═══════════════════════════════════════════════════════════');
      }

      await _fetchYoutubeQualities(youtubeUrl);
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error initializing YouTube playback: $e');
      }
      await _playYoutubeDefault(youtubeUrl);
    }
  }

  Future<void> _playYoutubeDefault(String youtubeUrl) async {
    _controller?.dispose();
    _controller = null;
    if (!mounted) return;
    setState(() {
      _youtubeQualityUrls = {};
      _serverQualityUrls = {};
      _serverQualityOrder = [];
      _selectedQuality = null;
      _isLoadingQualities = false;
      _isVideoLoading = true;
    });

    _controller = PodPlayerController(
      playVideoFrom: PlayVideoFrom.youtube(youtubeUrl),
      podPlayerConfig: const PodPlayerConfig(
        autoPlay: false,
        isLooping: false,
      ),
    );

    _controller!.initialise().then((_) {
      if (!mounted) return;
      setState(() {
        _isVideoLoading = false;
      });
    }).catchError((error) {
      if (kDebugMode) {
        print('❌ Error initializing YouTube fallback: $error');
      }
      if (mounted) {
        setState(() => _isVideoLoading = false);
      }
    });
  }

  /// Initialize direct video playback using pod_player
  Future<void> _initializeDirectVideo(String videoUrl) async {
    try {
      if (kDebugMode) {
        print('📹 Initializing direct video with pod_player: $videoUrl');
      }

      if (!mounted) return;
      setState(() {
        _youtubeQualityUrls = {};
        _isLoadingQualities = false;
        _useWebViewFallback = false;
        _isVideoLoading = true;
        if (_serverQualityUrls.isEmpty) {
          _selectedQuality = null;
        }
      });

      await _initPodNetworkFromUrl(videoUrl);
      if (!mounted) return;
      setState(() {
        _isVideoLoading = false;
      });
      if (kDebugMode) {
        print('✅ Direct video initialized successfully with pod_player');
      }
    } catch (error, st) {
      if (kDebugMode) {
        print('❌ Error initializing direct video with pod_player: $error');
        print(st);
        print('   Falling back to WebView...');
      }
      if (mounted) {
        await _initializeWebView(videoUrl);
      }
    }
  }

  /// Initialize WebView for direct video playback (fallback method)
  Future<void> _initializeWebView(String videoUrl) async {
    try {
      if (kDebugMode) {
        print('🌐 Initializing WebView for video playback: $videoUrl');
      }

      // Get authorization token for video access
      final token = await TokenStorageService.instance.getAccessToken();

      setState(() {
        _useWebViewFallback = true;
      });

      // Try to load video via Flutter HTTP request first (to bypass CORS)
      // Then pass it to WebView as blob URL
      try {
        if (kDebugMode) {
          print('📥 Loading video via Flutter HTTP request...');
        }

        final headers = <String, String>{};
        if (token != null && token.isNotEmpty) {
          headers['Authorization'] = 'Bearer $token';
        }

        // Load video and save to temporary file
        final response = await http
            .get(
              Uri.parse(videoUrl),
              headers: headers,
            )
            .timeout(const Duration(seconds: 60));

        if (response.statusCode == 200) {
          if (kDebugMode) {
            print(
                '✅ Video loaded successfully via HTTP (${response.bodyBytes.length} bytes)');
          }

          // Save to temporary file
          final tempDir = await getTemporaryDirectory();
          final fileName = videoUrl.split('/').last.split('?').first;
          final fileExtension = fileName.split('.').last;
          final tempFile = File(
              '${tempDir.path}/video_${DateTime.now().millisecondsSinceEpoch}.$fileExtension');

          await tempFile.writeAsBytes(response.bodyBytes);

          if (kDebugMode) {
            print('💾 Video saved to temporary file: ${tempFile.path}');
          }

          // Use file:// URL for WebView
          final fileUrl = tempFile.path;
          _createWebViewWithFileUrl(fileUrl);

          // Store reference to temp file for cleanup
          setState(() {
            _tempVideoFile = tempFile;
          });

          return;
        } else {
          if (kDebugMode) {
            print('❌ HTTP request failed with status: ${response.statusCode}');
          }
        }
      } catch (e) {
        if (kDebugMode) {
          print('⚠️ Failed to load video via HTTP: $e');
          print('   Falling back to direct WebView method...');
        }
      }

      // Fallback: Try direct WebView method

      _createWebViewWithDirectUrl(videoUrl, token);
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error initializing WebView: $e');
      }
      if (mounted) {
        setState(() {
          _isVideoLoading = false;
        });
      }
    }
  }

  /// Create WebView with file URL (from temporary file)
  void _createWebViewWithFileUrl(String filePath) {
    // Convert file path to file:// URL
    final fileUrl =
        Platform.isAndroid ? 'file://$filePath' : 'file://$filePath';

    final htmlContent = '''
<!DOCTYPE html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <style>
    * {
      margin: 0;
      padding: 0;
      box-sizing: border-box;
    }
    html, body {
      width: 100%;
      height: 100%;
      background-color: #000;
      overflow: hidden;
    }
    video {
      width: 100%;
      height: 100%;
      object-fit: contain;
      background-color: #000;
    }
  </style>
</head>
<body>
  <video id="videoPlayer" controls autoplay playsinline webkit-playsinline>
    <source src="$fileUrl" type="video/mp4">
    Your browser does not support the video tag.
  </video>
  <script>
    var video = document.getElementById('videoPlayer');
    video.addEventListener('loadeddata', function() {
      console.log('Video loaded successfully from file URL');
    });
    video.addEventListener('error', function(e) {
      console.error('Video error:', e);
      var error = video.error;
      if (error) {
        console.error('Error code:', error.code, 'Message:', error.message);
      }
    });
  </script>
</body>
</html>
''';

    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (String url) {
            if (kDebugMode) {
              print('✅ WebView page finished: $url');
            }
            if (mounted) {
              setState(() {
                _isVideoLoading = false;
              });
            }
          },
          onWebResourceError: (WebResourceError error) {
            if (kDebugMode) {
              print('❌ WebView resource error: ${error.description}');
            }
            if (mounted) {
              setState(() {
                _isVideoLoading = false;
              });
            }
          },
        ),
      )
      ..loadHtmlString(htmlContent);

    if (mounted) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          setState(() {
            _isVideoLoading = false;
          });
        }
      });
    }
  }

  /// Create WebView with direct URL (fallback method)
  void _createWebViewWithDirectUrl(String videoUrl, String? token) {
    // Build video URL with token as query parameter (fallback method)
    String videoUrlWithToken = videoUrl;
    if (token != null && token.isNotEmpty) {
      final uri = Uri.parse(videoUrl);
      videoUrlWithToken = uri.replace(queryParameters: {
        ...uri.queryParameters,
        'token': token,
      }).toString();
    }

    // Create HTML5 video player with multiple fallback methods
    final htmlContent = '''
<!DOCTYPE html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <style>
    * {
      margin: 0;
      padding: 0;
      box-sizing: border-box;
    }
    html, body {
      width: 100%;
      height: 100%;
      background-color: #000;
      overflow: hidden;
    }
    video {
      width: 100%;
      height: 100%;
      object-fit: contain;
      background-color: #000;
    }
    .loading {
      position: absolute;
      top: 50%;
      left: 50%;
      transform: translate(-50%, -50%);
      color: white;
      font-family: Arial, sans-serif;
      text-align: center;
    }
    .error {
      color: #ff6b6b;
    }
  </style>
</head>
<body>
  <div class="loading" id="loading">جاري تحميل الفيديو...</div>
  <video id="videoPlayer" controls autoplay playsinline webkit-playsinline style="display: none;">
    Your browser does not support the video tag.
  </video>
  <script>
    var video = document.getElementById('videoPlayer');
    var loading = document.getElementById('loading');
    var videoUrl = '$videoUrl';
    var videoUrlWithToken = '$videoUrlWithToken';
    ${token != null ? "var token = '$token';" : 'var token = null;'}
    var currentMethod = 0;
    var methods = ['direct', 'no-cors', 'token-param'];
    
    function showVideo() {
      video.style.display = 'block';
      loading.style.display = 'none';
    }
    
    function showError(message) {
      loading.textContent = message;
      loading.className = 'loading error';
    }
    
    // Method 1: Try direct video source first (simplest, may work if server allows)
    function tryDirectVideo() {
      console.log('Trying method 1: Direct video source');
      video.src = videoUrl;
      video.load();
      
      var timeout = setTimeout(function() {
        if (video.readyState === 0) {
          console.log('Direct method failed, trying next method');
          tryNoCorsFetch();
        }
      }, 3000);
      
      video.addEventListener('loadeddata', function() {
        clearTimeout(timeout);
        console.log('Direct method succeeded');
        showVideo();
      }, { once: true });
      
      video.addEventListener('error', function(e) {
        clearTimeout(timeout);
        console.log('Direct method failed:', e);
        tryNoCorsFetch();
      }, { once: true });
    }
    
    // Method 2: Try fetch with no-cors mode
    async function tryNoCorsFetch() {
      console.log('Trying method 2: Fetch with no-cors mode');
      try {
        var response = await fetch(videoUrl, {
          method: 'GET',
          mode: 'no-cors',
          cache: 'default'
        });
        
        // With no-cors, we can't read the response, but we can try to use it
        // Try to create a blob URL anyway
        if (response.type === 'opaque') {
          // Opaque response - try to use video tag with the URL directly
          console.log('Got opaque response, trying direct video');
          video.src = videoUrl;
          video.load();
          
          video.addEventListener('loadeddata', function() {
            console.log('Video loaded after no-cors fetch');
            showVideo();
          }, { once: true });
          
          video.addEventListener('error', function(e) {
            console.log('No-cors method failed:', e);
            tryTokenParam();
          }, { once: true });
        }
      } catch (error) {
        console.log('No-cors fetch failed:', error);
        tryTokenParam();
      }
    }
    
    // Method 3: Try with token as query parameter
    function tryTokenParam() {
      if (!token) {
        showError('لا يمكن تحميل الفيديو');
        return;
      }
      
      console.log('Trying method 3: Token as query parameter');
      video.src = videoUrlWithToken;
      video.load();
      
      video.addEventListener('loadeddata', function() {
        console.log('Token param method succeeded');
        showVideo();
      }, { once: true });
      
      video.addEventListener('error', function(e) {
        console.log('Token param method failed:', e);
        showError('فشل تحميل الفيديو. يرجى التحقق من الاتصال بالإنترنت.');
      }, { once: true });
    }
    
    // Add error handlers
    video.addEventListener('error', function(e) {
      var error = video.error;
      if (error) {
        console.error('Video error code:', error.code, 'Message:', error.message);
        if (error.code === 4) {
          // MEDIA_ELEMENT_ERROR: Format error
          showError('تنسيق الفيديو غير مدعوم');
        } else if (error.code === 3) {
          // MEDIA_ELEMENT_ERROR: Decode error
          showError('خطأ في فك تشفير الفيديو');
        } else if (error.code === 2) {
          // MEDIA_ELEMENT_ERROR: Network error
          showError('خطأ في الاتصال بالشبكة');
        } else {
          showError('خطأ في تحميل الفيديو');
        }
      }
    });
    
    // Start loading
    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', tryDirectVideo);
    } else {
      tryDirectVideo();
    }
  </script>
</body>
</html>
''';

    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            if (kDebugMode) {
              print('🌐 WebView page started: $url');
            }
          },
          onPageFinished: (String url) {
            if (kDebugMode) {
              print('✅ WebView page finished: $url');
            }
            if (mounted) {
              setState(() {
                _isVideoLoading = false;
              });
            }
          },
          onWebResourceError: (WebResourceError error) {
            if (kDebugMode) {
              print('❌ WebView resource error: ${error.description}');
              print('   Error code: ${error.errorCode}');
              print('   Error type: ${error.errorType}');
              print('   Failed URL: ${error.url}');

              // Log specific error types
              if (error.errorCode == -1) {
                print(
                    '   ⚠️ CORS or ORB (Opaque Response Blocking) error detected');
                print(
                    '   💡 This is expected - JavaScript will handle fallback methods');
              }
            }
            // Don't set loading to false immediately - let JavaScript try fallback methods
            // Only set to false if it's a critical error
            if (error.errorType == WebResourceErrorType.hostLookup ||
                error.errorType == WebResourceErrorType.timeout) {
              if (mounted) {
                setState(() {
                  _isVideoLoading = false;
                });
              }
            }
          },
        ),
      )
      ..loadHtmlString(htmlContent);

    if (mounted) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          setState(() {
            _isVideoLoading = false;
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    // Clean up temporary video file
    if (_tempVideoFile != null) {
      try {
        _tempVideoFile!.deleteSync();
      } catch (e) {
        if (kDebugMode) {
          print('⚠️ Error deleting temp video file: $e');
        }
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
    );

    final lesson = _lesson;
    if (lesson == null) {
      return Scaffold(
        backgroundColor: const Color(0xFF0F0F1A),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.white54),
              const SizedBox(height: 16),
              Text(
                'لا يوجد درس',
                style: GoogleFonts.cairo(color: Colors.white, fontSize: 18),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            // Video Player Section
            _buildVideoSection(lesson),

            // Lesson Info Section
            Expanded(
              child: _buildLessonInfo(lesson),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoSection(Map<String, dynamic> lesson) {
    return Container(
      color: Colors.black,
      child: Column(
        children: [
          // Header
          Container(
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 8,
              left: 16,
              right: 16,
              bottom: 8,
            ),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => context.pop(),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.arrow_back_ios_new_rounded,
                        color: Colors.white, size: 18),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        lesson['title'] as String? ?? 'عنوان الدرس',
                        style: GoogleFonts.cairo(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'المدة: ${lesson['duration'] ?? 'غير محدد'}',
                        style: GoogleFonts.cairo(
                          fontSize: 12,
                          color: Colors.white60,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_isLoadingQualities)
                  const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.purple,
                      ),
                    ),
                  )
                else if (_serverQualityUrls.length > 1)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: _buildServerQualityPicker(),
                  )
                else if (_youtubeQualityUrls.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: _buildQualityPicker(),
                  ),
              ],
            ),
          ),

          // Video Player
          SizedBox(
            height: 220,
            child: _isVideoLoading
                ? Container(
                    color: Colors.black,
                    child: const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.purple,
                      ),
                    ),
                  )
                : _controller != null
                    ? PodVideoPlayer(
                        controller: _controller!,
                        videoAspectRatio: 16 / 9,
                        podProgressBarConfig: const PodProgressBarConfig(
                          playingBarColor: AppColors.purple,
                          circleHandlerColor: AppColors.purple,
                          bufferedBarColor: Colors.white30,
                        ),
                      )
                    : _useWebViewFallback && _webViewController != null
                        ? WebViewWidget(controller: _webViewController!)
                        : Container(
                            color: Colors.black,
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.error_outline,
                                      color: Colors.white54, size: 48),
                                  const SizedBox(height: 12),
                                  Text(
                                    'لا يمكن تحميل الفيديو',
                                    style: GoogleFonts.cairo(
                                      color: Colors.white54,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildLessonInfo(Map<String, dynamic> lesson) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF8F9FC),
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Lesson Title & Stats
            Text(
              lesson['title'] as String? ?? 'عنوان الدرس',
              style: GoogleFonts.cairo(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppColors.foreground,
              ),
            ),
            const SizedBox(height: 12),

            // Stats Row
            Row(
              children: [
                _buildStatBadge(
                    Icons.access_time_rounded, lesson['duration'] ?? '0'),
                // const SizedBox(width: 12),
                // _buildStatBadge(Icons.visibility_rounded, '0 مشاهدة'),
                // const SizedBox(width: 12),
                // _buildStatBadge(Icons.thumb_up_rounded, '0%'),
              ],
            ),
            const SizedBox(height: 24),

            // Description Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.purple.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.description_rounded,
                            color: AppColors.purple, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'وصف الدرس',
                        style: GoogleFonts.cairo(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.foreground,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _isLoadingContent
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(20.0),
                            child: CircularProgressIndicator(
                              color: AppColors.purple,
                            ),
                          ),
                        )
                      : Text(
                          _lessonContent?['description'] as String? ??
                              'لا يوجد وصف متاح',
                          style: GoogleFonts.cairo(
                            fontSize: 14,
                            color: AppColors.mutedForeground,
                            height: 1.7,
                          ),
                        ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Download Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.purple.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.download_rounded,
                            color: AppColors.purple, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'تحميل للعرض بدون إنترنت',
                        style: GoogleFonts.cairo(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.foreground,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_isDownloading)
                    Column(
                      children: [
                        LinearProgressIndicator(
                          value: _downloadProgress / 100,
                          backgroundColor: Colors.grey[200],
                          valueColor: AlwaysStoppedAnimation<Color>(
                            AppColors.purple,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'جاري التحميل: $_downloadProgress%',
                          style: GoogleFonts.cairo(
                            fontSize: 14,
                            color: AppColors.mutedForeground,
                          ),
                        ),
                      ],
                    )
                  else if (_isDownloaded)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green[50],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.check_circle,
                              color: Colors.green[600], size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'تم تحميل الفيديو',
                            style: GoogleFonts.cairo(
                              fontSize: 14,
                              color: Colors.green[700],
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    ElevatedButton.icon(
                      onPressed: _handleDownload,
                      icon: const Icon(Icons.download, color: Colors.white),
                      label: Text(
                        'تحميل للعرض بدون إنترنت',
                        style: GoogleFonts.cairo(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.purple,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Resources Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.folder_rounded,
                            color: Colors.orange, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'ملفات الدرس',
                        style: GoogleFonts.cairo(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.foreground,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _isLoadingContent
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(20.0),
                            child: CircularProgressIndicator(
                              color: AppColors.purple,
                            ),
                          ),
                        )
                      : _buildResourcesList(),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Navigation Buttons
            Row(
              children: [
                Expanded(
                  child: _buildNavButton(
                    'الدرس السابق',
                    Icons.arrow_forward_rounded,
                    false,
                    _onPreviousLesson,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 1,
                  child: _buildNavButton(
                    'الدرس التالي',
                    Icons.arrow_back_rounded,
                    true,
                    _onNextLesson,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  void _onPreviousLesson() {
    final flat = _allLessons;
    final idx = _lessonIndexInCourse;
    if (flat == null || idx == null) {
      context.pop();
      return;
    }
    if (idx <= 0) {
      context.pop();
      return;
    }
    final prev = flat[idx - 1];
    if (lessonMapIsLocked(prev)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(lessonLockMessage(prev), style: GoogleFonts.cairo()),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    _switchToLesson(prev, idx - 1);
  }

  void _onNextLesson() {
    final flat = _allLessons;
    final idx = _lessonIndexInCourse;
    if (flat == null || idx == null) {
      context.pop();
      return;
    }
    if (idx >= flat.length - 1) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('لا يوجد درس تالي', style: GoogleFonts.cairo()),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final nxt = flat[idx + 1];
    if (lessonMapIsLocked(nxt)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(lessonLockMessage(nxt), style: GoogleFonts.cairo()),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    _switchToLesson(nxt, idx + 1);
  }

  Future<void> _switchToLesson(Map<String, dynamic> next, int newIndex) async {
    _controller?.dispose();
    _controller = null;
    _webViewController = null;
    if (_tempVideoFile != null) {
      try {
        _tempVideoFile!.deleteSync();
      } catch (_) {}
      _tempVideoFile = null;
    }
    if (!mounted) return;
    setState(() {
      _lessonState = Map<String, dynamic>.from(next);
      _lessonIndexInCourse = newIndex;
      _lessonContent = null;
      _isLoadingContent = true;
      _isVideoLoading = true;
      _useWebViewFallback = false;
      _youtubeQualityUrls = {};
      _serverQualityUrls = {};
      _serverQualityOrder = [];
      _selectedQuality = null;
      _isLoadingQualities = false;
      _isDownloaded = false;
    });
    await _loadLessonContent();
    if (!mounted) return;
    await _initializeVideo();
    await _checkIfDownloaded();
  }

  Widget _buildStatBadge(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.purple),
          const SizedBox(width: 6),
          Text(
            text,
            style: GoogleFonts.cairo(fontSize: 12, color: AppColors.foreground),
          ),
        ],
      ),
    );
  }

  Widget _buildResourcesList() {
    final resources = _lessonContent?['resources'] as List?;
    final contentPdf = _lessonContent?['content_pdf'] as String?;

    // Build list of resources
    final List<Map<String, dynamic>> resourceList = [];

    // Add PDF if available
    if (contentPdf != null && contentPdf.isNotEmpty) {
      resourceList.add({
        'title': 'ملف PDF - ملخص الدرس',
        'url': contentPdf,
        'type': 'pdf',
        'icon': Icons.picture_as_pdf,
      });
    }

    // Add resources from API
    if (resources != null && resources.isNotEmpty) {
      for (var resource in resources) {
        if (resource is Map<String, dynamic>) {
          final title = resource['title']?.toString() ??
              resource['name']?.toString() ??
              'ملف مرفق';
          final url =
              resource['url']?.toString() ?? resource['file']?.toString() ?? '';
          final type = (resource['type']?.toString() ??
                  resource['file_type']?.toString() ??
                  '')
              .toLowerCase();

          IconData icon = Icons.insert_drive_file;
          if (type.contains('pdf')) {
            icon = Icons.picture_as_pdf;
          } else if (type.contains('zip') || type.contains('rar')) {
            icon = Icons.folder_zip;
          } else if (type.contains('image')) {
            icon = Icons.image;
          } else if (type.contains('video')) {
            icon = Icons.video_file;
          }

          resourceList.add({
            'title': title,
            'url': url,
            'type': type,
            'icon': icon,
            'size': resource['size']?.toString() ?? '',
          });
        }
      }
    }

    if (resourceList.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(20.0),
        child: Center(
          child: Text(
            'لا توجد ملفات متاحة',
            style: GoogleFonts.cairo(
              fontSize: 14,
              color: AppColors.mutedForeground,
            ),
          ),
        ),
      );
    }

    return Column(
      children: resourceList.asMap().entries.map((entry) {
        final index = entry.key;
        final resource = entry.value;
        return Column(
          children: [
            _buildResourceItem(
              resource['title'] as String,
              resource['size'] as String? ?? '',
              resource['icon'] as IconData,
              resource['url'] as String? ?? '',
            ),
            if (index < resourceList.length - 1) const SizedBox(height: 10),
          ],
        );
      }).toList(),
    );
  }

  Future<void> _handleDownload() async {
    final lesson = _lesson;
    if (lesson == null) return;

    final lessonId = lesson['id']?.toString();
    final courseId = widget.courseId ?? lesson['course_id']?.toString();
    final title = lesson['title']?.toString() ?? 'فيديو';
    final description = lesson['description']?.toString() ?? '';

    if (lessonId == null || courseId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'لا يمكن تحميل هذا الفيديو',
            style: GoogleFonts.cairo(),
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // التحميل يُحفظ في مجلد التطبيق الخاص — لا يحتاج صلاحيات التخزين/الوسائط.

    final qb = _mergeApiVideoQualities(lesson, _lessonContent);

    // الحصول على رابط الفيديو (نفس منطق التشغيل، مع تنظيف الرابط)
    String? rawVideoUrl = _lessonContent?['video']?['url']?.toString() ??
        lesson['video_url']?.toString() ??
        lesson['video']?['url']?.toString();

    if ((rawVideoUrl == null || rawVideoUrl.isEmpty) &&
        qb.qualities.isNotEmpty) {
      rawVideoUrl = _pickInitialDirectPlayUrl(null, qb);
    }

    String? videoUrl = _cleanVideoUrl(rawVideoUrl);
    if (qb.qualities.isNotEmpty) {
      String? fixed;
      for (final k in ['720p', '1080p', '480p', '360p']) {
        final u = qb.qualities[k];
        if (u != null) {
          fixed = u;
          break;
        }
      }
      if (fixed != null) {
        videoUrl = _cleanVideoUrl(fixed);
      }
    }

    if (videoUrl == null || videoUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'لا يوجد رابط فيديو للتحميل',
            style: GoogleFonts.cairo(),
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isDownloading = true;
      _downloadProgress = 0;
    });

    try {
      // الحصول على عنوان الكورس
      String? courseTitle;
      try {
        final courseDetails =
            await CoursesService.instance.getCourseDetails(courseId);
        courseTitle = courseDetails['title']?.toString();
      } catch (e) {
        print('Error getting course title: $e');
      }
      if (videoUrl.contains('youtube.com') || videoUrl.contains('youtu.be')) {
        // Build fileName with course title for better organization
        final safeCourseTitle = (courseTitle ?? 'course_$courseId')
            .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
            .trim();
        final safeLessonTitle =
            title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
        final fileName =
            '${safeCourseTitle}_${safeLessonTitle}_${DateTime.now().millisecondsSinceEpoch}.mp4';

        final localPath =
            await YoutubeVideoService.instance.downloadYoutubeVideo(
          videoUrl,
          fileName: fileName,
          onProgress: (progress) {
            if (mounted) {
              setState(() => _downloadProgress = progress);
            }
          },
        );

        if (localPath != null) {
          // Save to database so it appears in Downloads screen (like server downloads)
          // title = course title (main display), courseTitle = course for grouping
          final videoId = await _downloadService.saveDownloadedVideoRecord(
            lessonId: lessonId,
            courseId: courseId,
            title: courseTitle ?? title,
            videoUrl: videoUrl,
            localPath: localPath,
            courseTitle: courseTitle ?? 'كورس $courseId',
            description: description.isNotEmpty ? description : title,
            durationText: lesson['duration']?.toString(),
            videoSource: 'youtube',
          );

          if (kDebugMode && videoId != null) {
            log('YouTube video saved to database: $videoId');
          }

          if (mounted) {
            setState(() {
              _isDownloading = false;
              _isDownloaded = true;
              _downloadProgress = 0;
            });

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'تم تحميل الفيديو بنجاح',
                  style: GoogleFonts.cairo(),
                ),
                backgroundColor: Colors.green,
              ),
            );
          }
        } else {
          if (mounted) {
            setState(() {
              _isDownloading = false;
              _downloadProgress = 0;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'فشل تحميل الفيديو',
                  style: GoogleFonts.cairo(),
                ),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
        return;
      }

      final videoId = await _downloadService.downloadVideoWithManager(
        videoUrl: videoUrl,
        lessonId: lessonId,
        courseId: courseId,
        title: title,
        courseTitle: courseTitle,
        description: description,
        onProgress: (progress) {
          if (mounted) {
            setState(() {
              _downloadProgress = progress;
            });
          }
        },
      );

      if (videoId != null) {
        if (mounted) {
          setState(() {
            _isDownloading = false;
            _isDownloaded = true;
            _downloadProgress = 0;
          });

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'تم تحميل الفيديو بنجاح',
                style: GoogleFonts.cairo(),
              ),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        throw Exception('فشل تحميل الفيديو');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _downloadProgress = 0;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'خطأ في تحميل الفيديو: ${e.toString().replaceFirst('Exception: ', '')}',
              style: GoogleFonts.cairo(),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildResourceItem(
      String title, String size, IconData icon, String url) {
    // Check if the resource is a PDF
    final isPdf = url.toLowerCase().contains('.pdf') ||
        title.toLowerCase().contains('pdf') ||
        icon == Icons.picture_as_pdf;

    return GestureDetector(
      onTap: url.isNotEmpty
          ? () {
              if (kDebugMode) {
                print('Opening resource: $url');
              }

              if (isPdf) {
                // Open PDF in viewer screen
                context.push(
                  RouteNames.pdfViewer,
                  extra: {
                    'pdfUrl': url,
                    'title': title,
                  },
                );
              } else {
                // For non-PDF files, you can implement download or other actions
                if (kDebugMode) {
                  print('Non-PDF file: $url');
                }
              }
            }
          : null,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F9FC),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: Colors.red, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.cairo(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.foreground),
                  ),
                  if (size.isNotEmpty)
                    Text(
                      size,
                      style: GoogleFonts.cairo(
                          fontSize: 11, color: AppColors.mutedForeground),
                    ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isPdf
                    ? AppColors.purple.withOpacity(0.1)
                    : AppColors.purple.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                isPdf ? Icons.preview_rounded : Icons.download_rounded,
                color: AppColors.purple,
                size: 18,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavButton(
      String text, IconData icon, bool isPrimary, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          gradient: isPrimary
              ? const LinearGradient(
                  colors: [Color(0xFF7C3AED), Color(0xFF5B21B6)])
              : null,
          color: isPrimary ? null : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: isPrimary ? null : Border.all(color: Colors.grey[200]!),
          boxShadow: isPrimary
              ? [
                  BoxShadow(
                    color: AppColors.purple.withOpacity(0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (!isPrimary) Icon(icon, size: 18, color: AppColors.foreground),
            if (!isPrimary) const SizedBox(width: 8),
            Text(
              text,
              style: GoogleFonts.cairo(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: isPrimary ? Colors.white : AppColors.foreground,
              ),
            ),
            if (isPrimary) const SizedBox(width: 8),
            if (isPrimary) Icon(icon, size: 18, color: Colors.white),
          ],
        ),
      ),
    );
  }
}
