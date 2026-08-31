import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vision_wear/core/theme/app_theme.dart';
import 'package:vision_wear/models/app_settings.dart';

/// WCAG 2.1 relative luminance.
double _luminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) +
      0.7152 * channel(c.g) +
      0.0722 * channel(c.b);
}

/// WCAG contrast ratio, 1.0 (identical) to 21.0 (black on white).
double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final lighter = math.max(la, lb);
  final darker = math.min(la, lb);
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  group('AppTheme colour contrast', () {
    // This app is for people with limited or no sight. A label that is
    // technically present but unreadable is a bug, and it has shipped here
    // before: a gold button whose label defaulted to the same gold.
    //
    // 4.5:1 is the WCAG AA threshold for body text. 3:1 is the threshold for
    // large text (>=18pt bold / 24pt regular), which every button label in
    // this app clears at 20pt semibold.
    const bodyMinimum = 4.5;
    const largeTextMinimum = 3.0;

    for (final (name, theme) in [
      ('light', AppTheme.lightTheme),
      ('dark', AppTheme.darkTheme),
    ]) {
      final scheme = theme.colorScheme;
      final app = theme.extension<AppColors>()!;

      test('$name: primary button label is readable on its fill', () {
        expect(
          _contrast(scheme.onPrimary, scheme.primary),
          greaterThanOrEqualTo(bodyMinimum),
          reason: 'gold fill needs dark text, not the scheme default',
        );
      });

      test('$name: semantic fills carry a readable label', () {
        expect(_contrast(app.onAccent, app.accent),
            greaterThanOrEqualTo(largeTextMinimum));
        expect(_contrast(app.onWarning, app.warning),
            greaterThanOrEqualTo(largeTextMinimum));
        expect(_contrast(app.onDanger, app.danger),
            greaterThanOrEqualTo(largeTextMinimum));
      });

      test('$name: accent is readable as text on the app surface', () {
        // accent is used for section headers and status text, not only fills,
        // so it has to clear the body threshold against the surface.
        expect(
          _contrast(app.accent, scheme.surface),
          greaterThanOrEqualTo(bodyMinimum),
          reason: 'gold-on-white fails here unless the light theme darkens it',
        );
      });

      test('$name: warning is readable as text on the app surface', () {
        // Used for the "paused" dot and the model-loading chip, which are
        // small text rather than fills.
        expect(_contrast(app.warning, scheme.surface),
            greaterThanOrEqualTo(bodyMinimum));
      });

      test('$name: body text is readable on the surface', () {
        expect(_contrast(scheme.onSurface, scheme.surface),
            greaterThanOrEqualTo(bodyMinimum));
      });

      test('$name: overlay text is readable on the camera scrim', () {
        // The scrim is translucent black over live video; compositing it on
        // black is the best case, and even that must pass.
        final scrim = Color.alphaBlend(app.overlayScrim, app.letterbox);
        expect(_contrast(app.onOverlay, scrim),
            greaterThanOrEqualTo(bodyMinimum));
      });

      test('$name: warning is distinguishable from the gold primary', () {
        // Amber warnings used to sit almost on top of the brand gold, which
        // made a caution state read as an ordinary one.
        expect(
          _contrast(app.warning, scheme.primary),
          greaterThan(1.8),
          reason: 'warning must not be mistakable for the brand colour',
        );
      });
    }
  });

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
