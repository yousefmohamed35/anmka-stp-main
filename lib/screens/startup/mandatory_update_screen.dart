import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/default_store_urls.dart';
import '../../l10n/app_localizations.dart';
import '../../models/app_config.dart';
import '../../utils/mandatory_update_policy.dart';

/// Full-screen gate: user cannot use the app until they update.
class MandatoryUpdateScreen extends StatelessWidget {
  const MandatoryUpdateScreen({
    super.key,
    required this.config,
    required this.installedVersion,
  });

  final AppConfig config;
  final String installedVersion;

  String? _storeUrl() {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return config.androidStoreUrl ??
            config.updateUrl ??
            kDefaultAndroidPlayStoreUrl;
      case TargetPlatform.iOS:
        return config.iosStoreUrl ?? config.updateUrl;
      default:
        return config.updateUrl;
    }
  }

  Future<void> _openStore(BuildContext context) async {
    final url = _storeUrl();
    final loc = AppLocalizations.of(context)!;
    if (url == null || url.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.mandatoryUpdateStoreMissing)),
      );
      return;
    }
    final uri = Uri.tryParse(url);
    if (uri == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.mandatoryUpdateStoreMissing)),
      );
      return;
    }
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.mandatoryUpdateStoreMissing)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final requiredLabel = MandatoryUpdatePolicy.requiredVersionLabel(config);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Icon(Icons.system_update_rounded,
                  size: 72, color: theme.colorScheme.primary),
              const SizedBox(height: 24),
              Text(
                loc.mandatoryUpdateTitle,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                loc.mandatoryUpdateBody(installedVersion, requiredLabel),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              FilledButton(
                onPressed: () => _openStore(context),
                child: Text(loc.updateNow),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
