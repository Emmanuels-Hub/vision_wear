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
    required this.brand,
    required this.onBrand,
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

  /// The interactive tint for text and icons drawn *on the app surface* —
  /// links, selected states, control accents. A blue that is deliberately
  /// resolved light-on-dark / dark-on-light so it always clears 4.5:1.
  /// [ColorScheme.primary] carries the same family for filled surfaces.
  final Color accent;
  final Color onAccent;

  /// Gold. The brand's warm signature, used sparingly: section headers, the
  /// splash mark, focus rings. It is *not* an action colour — that is
  /// [ColorScheme.primary]. Kept off the light theme's body-text path because
  /// a legible gold on white is unavoidably a dark mustard.
  final Color brand;
  final Color onBrand;

  /// Caution — paused states, approaching obstacles, reconnecting. Amber, and
  /// far enough from both the blue primary and the red danger to be told
  /// apart at a glance by someone who is not looking straight at it.
  final Color warning;
  final Color onWarning;

  /// Immediate hazard.
  final Color danger;
  final Color onDanger;

  /// Confirmed-good states — camera connected, model ready.
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
    Color? brand,
    Color? onBrand,
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
      brand: brand ?? this.brand,
      onBrand: onBrand ?? this.onBrand,
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
      brand: Color.lerp(brand, other.brand, t)!,
      onBrand: Color.lerp(onBrand, other.onBrand, t)!,
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

/// The neutral surface ramp for one brightness.
///
/// Pinned by hand rather than derived by `ColorScheme.fromSeed`, which tinted
/// every container toward the seed hue and left the home screen a wall of
/// muddy buttons. The ramp here is a near-neutral grey with a faint cool cast
/// so it sits under the blue primary without arguing with it.
@immutable
class _Surfaces {
  const _Surfaces({
    required this.surface,
    required this.surfaceDim,
    required this.surfaceBright,
    required this.containerLowest,
    required this.containerLow,
    required this.container,
    required this.containerHigh,
    required this.containerHighest,
    required this.onSurface,
    required this.onSurfaceVariant,
    required this.outline,
    required this.outlineVariant,
    required this.inverseSurface,
    required this.onInverseSurface,
    required this.primaryContainer,
    required this.onPrimaryContainer,
  });

  final Color surface;
  final Color surfaceDim;
  final Color surfaceBright;
  final Color containerLowest;
  final Color containerLow;
  final Color container;
  final Color containerHigh;
  final Color containerHighest;
  final Color onSurface;
  final Color onSurfaceVariant;
  final Color outline;
  final Color outlineVariant;
  final Color inverseSurface;
  final Color onInverseSurface;
  final Color primaryContainer;
  final Color onPrimaryContainer;
}

class AppTheme {
  AppTheme._();

  // ── Brand palette ─────────────────────────────────────────────────────────
  //
  // Blue is the action colour. It is the one hue that holds high contrast on
  // both a near-black and a near-white surface, it reads as "interactive"
  // everywhere, and it is unmistakable next to the amber warning and the red
  // danger states — which matters more here than in most apps.
  //
  // Gold stays as the brand's warm accent, but only where it can be legible:
  // large section headers and the splash mark. Widgets should not reference
  // these constants directly — use `context.appColors` or `context.colors` so
  // the value follows the active theme.

  /// Filled actions (primary buttons, selected states) in both themes.
  /// White text on this is ~5.2:1.
  static const Color brandBlue = Color(0xFF2563EB);

  /// Gold for a filled surface with dark text on top (rare — mostly the
  /// splash mark's ring).
  static const Color brandGold = Color(0xFFD4AF37);
  static const Color onGold = Color(0xFF241B00);

  static const Color brandDanger = Color(0xFFF04438);

  // Colours for the detection overlay. These paint on top of live video in
  // either theme, so they are fixed and vivid rather than theme-resolved —
  // the same reason [AppColors.overlayScrim] is fixed.
  static const Color visionSafe = Color(0xFF38BDF8);
  static const Color visionHazard = Color(0xFFF59E0B);
  static const Color visionDanger = Color(0xFFFB4B4B);

