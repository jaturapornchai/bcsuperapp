import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/theme/app_theme.dart';

void main() {
  test('business theme presets: unknown code falls back, apply repaints brand', () {
    // Codes must match backend THEME_PRESETS (admin_routes.rs).
    expect(ThemePreset.all.map((p) => p.code), [
      'emerald',
      'finance_blue',
      'restaurant_orange',
      'clinic_teal',
      'retail_red',
      'factory_amber',
      'beauty_pink',
    ]);
    expect(ThemePreset.byCode('nope').code, 'emerald');
    expect(ThemePreset.byCode(null).code, 'emerald');

    AppTheme.applyPreset('finance_blue');
    expect(AppTheme.brandPrimary, ThemePreset.byCode('finance_blue').primary);
    AppTheme.applyPreset('emerald');
    expect(AppTheme.brandPrimary, ThemePreset.all.first.primary);
  });
}
