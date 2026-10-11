// theme_model.dart, the app's design tokens (DA) and light/dark themes.
// ConvertAll, a versatile unit conversion program.
// Copyright (c) 2026, Douglas W. Bell.
// Free software, GPL v2 or later.
//
// Design direction (DA) - "Precision Instrument":
//   * A converter is a measuring instrument, so the interface stays quiet:
//     neutral cool-grey surfaces, one confident accent, and semantic colors
//     used only for feedback (valid / warning / error).
//   * Data first: numbers use tabular figures, labels are small uppercase
//     text, and every block of content lives on a bordered "panel" card so
//     the eye can scan From -> list -> To without effort.
//   * Two accents identify the two sides of a conversion: the azure primary
//     for "From" and the indigo tertiary for "To".  They are also used by
//     the swap button that joins the two sides.
//   * Contrast: every pair below meets WCAG AA (>= 4.5:1) for body text.

import 'package:flutter/material.dart';
import '../main.dart' show prefs;

/// Colors that are not part of Material's [ColorScheme].
///
/// They are exposed as a [ThemeExtension] so that widgets can read them
/// with `AppColors.of(context)`.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  /// Page background, behind the panels.
  final Color canvas;

  /// Panel (card) background.
  final Color panel;

  /// Hairline used for panel borders, table row separators and dividers.
  final Color hairline;

  /// Sunken surface used for editable fields.
  final Color sunken;

  /// Stronger sunken surface used for table headers and key hints.
  final Color sunkenStrong;

  /// Overlay painted under the mouse pointer in lists and tables.
  final Color hover;

  /// Overlay painted on the keyboard-highlighted row (not yet applied).
  final Color highlight;

  /// Focus ring drawn around the currently focused field.
  final Color focusRing;

  /// Soft accent background (badges, colored chips).
  final Color accentSoft;

  /// Positive feedback (compatible units, successful copy).
  final Color success;

  /// Cautionary feedback (partial entry, filtered lists).
  final Color warning;

  /// Negative feedback (unknown or incompatible units).
  final Color danger;

  const AppColors({
    required this.canvas,
    required this.panel,
    required this.hairline,
    required this.sunken,
    required this.sunkenStrong,
    required this.hover,
    required this.highlight,
    required this.focusRing,
    required this.accentSoft,
    required this.success,
    required this.warning,
    required this.danger,
  });

  /// Light palette ("Daylight instrument").
  static const light = AppColors(
    canvas: Color(0xFFEDF1F7),
    panel: Color(0xFFFFFFFF),
    hairline: Color(0xFFDCE3ED),
    sunken: Color(0xFFF7F9FC),
    sunkenStrong: Color(0xFFEDF1F8),
    hover: Color(0x0F1E5AE8),
    highlight: Color(0x1A1E5AE8),
    focusRing: Color(0x331E5AE8),
    accentSoft: Color(0xFFE6EDFD),
    success: Color(0xFF147A4B),
    warning: Color(0xFF9A6100),
    danger: Color(0xFFBB3021),
  );

  /// Dark palette ("Night instrument").
  static const dark = AppColors(
    canvas: Color(0xFF0A1120),
    panel: Color(0xFF121A2B),
    hairline: Color(0xFF26314A),
    sunken: Color(0xFF161F33),
    sunkenStrong: Color(0xFF1B2740),
    hover: Color(0x14FFFFFF),
    highlight: Color(0x247AA2FF),
    focusRing: Color(0x4D7AA2FF),
    accentSoft: Color(0xFF1C2B4D),
    success: Color(0xFF48C98B),
    warning: Color(0xFFE0B04C),
    danger: Color(0xFFFF8B7B),
  );

  /// Return the palette of the enclosing theme, falling back to the palette
  /// matching the current brightness when no extension is registered.
  static AppColors of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<AppColors>() ??
        (theme.brightness == Brightness.dark ? dark : light);
  }

  @override
  AppColors copyWith({
    Color? canvas,
    Color? panel,
    Color? hairline,
    Color? sunken,
    Color? sunkenStrong,
    Color? hover,
    Color? highlight,
    Color? focusRing,
    Color? accentSoft,
    Color? success,
    Color? warning,
    Color? danger,
  }) {
    return AppColors(
      canvas: canvas ?? this.canvas,
      panel: panel ?? this.panel,
      hairline: hairline ?? this.hairline,
      sunken: sunken ?? this.sunken,
      sunkenStrong: sunkenStrong ?? this.sunkenStrong,
      hover: hover ?? this.hover,
      highlight: highlight ?? this.highlight,
      focusRing: focusRing ?? this.focusRing,
      accentSoft: accentSoft ?? this.accentSoft,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
    );
  }

  @override
  AppColors lerp(covariant AppColors? other, double t) {
    if (other == null) return this;
    return AppColors(
      canvas: Color.lerp(canvas, other.canvas, t)!,
      panel: Color.lerp(panel, other.panel, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
      sunken: Color.lerp(sunken, other.sunken, t)!,
      sunkenStrong: Color.lerp(sunkenStrong, other.sunkenStrong, t)!,
      hover: Color.lerp(hover, other.hover, t)!,
      highlight: Color.lerp(highlight, other.highlight, t)!,
      focusRing: Color.lerp(focusRing, other.focusRing, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
    );
  }
}

/// Builds the light and dark [ThemeData] used by the app.
class AppTheme {
  /// Extra colors registered in both themes.
  static const lightAppColors = AppColors.light;
  static const darkAppColors = AppColors.dark;

  /// Scale of white space: 4 / 8 / 12 / 16 / 24.
  static const double gapXs = 4.0;
  static const double gapS = 8.0;
  static const double gapM = 12.0;
  static const double gapL = 16.0;
  static const double gapXl = 24.0;

  /// Corner radius of the content panels.
  static const double panelRadius = 14.0;

  /// Corner radius of the fields.
  static const double fieldRadius = 10.0;

  /// Radius of the window card shown on the web page background.
  static const double webRadius = 20.0;

  /// Backdrop behind the window card of the web version: one step darker
  /// (light theme) or deeper (dark theme) than the canvas, so the card reads
  /// as a floating window.
  static const Color webBackdropLight = Color(0xFFDCE3ED);
  static const Color webBackdropDark = Color(0xFF060B14);

  /// Uppercase label used above sections, panels and fields.
  static final TextStyle overline = TextStyle(
    fontSize: 10.5,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.4,
  );

  /// Text of a unit expression such as `ft * lbf / hr`.
  static final TextStyle unitText = TextStyle(
    fontSize: 15,
    height: 1.25,
    letterSpacing: 0.2,
    fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
  );

  /// Text of a converted or entered value (the hero data of the screen).
  static final TextStyle valueText = TextStyle(
    fontSize: 22,
    height: 1.15,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.2,
    fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
  );

  /// Small monospaced-feeling text used for keys, codes and reduced units.
  static final TextStyle codeText = TextStyle(
    fontSize: 12.5,
    letterSpacing: 0.3,
    fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
  );

  /// Light theme: azure primary, indigo tertiary, cool grey surfaces.
  static final ColorScheme _lightScheme = const ColorScheme.light(
    // Accent used for focus, selection markers and the "From" side.
    primary: Color(0xFF1E5AE8), // 5.2:1 on white
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFDCE8FF), // selected table row
    onPrimaryContainer: Color(0xFF0B2A6B),
    // Quiet slate secondary (headers, muted controls).
    secondary: Color(0xFF4F5B76),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFE4E9F3),
    onSecondaryContainer: Color(0xFF1B2436),
    // Indigo accent used for the "To" side.
    tertiary: Color(0xFF4F46E5), // 6.3:1 on white
    onTertiary: Color(0xFFFFFFFF),
    tertiaryContainer: Color(0xFFE6E4FF),
    onTertiaryContainer: Color(0xFF231C7A),
    error: Color(0xFFBB3021),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFFBE3DF),
    onErrorContainer: Color(0xFF5C1108),
    surface: Color(0xFFFFFFFF),
    onSurface: Color(0xFF101828), // 16:1 on white
    onSurfaceVariant: Color(0xFF5A6880), // 5.6:1 on white
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: Color(0xFFF7F9FC),
    surfaceContainer: Color(0xFFF7F9FC),
    surfaceContainerHigh: Color(0xFFEDF1F8),
    surfaceContainerHighest: Color(0xFFE6EBF4),
    outline: Color(0xFFB9C4D6),
    outlineVariant: Color(0xFFDCE3ED),
    shadow: Color(0x1F101828),
    scrim: Color(0x80101828),
    inverseSurface: Color(0xFF24303F),
    onInverseSurface: Color(0xFFF3F6FA),
    inversePrimary: Color(0xFF9DBAFF),
  );

  /// Dark theme: brighter azure/indigo so both accents keep their contrast.
  static final ColorScheme _darkScheme = const ColorScheme.dark(
    primary: Color(0xFF7AA2FF), // 8.6:1 on the dark canvas
    onPrimary: Color(0xFF0A1A3D),
    primaryContainer: Color(0xFF1E3A72),
    onPrimaryContainer: Color(0xFFDDE7FF),
    secondary: Color(0xFF9FB0CC),
    onSecondary: Color(0xFF0A1120),
    secondaryContainer: Color(0xFF24314C),
    onSecondaryContainer: Color(0xFFDBE4F5),
    tertiary: Color(0xFFA5A1FF), // 7.4:1 on the dark canvas
    onTertiary: Color(0xFF17123F),
    tertiaryContainer: Color(0xFF2E2A6E),
    onTertiaryContainer: Color(0xFFE4E2FF),
    error: Color(0xFFFF8B7B),
    onError: Color(0xFF3A0A03),
    errorContainer: Color(0xFF5C1B10),
    onErrorContainer: Color(0xFFFFDAD4),
    surface: Color(0xFF121A2B),
    onSurface: Color(0xFFE9EEF7), // 13:1 on the panel color
    onSurfaceVariant: Color(0xFFA3B2CB), // 7.6:1 on the panel color
    surfaceContainerLowest: Color(0xFF0A1120),
    surfaceContainerLow: Color(0xFF161F33),
    surfaceContainer: Color(0xFF161F33),
    surfaceContainerHigh: Color(0xFF1B2740),
    surfaceContainerHighest: Color(0xFF212E4A),
    outline: Color(0xFF465570),
    outlineVariant: Color(0xFF26314A),
    shadow: Color(0x66000000),
    scrim: Color(0x99000000),
    inverseSurface: Color(0xFFE9EEF7),
    onInverseSurface: Color(0xFF141B28),
    inversePrimary: Color(0xFF1E3A72),
  );

  /// The light [ThemeData].
  static ThemeData light() => _build(_lightScheme, lightAppColors);

  /// The dark [ThemeData].
  static ThemeData dark() => _build(_darkScheme, darkAppColors);

  static ThemeData _build(ColorScheme scheme, AppColors colors) {
    final base = ThemeData(
      colorScheme: scheme,
      brightness: scheme.brightness,
      useMaterial3: true,
    );
    final text = _textTheme(base.textTheme, scheme);
    final radius = BorderRadius.circular(fieldRadius);

    return base.copyWith(
      scaffoldBackgroundColor: colors.canvas,
      canvasColor: colors.panel,
      textTheme: text,
      primaryTextTheme: text,
      extensions: <ThemeExtension<dynamic>>[colors],
      iconTheme: const IconThemeData(size: 20),
      dividerTheme: DividerThemeData(
        color: colors.hairline,
        thickness: 1.0,
        space: 1.0,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: colors.panel,
        surfaceTintColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        elevation: 0.0,
        scrolledUnderElevation: 0.0,
        centerTitle: false,
        titleTextStyle: text.titleMedium,
        shape: Border(bottom: BorderSide(color: colors.hairline)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: colors.sunken,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12.0,
          vertical: 11.0,
        ),
        hintStyle: text.bodyLarge?.copyWith(color: scheme.outline),
        labelStyle: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        floatingLabelStyle: text.bodySmall?.copyWith(color: scheme.primary),
        helperStyle: text.bodySmall,
        helperMaxLines: 2,
        errorStyle: text.bodySmall?.copyWith(color: colors.danger),
        errorMaxLines: 2,
        border: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: scheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: colors.hairline),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: colors.hairline.withValues(alpha: 0.6)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: colors.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: colors.danger, width: 1.6),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.onPrimary
              : scheme.outline,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.primary
              : colors.sunkenStrong,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.transparent
              : colors.hairline,
        ),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.hovered)
              ? scheme.outline
              : scheme.outline.withValues(alpha: 0.7),
        ),
        trackColor: WidgetStatePropertyAll<Color>(
          colors.sunkenStrong.withValues(alpha: 0.5),
        ),
        thickness: const WidgetStatePropertyAll<double>(8.0),
        crossAxisMargin: 2.0,
        radius: const Radius.circular(4.0),
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 450),
        padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 6.0),
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          borderRadius: BorderRadius.circular(8.0),
        ),
        textStyle: text.bodySmall?.copyWith(color: scheme.onInverseSurface),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: colors.panel,
        surfaceTintColor: Colors.transparent,
        elevation: 8.0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.0),
          side: BorderSide(color: colors.hairline),
        ),
        textStyle: text.bodyMedium,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
        textColor: scheme.onSurface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12.0),
        horizontalTitleGap: 12.0,
        minVerticalPadding: 6.0,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: colors.sunken,
        selectedColor: colors.accentSoft,
        checkmarkColor: scheme.primary,
        side: BorderSide(color: colors.hairline),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8.0),
        ),
        labelStyle: text.bodySmall?.copyWith(fontWeight: FontWeight.w600),
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          textStyle: text.labelLarge,
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          textStyle: text.labelLarge,
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(fieldRadius),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.onSurface,
          textStyle: text.labelLarge,
          side: BorderSide(color: colors.hairline),
          padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 12.0),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(fieldRadius),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: text.bodyMedium?.copyWith(
          color: scheme.onInverseSurface,
        ),
        elevation: 6.0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10.0),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: colors.sunkenStrong,
        circularTrackColor: colors.sunkenStrong,
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: colors.panel,
        surfaceTintColor: Colors.transparent,
        elevation: 0.0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            topRight: Radius.circular(panelRadius),
            bottomRight: Radius.circular(panelRadius),
          ),
        ),
      ),
    );
  }

  /// Type scale of the app.
  static TextTheme _textTheme(TextTheme base, ColorScheme scheme) {
    return base.copyWith(
      titleLarge: base.titleLarge?.copyWith(
        fontSize: 20.0,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        color: scheme.onSurface,
      ),
      titleMedium: base.titleMedium?.copyWith(
        fontSize: 16.5,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.1,
        color: scheme.onSurface,
      ),
      titleSmall: base.titleSmall?.copyWith(
        fontSize: 14.0,
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
      bodyLarge: base.bodyLarge?.copyWith(
        fontSize: 15.0,
        color: scheme.onSurface,
      ),
      bodyMedium: base.bodyMedium?.copyWith(
        fontSize: 14.0,
        color: scheme.onSurface,
      ),
      bodySmall: base.bodySmall?.copyWith(
        fontSize: 12.5,
        height: 1.35,
        color: scheme.onSurfaceVariant,
      ),
      labelLarge: base.labelLarge?.copyWith(
        fontSize: 13.0,
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
      labelMedium: base.labelMedium?.copyWith(
        fontSize: 11.5,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.6,
        color: scheme.onSurfaceVariant,
      ),
      labelSmall: base.labelSmall?.copyWith(
        fontSize: 11.0,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.8,
        color: scheme.onSurfaceVariant,
      ),
    );
  }
}

/// This class is used to retrieve and update theme data.
class ThemeModel extends ChangeNotifier {
  ThemeModel();

  /// True when the dark palette is selected.
  bool get isDark => prefs.getBool('dark_theme') ?? false;

  /// Return the theme based on the current light/dark setting.
  ThemeData getTheme() {
    return isDark ? darkTheme : lightTheme;
  }

  /// Language selected in the settings: 'system', 'en' or 'fr'.
  String get languageCode => prefs.getString('language') ?? 'system';

  /// The locale of the interface, or null to follow the system language.
  Locale? get locale {
    switch (languageCode) {
      case 'en':
        return const Locale('en');
      case 'fr':
        return const Locale('fr');
      default:
        return null;
    }
  }

  /// Update the themes and the language throughout the app.
  void updateTheme() {
    notifyListeners();
  }

  /// The light theme (kept as a static so it is built only once).
  static final ThemeData lightTheme = AppTheme.light();

  /// The dark theme (kept as a static so it is built only once).
  static final ThemeData darkTheme = AppTheme.dark();
}
