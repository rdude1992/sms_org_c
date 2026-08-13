import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app.dart';
import 'providers/collapsible_sections_provider.dart';
import 'providers/notification_settings_provider.dart';
import 'providers/security_settings_provider.dart';
import 'providers/sms_provider.dart';
import 'providers/theme_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final themeProvider = ThemeProvider();
  await themeProvider.load();

  final notificationSettingsProvider = NotificationSettingsProvider();
  await notificationSettingsProvider.load();

  final securitySettingsProvider = SecuritySettingsProvider();
  await securitySettingsProvider.load();

  final collapsibleSectionsProvider = CollapsibleSectionsProvider();
  await collapsibleSectionsProvider.load();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: themeProvider),
        ChangeNotifierProvider.value(value: notificationSettingsProvider),
        ChangeNotifierProvider.value(value: securitySettingsProvider),
        ChangeNotifierProvider.value(value: collapsibleSectionsProvider),
        ChangeNotifierProvider(create: (_) => SmsProvider()),
      ],
      child: const SmsOrganizerApp(),
    ),
  );
}
