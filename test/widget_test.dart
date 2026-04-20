// This is a basic Flutter widget test.

import 'package:flutter_test/flutter_test.dart';
import 'package:educational_app/main.dart';
import 'package:educational_app/core/config/app_config_provider.dart';
import 'package:educational_app/core/config/theme_provider.dart';

void main() {
  testWidgets('App starts correctly', (WidgetTester tester) async {
    final configProvider = AppConfigProvider();
    final themeProvider = ThemeProvider.instance;
    await themeProvider.ensureInitialized();
    await configProvider.initialize();

    await tester.pumpWidget(EducationalApp(
      configProvider: configProvider,
      themeProvider: themeProvider,
    ));

    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  });
}
