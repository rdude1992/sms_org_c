import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/theme_provider.dart';
import 'screens/permission_onboarding_screen.dart';
import 'theme/app_theme.dart';
import 'utils/navigation.dart';

class SmsOrganizerApp extends StatelessWidget {
  const SmsOrganizerApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();

    return MaterialApp(
      title: 'SMS Organiser',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeProvider.mode,
      home: const PermissionOnboardingScreen(),
    );
  }
}
