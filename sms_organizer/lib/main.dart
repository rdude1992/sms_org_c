import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app.dart';
import 'providers/notification_settings_provider.dart';
import 'providers/sms_provider.dart';
import 'providers/theme_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final themeProvider = ThemeProvider();
  await themeProvider.load();

  final notificationSettingsProvider = NotificationSettingsProvider();
  await notificationSettingsProvider.load();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: themeProvider),
        ChangeNotifierProvider.value(value: notificationSettingsProvider),
        ChangeNotifierProvider(create: (_) => SmsProvider()),
      ],
      child: const SmsOrganizerApp(),
    ),
  );
}
