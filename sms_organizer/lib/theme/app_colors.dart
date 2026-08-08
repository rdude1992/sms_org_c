import 'package:flutter/material.dart';

/// Warm "stone" neutral scale and semantic tokens styled after Claude's
/// (claude.ai) UI: a paper/cream canvas rather than cool gray, hairline
/// borders instead of shadows, and a single terracotta brand accent used
/// everywhere Material would otherwise default to blue.
class AppColors {
  AppColors._();

  // Warm neutral ramp (shared across light/dark) — Tailwind's "stone"
  // scale, which is toned yellow/brown rather than the blue-gray of zinc.
  static const stone50 = Color(0xFFFAFAF9);
  static const stone100 = Color(0xFFF5F5F4);
  static const stone200 = Color(0xFFE7E5E4);
  static const stone300 = Color(0xFFD6D3D1);
  static const stone400 = Color(0xFFA8A29E);
  static const stone500 = Color(0xFF78716C);
  static const stone600 = Color(0xFF57534E);
  static const stone700 = Color(0xFF44403C);
  static const stone800 = Color(0xFF292524);
  static const stone900 = Color(0xFF1C1917);
  static const stone950 = Color(0xFF0C0A09);

  /// Claude's signature clay/terracotta accent — the app's one brand
  /// colour, used for the seeded [ColorScheme] as well as anywhere a
  /// screen needs the brand colour directly instead of through the theme.
  static const lightPrimary = Color(0xFFC96442);
  static const lightOnPrimary = Color(0xFFFFFFFF);
  // A touch lighter/warmer so it still pops against the near-black dark
  // background instead of reading muddy.
  static const darkPrimary = Color(0xFFD97757);
  static const darkOnPrimary = Color(0xFFFFFFFF);

  static const lightDestructive = Color(0xFFC0152F);
  static const darkDestructive = Color(0xFFE5484D);

  // Light theme surface tokens — warm cream canvas with white cards, the
  // same "paper" feel as claude.ai's light mode.
  static const lightScaffold = Color(0xFFFAF9F5);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightOnSurface = Color(0xFF262624);
  static const lightMuted = Color(0xFFF0EEE6);
  static const lightMutedForeground = Color(0xFF83827D);
  static const lightBorder = Color(0xFFE1DED4);
  static const lightBorderStrong = Color(0xFFC9C4B8);

  // Dark theme surface tokens — warm near-black ink instead of a cool
  // slate/zinc dark mode.
  static const darkScaffold = Color(0xFF262624);
  static const darkSurface = Color(0xFF30302E);
  static const darkOnSurface = Color(0xFFF5F4EE);
  static const darkMuted = Color(0xFF3A3935);
  static const darkMutedForeground = Color(0xFFA3A299);
  static const darkBorder = Color(0xFF45443F);
  static const darkBorderStrong = Color(0xFF57554D);
}
