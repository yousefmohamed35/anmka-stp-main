/// Compares dotted version strings including optional build after `+`
/// (e.g. `1.2.3`, `1.2.3+45`, `1.0.0-beta+5` → core `1.0.0`, build `5`).
abstract final class AppVersionCompare {
  AppVersionCompare._();

  /// Parses `major.minor.patch` from the segment before the first `+` (pre-release stripped).
  static List<int> parseCore(String raw) {
    final core = raw.split('+').first.split('-').first.trim();
    final segments = core.split('.');
    final out = <int>[];
    for (var i = 0; i < 3; i++) {
      if (i < segments.length) {
        out.add(int.tryParse(segments[i].trim()) ?? 0);
      } else {
        out.add(0);
      }
    }
    return out;
  }

  /// Build number after the first `+` (Flutter/pub style). Missing `+` → `0`.
  static int parseBuild(String raw) {
    final parts = raw.split('+');
    if (parts.length < 2) return 0;
    final buildPart = parts[1].split('-').first.trim();
    return int.tryParse(buildPart) ?? 0;
  }

  /// Installed app string aligned with API `version` / `min_version` format (`name+build`).
  static String composeInstalledVersion({
    required String versionName,
    required String buildNumber,
  }) {
    final v = versionName.trim();
    final b = buildNumber.trim();
    if (v.contains('+')) return v;
    if (b.isEmpty || b == '0') return v;
    return '$v+$b';
  }

  /// Returns negative if [a] < [b], zero if equal, positive if [a] > [b].
  static int compare(String a, String b) {
    final pa = parseCore(a);
    final pb = parseCore(b);
    for (var i = 0; i < 3; i++) {
      final c = pa[i].compareTo(pb[i]);
      if (c != 0) return c;
    }
    final ba = parseBuild(a);
    final bb = parseBuild(b);
    return ba.compareTo(bb);
  }
}
