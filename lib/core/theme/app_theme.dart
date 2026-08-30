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
  });

  /// Brand teal. Used for "live"/active affordances.
  final Color accent;
  final Color onAccent;

  /// Caution — paused states, approaching obstacles, reconnecting.
  final Color warning;
  final Color onWarning;

  /// Immediate hazard.
  final Color danger;
  final Color onDanger;

  final Color success;
  final Color info;

  /// De-emphasised body text. Replaces the scattered `Colors.white70`.
  final Color muted;

  /// Backing for chips and panels drawn *on top of the camera feed*. These
  /// stay dark in both themes: the backdrop is live video, not the app
  /// surface, so a light scrim would be unreadable outdoors.
  final Color overlayScrim;
  final Color onOverlay;

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

  // ── Brand seed palette ────────────────────────────────────────────────────
  // These are the source colours the schemes are derived from. Widgets should
  // not reference them directly — use `context.appColors` or `context.colors`
  // so the value follows the active theme.

  static const Color brandPrimary = Color(0xFF1A73E8);
  static const Color brandAccent = Color(0xFF00C9A7);
  static const Color brandDanger = Color(0xFFE53935);
  static const Color brandWarning = Color(0xFFFFB300);

  // Dark-theme surfaces, kept deliberately near-black. This app is used
  // outdoors and at night by people who may have light sensitivity.
  static const Color _surfaceDark = Color(0xFF121212);
  static const Color _cardDark = Color(0xFF1E1E1E);

  static const Color _surfaceLight = Color(0xFFF7F8FA);
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
    accent: brandAccent,
    onAccent: Color(0xFF00281F),
    warning: brandWarning,
    onWarning: Color(0xFF2B1D00),
    danger: brandDanger,
    onDanger: Colors.white,
    success: Color(0xFF43A047),
    info: Color(0xFF64B5F6),
    muted: Color(0xB3FFFFFF), // white @ 70%
    overlayScrim: Color(0xB3000000),
    onOverlay: Colors.white,
  );

  static const AppColors _lightColors = AppColors(
    // Darkened against white so it still passes contrast as text/iconography.
    accent: Color(0xFF00796B),
    onAccent: Colors.white,
    warning: Color(0xFF9A6700),
    onWarning: Colors.white,
    danger: Color(0xFFC62828),
    onDanger: Colors.white,
    success: Color(0xFF2E7D32),
    info: Color(0xFF1565C0),
    muted: Color(0x99000000), // black @ 60%
    // Still dark: this sits on live video in both themes.
    overlayScrim: Color(0xB3000000),
    onOverlay: Colors.white,
  );

  static ThemeData get darkTheme => _build(Brightness.dark);
  static ThemeData get lightTheme => _build(Brightness.light);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final appColors = isDark ? _darkColors : _lightColors;
    final surface = isDark ? _surfaceDark : _surfaceLight;
    final card = isDark ? _cardDark : _cardLight;

    final scheme = ColorScheme.fromSeed(
      seedColor: brandPrimary,
      brightness: brightness,
      primary: brandPrimary,
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
        centerTitle: true,
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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radius),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(double.infinity, _minButtonHeight),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
          textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_radius),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(double.infinity, _minButtonHeight),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_radius),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: card,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
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
          (states) => states.contains(WidgetState.selected)
              ? appColors.accent
              : null,
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
    );
  }
}
