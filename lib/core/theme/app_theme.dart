import 'package:flutter/material.dart';

/// Semantic colours that Material's [ColorScheme] has no slot for.
///
/// These are resolved per-brightness and read through `context.appColors`, so
/// no widget needs to know whether the app is currently light or dark. Adding a
/// colour here is what makes it themeable; a `const Color(...)` written inline
/// in a widget is not.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.accent,
    required this.onAccent,
    required this.warning,
    required this.onWarning,
    required this.danger,
    required this.onDanger,
    required this.success,
    required this.info,
    required this.muted,
    required this.overlayScrim,
    required this.onOverlay,
    required this.letterbox,
  });

  /// Gold, adjusted per theme so it stays legible as text and iconography.
  /// This is the brand colour; [ColorScheme.primary] carries the same family
  /// for filled surfaces.
  final Color accent;
  final Color onAccent;

  /// Caution — paused states, approaching obstacles, reconnecting. Deliberately
  /// orange rather than amber: amber sits too close to the gold primary to be
  /// distinguishable at a glance, which defeats the point of a warning colour.
  final Color warning;
  final Color onWarning;

  /// Immediate hazard.
  final Color danger;
  final Color onDanger;

  final Color success;
  final Color info;

  /// De-emphasised body text.
  final Color muted;

  /// Backing for chips and panels drawn *on top of the camera feed*. These
  /// stay dark in both themes: the backdrop is live video, not the app
  /// surface, so a light scrim would be unreadable outdoors.
  final Color overlayScrim;
  final Color onOverlay;

  /// Fills the gap around a camera frame that does not match the widget's
  /// aspect ratio. Black in both themes on purpose — anything lighter glows
  /// around the video and hurts in the dark — but a token rather than an
  /// inline `Colors.black` so it is named and searchable.
  final Color letterbox;

  @override
  AppColors copyWith({
    Color? accent,
    Color? onAccent,
    Color? warning,
    Color? onWarning,
    Color? danger,
    Color? onDanger,
    Color? success,
    Color? info,
    Color? muted,
    Color? overlayScrim,
    Color? onOverlay,
    Color? letterbox,
  }) {
    return AppColors(
      accent: accent ?? this.accent,
      onAccent: onAccent ?? this.onAccent,
      warning: warning ?? this.warning,
      onWarning: onWarning ?? this.onWarning,
      danger: danger ?? this.danger,
      onDanger: onDanger ?? this.onDanger,
      success: success ?? this.success,
      info: info ?? this.info,
      muted: muted ?? this.muted,
      overlayScrim: overlayScrim ?? this.overlayScrim,
      onOverlay: onOverlay ?? this.onOverlay,
      letterbox: letterbox ?? this.letterbox,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      accent: Color.lerp(accent, other.accent, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      onWarning: Color.lerp(onWarning, other.onWarning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      onDanger: Color.lerp(onDanger, other.onDanger, t)!,
      success: Color.lerp(success, other.success, t)!,
      info: Color.lerp(info, other.info, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      overlayScrim: Color.lerp(overlayScrim, other.overlayScrim, t)!,
      onOverlay: Color.lerp(onOverlay, other.onOverlay, t)!,
      letterbox: Color.lerp(letterbox, other.letterbox, t)!,
    );
  }
}

/// Ergonomic access: `context.appColors.warning`.
extension AppColorsX on BuildContext {
  AppColors get appColors => Theme.of(this).extension<AppColors>()!;
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get texts => Theme.of(this).textTheme;
}

class AppTheme {
  AppTheme._();

  // ── Brand palette ─────────────────────────────────────────────────────────
  //
  // Gold is a light colour, which constrains how it can be used. It works as a
  // *fill* with dark text on top, and it works as text on a dark surface — but
  // gold text on white is around 2:1 contrast, well under the 4.5:1 the users
  // of this app need. So the palette carries three golds: one for fills, a
  // brighter one for text on dark, and a deeper one for text on light.
  //
  // Widgets should not reference these directly — use `context.appColors` or
  // `context.colors` so the value follows the active theme.

  /// Filled surfaces (primary buttons, selected states) in both themes.
  static const Color brandGold = Color(0xFFD4AF37);

  /// Text and icons drawn on [brandGold]. Near-black, ~9:1 against the fill.
  static const Color onGold = Color(0xFF241B00);

  /// Gold for text and icons on a dark surface.
  static const Color goldLight = Color(0xFFF0CE5A);

  /// Gold for text and icons on a light surface. Dark enough to read on white.
  static const Color goldDeep = Color(0xFF7A5E10);

  static const Color brandDanger = Color(0xFFE53935);

  // Dark-theme surfaces, kept deliberately near-black. This app is used
  // outdoors and at night by people who may have light sensitivity.
  static const Color _surfaceDark = Color(0xFF121212);
  static const Color _cardDark = Color(0xFF1E1E1E);

  static const Color _surfaceLight = Color(0xFFFAF8F3);
  static const Color _cardLight = Color(0xFFFFFFFF);

  /// Shared, brightness-independent shape and sizing.
  ///
  /// The large minimum tap targets are an accessibility requirement, not a
  /// style choice: the primary users cannot see the button they are aiming at.
  static const double _minButtonHeight = 64;
  static const double _radius = 16;

  static const TextTheme _textTheme = TextTheme(
    headlineLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
    headlineMedium: TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
    headlineSmall: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
    titleLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
    titleMedium: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
    bodyLarge: TextStyle(fontSize: 18, height: 1.5),
    bodyMedium: TextStyle(fontSize: 16, height: 1.4),
    bodySmall: TextStyle(fontSize: 14, height: 1.4),
    labelLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
    labelSmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
  );

  static const AppColors _darkColors = AppColors(
    accent: goldLight,
    onAccent: onGold,
    warning: Color(0xFFFF9800),
    onWarning: Color(0xFF2B1500),
    danger: brandDanger,
    onDanger: Colors.white,
    success: Color(0xFF43A047),
    info: Color(0xFF64B5F6),
    muted: Color(0xB3FFFFFF), // white @ 70%
    overlayScrim: Color(0xB3000000),
    onOverlay: Colors.white,
    letterbox: Colors.black,
  );

  static const AppColors _lightColors = AppColors(
    accent: goldDeep,
    onAccent: Colors.white,
    warning: Color(0xFFB35309),
    onWarning: Colors.white,
    danger: Color(0xFFC62828),
    onDanger: Colors.white,
    success: Color(0xFF2E7D32),
    info: Color(0xFF1565C0),
    muted: Color(0x99000000), // black @ 60%
    // Still dark: these sit on live video in both themes.
    overlayScrim: Color(0xB3000000),
    onOverlay: Colors.white,
    letterbox: Colors.black,
  );

  static ThemeData get darkTheme => _build(Brightness.dark);
  static ThemeData get lightTheme => _build(Brightness.light);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final appColors = isDark ? _darkColors : _lightColors;
    final surface = isDark ? _surfaceDark : _surfaceLight;
    final card = isDark ? _cardDark : _cardLight;

    final scheme = ColorScheme.fromSeed(
      seedColor: brandGold,
      brightness: brightness,
      primary: brandGold,
      // Pinned rather than derived: `fromSeed` picks white here, which is
      // unreadable on gold. Every filled primary button depends on this.
      onPrimary: onGold,
      secondary: appColors.accent,
      error: appColors.danger,
      surface: surface,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: surface,
      fontFamily: 'Roboto',
      textTheme: _textTheme,
      extensions: <ThemeExtension<dynamic>>[appColors],
    );

    return base.copyWith(
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        backgroundColor: surface,
        foregroundColor: scheme.onSurface,
        titleTextStyle: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        color: card,
        elevation: isDark ? 2 : 1,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radius),
        ),
      ),
      // Both colours are pinned. Setting only the background leaves the label
      // at the M3 default of `colorScheme.primary` — the same gold as the fill,
      // which is exactly the invisible-label bug this app already hit once.
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          disabledBackgroundColor: scheme.onSurface.withValues(alpha: 0.12),
          disabledForegroundColor: scheme.onSurface.withValues(alpha: 0.38),
          minimumSize: const Size(double.infinity, _minButtonHeight),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
          textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_radius),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(double.infinity, _minButtonHeight),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_radius),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: appColors.accent,
          side: BorderSide(color: appColors.accent, width: 1.5),
          minimumSize: const Size(double.infinity, _minButtonHeight),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_radius),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: appColors.accent),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: scheme.onSurface),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: card,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: appColors.accent, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 18,
        ),
        labelStyle: const TextStyle(fontSize: 16),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
        textColor: scheme.onSurface,
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        contentTextStyle: const TextStyle(fontSize: 16),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: appColors.accent,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? appColors.accent : null,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? appColors.accent.withValues(alpha: 0.4)
              : null,
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: appColors.accent,
        thumbColor: appColors.accent,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? scheme.primary
                : null,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? scheme.onPrimary
                : scheme.onSurface,
          ),
        ),
      ),
    );
  }
}