  // Dark-theme surfaces, kept deliberately near-black with a faint cool cast.
  // This app is used outdoors and at night by people who may have light
  // sensitivity.
  static const _Surfaces _darkSurfaces = _Surfaces(
    surface: Color(0xFF0F1216),
    surfaceDim: Color(0xFF0B0E12),
    surfaceBright: Color(0xFF2A303B),
    containerLowest: Color(0xFF0A0C10),
    containerLow: Color(0xFF151A20),
    container: Color(0xFF1A1F26),
    containerHigh: Color(0xFF222831),
    containerHighest: Color(0xFF2B323D),
    onSurface: Color(0xFFECEEF2),
    onSurfaceVariant: Color(0xFFAEB8C4),
    outline: Color(0xFF4A5360),
    outlineVariant: Color(0xFF2C333D),
    inverseSurface: Color(0xFFECEEF2),
    onInverseSurface: Color(0xFF1A1F26),
    primaryContainer: Color(0xFF1E3A6E),
    onPrimaryContainer: Color(0xFFD6E4FF),
  );

  static const _Surfaces _lightSurfaces = _Surfaces(
    surface: Color(0xFFF4F6F9),
    surfaceDim: Color(0xFFDCE0E7),
    surfaceBright: Color(0xFFFFFFFF),
    containerLowest: Color(0xFFFFFFFF),
    containerLow: Color(0xFFFCFDFE),
    container: Color(0xFFFFFFFF),
    containerHigh: Color(0xFFEDF0F4),
    containerHighest: Color(0xFFE4E8EF),
    onSurface: Color(0xFF171A1F),
    onSurfaceVariant: Color(0xFF515964),
    outline: Color(0xFFBCC4CF),
    outlineVariant: Color(0xFFDEE3EA),
    inverseSurface: Color(0xFF2B323D),
    onInverseSurface: Color(0xFFF1F3F6),
    primaryContainer: Color(0xFFDCE7FF),
    onPrimaryContainer: Color(0xFF0A2C6B),
  );

  /// Shared, brightness-independent shape and sizing.
  ///
  /// The large minimum tap targets are an accessibility requirement, not a
  /// style choice: the primary users cannot see the button they are aiming at.
  static const double _minButtonHeight = 64;
  static const double _radius = 16;

