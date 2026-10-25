import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zakoway/core/services/app_preferences.dart';
import 'package:zakoway/core/services/display_mode_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DisplayModeService & AppPreferences', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await AppPreferences.init();
    });

    test('save and read display mode preference', () async {
      expect(AppPreferences.getDisplayMode(), isNull);

      await AppPreferences.saveDisplayMode('DisplayMode(id: 1, width: 1080, height: 2400, refreshRate: 120.0)');
      expect(
        AppPreferences.getDisplayMode(),
        'DisplayMode(id: 1, width: 1080, height: 2400, refreshRate: 120.0)',
      );
    });

    test('non-Android platform returns empty supported modes gracefully', () async {
      final modes = await DisplayModeService.getSupportedModes();
      expect(modes, isEmpty);

      final active = await DisplayModeService.getActiveMode();
      expect(active, isNull);

      final preferred = await DisplayModeService.getPreferredMode();
      expect(preferred, isNull);
    });
  });
}
