import 'package:flutter/material.dart';
import 'app_colors.dart';

/// App-wide [ThemeData] for light and dark mode, built to read like
/// claude.ai: a warm paper/ink canvas instead of cool gray, hairline
/// borders instead of shadows, muted neutral backgrounds with a single
/// terracotta brand accent, and generous rounded corners on
/// cards/inputs/controls.
///
/// Both themes share one [ColorScheme] seed (the brand terracotta) so
/// Material 3's contrast-safe tone generation still drives secondary/
/// tertiary tones — the primary, error, and neutral surface/border/muted
/// roles are overridden with exact brand tokens from [AppColors] instead
/// of Material's generated tones.
class AppTheme {
  AppTheme._();

  static const _cardRadius = 16.0;
  static const _controlRadius = 12.0;

  static ThemeData light = _build(Brightness.light);
  static ThemeData dark = _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    final scaffold = isDark ? AppColors.darkScaffold : AppColors.lightScaffold;
    final surface = isDark ? AppColors.darkSurface : AppColors.lightSurface;
    final onSurface = isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface;
    final muted = isDark ? AppColors.darkMuted : AppColors.lightMuted;
    final mutedForeground = isDark ? AppColors.darkMutedForeground : AppColors.lightMutedForeground;
    final border = isDark ? AppColors.darkBorder : AppColors.lightBorder;
    final borderStrong = isDark ? AppColors.darkBorderStrong : AppColors.lightBorderStrong;
    final primary = isDark ? AppColors.darkPrimary : AppColors.lightPrimary;
    final onPrimary = isDark ? AppColors.darkOnPrimary : AppColors.lightOnPrimary;
    final destructive = isDark ? AppColors.darkDestructive : AppColors.lightDestructive;

    final base = ColorScheme.fromSeed(seedColor: primary, brightness: brightness);
    final scheme = base.copyWith(
      primary: primary,
      onPrimary: onPrimary,
      surface: surface,
      onSurface: onSurface,
      surfaceVariant: muted,
      onSurfaceVariant: mutedForeground,
      outline: borderStrong,
      outlineVariant: border,
      error: destructive,
      onError: Colors.white,
    );

    final textTheme = _textTheme(onSurface);
    final outlineBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(_controlRadius),
      borderSide: BorderSide(color: border),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffold,
      canvasColor: scaffold,
      splashFactory: InkRipple.splashFactory,
      fontFamily: 'Inter',
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      dividerColor: border,
      hintColor: mutedForeground,

      appBarTheme: AppBarTheme(
        backgroundColor: scaffold,
        foregroundColor: onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge?.copyWith(fontSize: 19, fontWeight: FontWeight.w700),
        iconTheme: IconThemeData(color: onSurface),
      ),