  static const TextTheme _textTheme = TextTheme(
    headlineLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, height: 1.2),
    headlineMedium: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, height: 1.25),
    headlineSmall: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, height: 1.3),
    titleLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
    titleMedium: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
    bodyLarge: TextStyle(fontSize: 18, height: 1.5),
    bodyMedium: TextStyle(fontSize: 16, height: 1.4),
    bodySmall: TextStyle(fontSize: 14, height: 1.4),
    labelLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
    labelSmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, letterSpacing: 0.4),
  );

  static const AppColors _darkColors = AppColors(
    accent: Color(0xFF7FB0FF), // ~9:1 on the dark surface
    onAccent: Color(0xFF06192E),
    brand: Color(0xFFEBC55A), // gold, ~10:1 on the dark surface
    onBrand: onGold,
    warning: Color(0xFFFF8A00), // amber — legible as text and as a fill
    onWarning: Color(0xFF2A1400),
    danger: brandDanger,
    onDanger: Colors.white,
    success: Color(0xFF34D399),
    info: Color(0xFF7FB0FF),
    muted: Color(0xFF9AA6B4), // ~6:1 on the dark surface
    overlayScrim: Color(0xB3000000),
    onOverlay: Colors.white,
    letterbox: Colors.black,
  );

  static const AppColors _lightColors = AppColors(
    accent: Color(0xFF1B4DD1), // ~6.5:1 on the light surface
    onAccent: Colors.white,
    brand: Color(0xFF8A6A00), // antique gold, ~4.8:1 on the light surface
    onBrand: Colors.white,
    warning: Color(0xFFB5470B), // burnt orange, distinct from the red danger
    onWarning: Colors.white,
    danger: Color(0xFFC5221F),
    onDanger: Colors.white,
    success: Color(0xFF0E7A3B),
    info: Color(0xFF1B4DD1),
    muted: Color(0xFF5A6472), // ~5:1 on the light surface
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
    final s = isDark ? _darkSurfaces : _lightSurfaces;

    // Start from a seeded scheme for the odd corners (inversePrimary, etc.)
    // then pin every slot the UI actually reads, so nothing is left tinted
    // toward the seed hue.
    final scheme = ColorScheme.fromSeed(
      seedColor: brandBlue,
      brightness: brightness,
    ).copyWith(
      primary: brandBlue,
      onPrimary: Colors.white,
      primaryContainer: s.primaryContainer,
      onPrimaryContainer: s.onPrimaryContainer,
      secondary: appColors.brand,
      onSecondary: appColors.onBrand,
      tertiary: appColors.accent,
      onTertiary: appColors.onAccent,
      error: appColors.danger,
      onError: Colors.white,
      surface: s.surface,
      onSurface: s.onSurface,
      onSurfaceVariant: s.onSurfaceVariant,
      surfaceDim: s.surfaceDim,
      surfaceBright: s.surfaceBright,
      surfaceContainerLowest: s.containerLowest,
      surfaceContainerLow: s.containerLow,
      surfaceContainer: s.container,
      surfaceContainerHigh: s.containerHigh,
      surfaceContainerHighest: s.containerHighest,
      outline: s.outline,
      outlineVariant: s.outlineVariant,
      inverseSurface: s.inverseSurface,
      onInverseSurface: s.onInverseSurface,
      shadow: Colors.black,
      scrim: Colors.black,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: s.surface,
      canvasColor: s.surface,
      fontFamily: 'Roboto',
      textTheme: _textTheme,
      // The focus ring is the one place gold does interactive duty: it reads
      // as "the app is paying attention to this control" without competing
      // with the blue that means "activate me".
      focusColor: appColors.brand.withValues(alpha: isDark ? 0.30 : 0.22),
      splashColor: scheme.primary.withValues(alpha: 0.12),
      highlightColor: scheme.primary.withValues(alpha: 0.08),
      extensions: <ThemeExtension<dynamic>>[appColors],
    );

    return base.copyWith(
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: s.surface,
        foregroundColor: scheme.onSurface,
        titleTextStyle: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        color: s.container,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.black.withValues(alpha: isDark ? 0.4 : 0.12),
        elevation: isDark ? 0 : 1,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radius),
          side: BorderSide(color: s.outlineVariant),
        ),
      ),
      // Both colours are pinned. Setting only the background leaves the label
      // at the M3 default of `colorScheme.primary` — which used to be the same
      // colour as the fill, the invisible-label bug this app hit once.
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          disabledBackgroundColor: scheme.onSurface.withValues(alpha: 0.12),
          disabledForegroundColor: scheme.onSurface.withValues(alpha: 0.38),
          elevation: 0,
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
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          minimumSize: const Size(double.infinity, _minButtonHeight),
          textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
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
          textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_radius),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: appColors.accent,
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: scheme.onSurface),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: s.containerHigh,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: s.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: s.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 18,
        ),
        prefixIconColor: s.onSurfaceVariant,
        labelStyle: TextStyle(fontSize: 16, color: s.onSurfaceVariant),
        hintStyle: TextStyle(color: s.onSurfaceVariant.withValues(alpha: 0.7)),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
        textColor: scheme.onSurface,
        subtitleTextStyle: TextStyle(
          fontSize: 14,
          height: 1.35,
          color: scheme.onSurfaceVariant,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: s.containerHigh,
        side: BorderSide(color: s.outlineVariant),
        labelStyle: TextStyle(color: scheme.onSurface, fontSize: 13),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: s.inverseSurface,
        contentTextStyle: TextStyle(fontSize: 16, color: s.onInverseSurface),
        actionTextColor: appColors.brand,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: s.container,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radius),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.onPrimary
              : s.onSurfaceVariant,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.primary
              : s.containerHighest,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.transparent
              : s.outline,
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: scheme.primary,
        inactiveTrackColor: scheme.primary.withValues(alpha: 0.24),
        thumbColor: scheme.primary,
        overlayColor: scheme.primary.withValues(alpha: 0.14),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          side: WidgetStateProperty.all(BorderSide(color: s.outline)),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? scheme.primary
                : Colors.transparent,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? scheme.onPrimary
                : scheme.onSurface,
          ),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: scheme.primary,
        unselectedLabelColor: scheme.onSurfaceVariant,
        indicatorColor: scheme.primary,
      ),
    );
  }
}
