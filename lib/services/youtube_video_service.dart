import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../core/services/download_manager.dart';

/// Normalizes embed / shorts / youtu.be links to `https://www.youtube.com/watch?v=ID`.
/// [youtube_explode_dart] resolves the watch page; `/embed/…` often fails with
/// [VideoUnavailableException] even when the video plays in a browser.
String canonicalYoutubeWatchUrl(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return trimmed;

  late final Uri uri;
  try {
    uri = Uri.parse(trimmed);
  } catch (_) {
    return trimmed;
  }

  final host = uri.host.toLowerCase();
  final isYoutube = host.contains('youtube.com') ||
      host == 'youtu.be' ||
      host.endsWith('.youtube.com');
  if (!isYoutube) return trimmed;

  // youtu.be/VIDEO_ID
  if (host.contains('youtu.be') && uri.pathSegments.isNotEmpty) {
    final id = uri.pathSegments.first;
    if (id.isNotEmpty) return 'https://www.youtube.com/watch?v=$id';
  }

  final v = uri.queryParameters['v'];
  if (v != null && v.isNotEmpty) {
    return 'https://www.youtube.com/watch?v=$v';
  }

  // /embed/ID, /v/ID, /shorts/ID, /live/ID
  final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  if (segs.length >= 2) {
    final first = segs[0].toLowerCase();
    if (first == 'embed' ||
        first == 'v' ||
        first == 'shorts' ||
        first == 'live') {
      final id = segs[1];
      if (id.isNotEmpty) return 'https://www.youtube.com/watch?v=$id';
    }
  }

  return trimmed;
}

class YoutubeVideoService {
  YoutubeVideoService._();
  static final instance = YoutubeVideoService._();
  final YoutubeExplode _yt = YoutubeExplode();

  /// Download YouTube video and return local file path (or null on fail)
  Future<String?> downloadYoutubeVideo(
    String youtubeUrl, {
    required Function(int progress) onProgress,
    String? fileName,
  }) async {
    try {
      youtubeUrl = canonicalYoutubeWatchUrl(youtubeUrl);
      final video = await _yt.videos.get(youtubeUrl);
      final manifest = await _yt.videos.streamsClient.getManifest(video.id);

      // Pick highest MP4 progressive stream (video + audio)
      final streamInfo = manifest.muxed.withHighestBitrate();

      final directUrl = streamInfo.url.toString();
      print('🎥 YouTube direct stream URL: $directUrl');

      // Use your existing DownloadManager to download as .mp4
      final localPath = await DownloadManager.download(
        directUrl,
        name: fileName ?? 'yt_${video.id}.mp4',
        onDownload: onProgress,
        isOpen: false,
      );

      return localPath;
    } catch (e) {
      print('❌ Error downloading YouTube video: $e');
      return null;
    }
  }

  Future<void> dispose() async {
    _yt.close();
  }
}
