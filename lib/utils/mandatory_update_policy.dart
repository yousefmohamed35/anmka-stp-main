import '../models/app_config.dart';
import 'app_version_compare.dart';

/// Decides when the client must block the UI until the user updates.
abstract final class MandatoryUpdatePolicy {
  MandatoryUpdatePolicy._();

  /// True if the installed app must not proceed (hard gate).
  ///
  /// Rules (evaluated in order):
  /// 1. If installed version is **strictly less than** [AppConfig.minVersion] → block.
  ///    Comparison uses `major.minor.patch`, then the integer after `+` if present (e.g. `1.0.0+5`).
  /// 2. If [AppConfig.forceUpdate] is true **and** installed version is **strictly less than**
  ///    [AppConfig.version] (latest from the server, same format) → block.
  static bool shouldBlock({
    required String installedVersion,
    required AppConfig config,
  }) {
    if (AppVersionCompare.compare(installedVersion, config.minVersion) < 0) {
      return true;
    }
    if (config.forceUpdate &&
        AppVersionCompare.compare(installedVersion, config.version) < 0) {
      return true;
    }
    return false;
  }

  /// Highest bar between [AppConfig.minVersion] and [AppConfig.version] (semver).
  static String requiredVersionLabel(AppConfig config) {
    return AppVersionCompare.compare(config.minVersion, config.version) >= 0
        ? config.minVersion
        : config.version;
  }
}
