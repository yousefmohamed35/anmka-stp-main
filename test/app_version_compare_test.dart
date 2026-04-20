import 'package:flutter_test/flutter_test.dart';
import 'package:educational_app/utils/app_version_compare.dart';

void main() {
  test('compare core when build absent', () {
    expect(AppVersionCompare.compare('1.0.0', '1.0.1'), lessThan(0));
    expect(AppVersionCompare.compare('1.0.1', '1.0.0'), greaterThan(0));
  });

  test('compare build after equal core', () {
    expect(AppVersionCompare.compare('1.0.0+5', '1.0.0+8'), lessThan(0));
    expect(AppVersionCompare.compare('1.0.0+8', '1.0.0+8'), 0);
    expect(AppVersionCompare.compare('1.0.0', '1.0.0+1'), lessThan(0));
    expect(AppVersionCompare.compare('1.0.0+1', '1.0.0'), greaterThan(0));
  });

  test('composeInstalledVersion', () {
    expect(
      AppVersionCompare.composeInstalledVersion(
        versionName: '1.0.0',
        buildNumber: '8',
      ),
      '1.0.0+8',
    );
    expect(
      AppVersionCompare.composeInstalledVersion(
        versionName: '1.0.0',
        buildNumber: '0',
      ),
      '1.0.0',
    );
    expect(
      AppVersionCompare.composeInstalledVersion(
        versionName: '1.0.0',
        buildNumber: '',
      ),
      '1.0.0',
    );
  });
}