      cardTheme: CardThemeData(
        elevation: 0,
        color: surface,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_cardRadius),
          side: BorderSide(color: border),
        ),
      ),

      dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),

      chipTheme: ChipThemeData(
        backgroundColor: muted,
        selectedColor: scheme.primary.withOpacity(0.14),
        disabledColor: muted.withOpacity(0.5),
        labelStyle: TextStyle(color: onSurface, fontSize: 13, fontWeight: FontWeight.w600),
        secondaryLabelStyle: TextStyle(color: scheme.primary, fontSize: 13, fontWeight: FontWeight.w600),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        side: BorderSide(color: border),
        shape: const StadiumBorder(),
        showCheckmark: false,
        iconTheme: IconThemeData(color: mutedForeground, size: 16),
      ),

      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: isDark ? muted.withOpacity(0.4) : surface,
        hintStyle: TextStyle(color: mutedForeground, fontWeight: FontWeight.normal),
        labelStyle: TextStyle(color: mutedForeground),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: outlineBorder,
        enabledBorder: outlineBorder,
        disabledBorder: outlineBorder.copyWith(borderSide: BorderSide(color: border.withOpacity(0.6))),
        focusedBorder: outlineBorder.copyWith(
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
        errorBorder: outlineBorder.copyWith(borderSide: BorderSide(color: scheme.error)),
        focusedErrorBorder: outlineBorder.copyWith(borderSide: BorderSide(color: scheme.error, width: 1.5)),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          disabledBackgroundColor: muted,
          disabledForegroundColor: mutedForeground,
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_controlRadius)),
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: muted,
          foregroundColor: onSurface,
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_controlRadius)),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: onSurface,
          side: BorderSide(color: borderStrong),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_controlRadius)),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_controlRadius)),
        ),
      ),

      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: onSurface),
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primary.withOpacity(0.14),
        elevation: 0,
        height: 64,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? scheme.primary : mutedForeground,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(color: selected ? scheme.primary : mutedForeground, size: 24);
        }),
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 1,
        focusElevation: 1,
        hoverElevation: 2,
        highlightElevation: 2,
        shape: const CircleBorder(),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_cardRadius + 2),
          side: BorderSide(color: border),
        ),
        titleTextStyle: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: mutedForeground),
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: surface,
        elevation: 0,
        showDragHandle: false,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: onSurface,
        contentTextStyle: TextStyle(color: scaffold, fontWeight: FontWeight.w500),
        actionTextColor: scheme.primary,
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_controlRadius)),
      ),

      tabBarTheme: TabBarThemeData(
        labelColor: scheme.primary,
        unselectedLabelColor: mutedForeground,
        indicatorColor: scheme.primary,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: border,
        labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13.5),
        overlayColor: WidgetStateProperty.all(Colors.transparent),
      ),

      listTileTheme: ListTileThemeData(
        iconColor: mutedForeground,
        textColor: onSurface,
        selectedColor: scheme.primary,
        selectedTileColor: scheme.primary.withOpacity(0.06),
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return scheme.primary;
          return isDark ? AppColors.stone400 : Colors.white;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return scheme.primary.withOpacity(0.3);
          return muted;
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.transparent;
          return borderStrong;
        }),
      ),

      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
        side: BorderSide(color: borderStrong, width: 1.5),
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return scheme.primary;
          return Colors.transparent;
        }),
      ),

      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return scheme.primary;
          return mutedForeground;
        }),
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        circularTrackColor: muted,
        linearTrackColor: muted,
      ),

      popupMenuTheme: PopupMenuThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_controlRadius),
          side: BorderSide(color: border),
        ),
        textStyle: TextStyle(color: onSurface, fontSize: 14),
      ),

      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(_controlRadius)),
          ),
          side: WidgetStateProperty.all(BorderSide(color: borderStrong)),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return scheme.primary;
            return Colors.transparent;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return scheme.onPrimary;
            return onSurface;
          }),
        ),
      ),

      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: onSurface,
          borderRadius: BorderRadius.circular(6),
        ),
        textStyle: TextStyle(color: scaffold, fontSize: 12),
      ),
    );
  }

  /// Sizes/weights tuned to claude.ai's own type scale rather than
  /// Material 3's defaults: a comfortable ~15-16px reading size with
  /// generous line-height for body copy, and restrained, moderately-sized
  /// (not oversized) headings — Claude leans on weight and spacing for
  /// hierarchy rather than large jumps in font size.
  static TextTheme _textTheme(Color onSurface) {
    return TextTheme(
      displaySmall: TextStyle(
        color: onSurface, fontSize: 30, fontWeight: FontWeight.w700, letterSpacing: -0.2, height: 1.2),
      headlineSmall: TextStyle(
        color: onSurface, fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.1, height: 1.25),
      titleLarge: TextStyle(
        color: onSurface, fontSize: 19, fontWeight: FontWeight.w700, letterSpacing: -0.1, height: 1.3),
      titleMedium: TextStyle(color: onSurface, fontSize: 16, fontWeight: FontWeight.w600, height: 1.35),
      titleSmall: TextStyle(color: onSurface, fontSize: 14, fontWeight: FontWeight.w600, height: 1.35),
      bodyLarge: TextStyle(color: onSurface, fontSize: 16, fontWeight: FontWeight.w400, height: 1.55),
      bodyMedium: TextStyle(color: onSurface, fontSize: 14.5, fontWeight: FontWeight.w400, height: 1.45),
      bodySmall: TextStyle(color: onSurface, fontSize: 12.5, fontWeight: FontWeight.w400, height: 1.4),
      labelLarge: TextStyle(color: onSurface, fontSize: 14, fontWeight: FontWeight.w600, height: 1.2),
      labelMedium: TextStyle(color: onSurface, fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.2),
      labelSmall: TextStyle(color: onSurface, fontSize: 11.5, fontWeight: FontWeight.w600, height: 1.2),
    );
  }
}
