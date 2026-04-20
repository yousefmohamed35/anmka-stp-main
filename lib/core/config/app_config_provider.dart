import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../models/app_config.dart';
import '../../services/app_config_service.dart';
import '../../utils/app_version_compare.dart';
import '../../utils/mandatory_update_policy.dart';

/// Provider to hold app configuration globally
class AppConfigProvider extends ChangeNotifier {
  AppConfig? _config;
  bool _isLoading = true;
  String? _error;
  PackageInfo? _packageInfo;

  AppConfig? get config => _config;
  bool get isLoading => _isLoading;
  String? get error => _error;
  /// Same shape as API versions, e.g. `1.0.0+5` from [PackageInfo].
  String? get installedAppVersion => _packageInfo == null
      ? null
      : AppVersionCompare.composeInstalledVersion(
          versionName: _packageInfo!.version,
          buildNumber: _packageInfo!.buildNumber,
        );

  /// When true, the app shows a full-screen mandatory update gate instead of routes.
  bool get isMandatoryUpdateRequired {
    if (_isLoading || _config == null || _packageInfo == null) return false;
    return MandatoryUpdatePolicy.shouldBlock(
      installedVersion: installedAppVersion!,
      config: _config!,
    );
  }

  /// Initialize and fetch app configuration
  Future<void> initialize() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _packageInfo = await PackageInfo.fromPlatform();
    } catch (e) {
      _error = e.toString();
    }
    try {
      _config = await AppConfigService.instance.fetchAppConfig();
    } catch (e) {
      _error = e.toString();
      _config = await AppConfigService.instance.getAppConfig();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Refresh configuration
  Future<void> refresh() async {
    AppConfigService.instance.clearCache();
    await initialize();
  }
}

