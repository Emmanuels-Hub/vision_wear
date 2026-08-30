import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vision_wear/core/theme/app_theme.dart';
import 'package:vision_wear/models/app_settings.dart';

void main() {
  group('AppTheme', () {
    test('both themes register the AppColors extension', () {
      // context.appColors uses a null assertion, so a missing registration
      // would crash on the first frame rather than fail gracefully.
      expect(AppTheme.lightTheme.extension<AppColors>(), isNotNull);
      expect(AppTheme.darkTheme.extension<AppColors>(), isNotNull);
    });

    test('themes carry the correct brightness', () {
      expect(AppTheme.lightTheme.brightness, Brightness.light);
      expect(AppTheme.darkTheme.brightness, Brightness.dark);
      expect(AppTheme.lightTheme.colorScheme.brightness, Brightness.light);
      expect(AppTheme.darkTheme.colorScheme.brightness, Brightness.dark);
    });

    test('semantic colours differ between light and dark', () {
      final light = AppTheme.lightTheme.extension<AppColors>()!;
      final dark = AppTheme.darkTheme.extension<AppColors>()!;

      // If these matched, one of the two themes would be unreadable.
      expect(light.muted, isNot(equals(dark.muted)));
      expect(light.accent, isNot(equals(dark.accent)));
    });

    test('overlay colours stay fixed across themes', () {
      final light = AppTheme.lightTheme.extension<AppColors>()!;
      final dark = AppTheme.darkTheme.extension<AppColors>()!;

      // These are painted on live video, not on an app surface, so they must
      // NOT follow the theme.
      expect(light.overlayScrim, equals(dark.overlayScrim));
      expect(light.onOverlay, equals(dark.onOverlay));
    });

    test('lerp produces a valid intermediate', () {
      final light = AppTheme.lightTheme.extension<AppColors>()!;
      final dark = AppTheme.darkTheme.extension<AppColors>()!;
      final mid = light.lerp(dark, 0.5);

      expect(mid, isA<AppColors>());
      expect(mid.accent, isNot(equals(light.accent)));
    });

    testWidgets('context.appColors resolves inside a themed subtree',
        (tester) async {
      late AppColors resolved;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Builder(
            builder: (context) {
              resolved = context.appColors;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(resolved.accent, AppTheme.lightTheme.extension<AppColors>()!.accent);
    });
  });

  group('AppSettings.themeMode', () {
    test('defaults to system', () {
      expect(const AppSettings().themeMode, ThemeMode.system);
    });

    test('round-trips through JSON', () {
      for (final mode in ThemeMode.values) {
        final restored = AppSettings.fromJson(
          const AppSettings().copyWith(themeMode: mode).toJson(),
        );
        expect(restored.themeMode, mode, reason: 'failed for $mode');
      }
    });

    test('falls back to the default on an unknown stored value', () {
      final json = const AppSettings().toJson()..['themeMode'] = 'chartreuse';
      expect(AppSettings.fromJson(json).themeMode, ThemeMode.system);
    });
  });
}
