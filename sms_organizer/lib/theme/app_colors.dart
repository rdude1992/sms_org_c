import 'package:flutter/material.dart';

/// Neutral "zinc" scale and semantic tokens used to flavour Flutter's
/// Material 3 [ColorScheme] into a flat, bordered, shadcn/ui-style look —
/// muted neutrals with a single brand accent, rather than the tonal
/// surfaces Material 3 generates by default.
class AppColors {
  AppColors._();

  // Zinc neutral ramp (shared across light/dark).
  static const zinc50 = Color(0xFFFAFAFA);
  static const zinc100 = Color(0xFFF4F4F5);
  static const zinc200 = Color(0xFFE4E4E7);
  static const zinc300 = Color(0xFFD4D4D8);
  static const zinc400 = Color(0xFFA1A1AA);
  static const zinc500 = Color(0xFF71717A);
  static const zinc600 = Color(0xFF52525B);
  static const zinc700 = Color(0xFF3F3F46);
  static const zinc800 = Color(0xFF27272A);
  static const zinc900 = Color(0xFF18181B);
  static const zinc950 = Color(0xFF09090B);

  /// Brand seed the Material 3 [ColorScheme] is generated from — kept as
  /// the app's one accent colour so primary/error/tertiary tones stay
  /// perceptually consistent and accessible in both themes.
  static const seed = Color(0xFF3B6DF5);

  static const destructive = Color(0xFFEF4444);

  // Light theme surface tokens.
  static const lightScaffold = zinc50;
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightOnSurface = zinc900;
  static const lightMuted = zinc100;
  static const lightMutedForeground = zinc500;
  // One step darker than the zinc-200/300 shadcn defaults — those read as
  // basically invisible hairlines against a white/near-white card (E4E4E7
  // on FFFFFF is ~1.08:1 contrast), which is why list-row dividers and
  // card outlines weren't actually showing up.
  static const lightBorder = zinc300;
  static const lightBorderStrong = zinc400;

  // Dark theme surface tokens.
  static const darkScaffold = zinc950;
  static const darkSurface = zinc900;
  static const darkOnSurface = zinc50;
  static const darkMuted = zinc800;
  static const darkMutedForeground = zinc400;
  static const darkBorder = zinc700;
  static const darkBorderStrong = zinc600;
}
