import 'dart:io';
import 'package:file_selector/file_selector.dart' show openFile, XTypeGroup;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/category.dart';
import '../providers/notification_settings_provider.dart';
import '../providers/sms_provider.dart';
import '../providers/theme_provider.dart';
import '../widgets/category_badge.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final smsProvider = context.watch<SmsProvider>();
    final themeProvider = context.watch<ThemeProvider>();
    final notificationSettings = context.watch<NotificationSettingsProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          _SectionHeader('Appearance'),
          SwitchListTile(
            title: const Text('Dark mode'),
            subtitle: const Text('Overrides system setting'),
            value: themeProvider.isDark,
            onChanged: (v) => themeProvider.setDark(v),
          ),
          TextButton(
            onPressed: themeProvider.useSystemDefault,
            child: const Text('Use system default instead'),
          ),
          const Divider(),
          _SectionHeader('Default SMS app'),
          ListTile(
            leading: Icon(
              smsProvider.isDefaultSmsApp ? Icons.check_circle : Icons.error_outline,
              color: smsProvider.isDefaultSmsApp ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
            ),
            title: Text(smsProvider.isDefaultSmsApp
                ? 'This app is your default SMS app'
                : 'Not set as default SMS app'),
            subtitle: smsProvider.isDefaultSmsApp
                ? null
                : const Text('Sending/receiving may be limited until set as default.'),
            trailing: smsProvider.isDefaultSmsApp
                ? null
                : FilledButton(
                    onPressed: () => smsProvider.requestDefaultSmsRole(),
                    child: const Text('Set default'),
                  ),
          ),
          const Divider(),
          _SectionHeader('Notifications'),
          for (final category in SmsCategory.values)
            SwitchListTile(
              secondary: CategoryBadge(category: category, compact: true),
              title: Text(category.label),
              subtitle: Text(_categoryNotificationHint(category)),
              value: !notificationSettings.isMuted(category),
              onChanged: (enabled) =>
                  context.read<NotificationSettingsProvider>().setMuted(category, !enabled),
            ),
          const Divider(),
          _SectionHeader('Data & sync'),
          ListTile(
            leading: const Icon(Icons.storage_outlined),
            title: const Text('Local cache'),
            subtitle: Text(
              '${smsProvider.allMessages.length} messages on-device • '
              '${smsProvider.transactions.length} transactions cached',
            ),
          ),
          ListTile(
            leading: const Icon(Icons.refresh_outlined),
            title: const Text('Recalculate categorisation'),
            subtitle: const Text(
              'Wipes the local cache and re-scans everything from scratch. '
              'Categories are normally cached once and never re-checked — use '
              'this if something looks miscategorised.',
            ),
            onTap: () => _confirmRecalculate(context),
          ),
          const Divider(),
          _SectionHeader('Backup & restore'),
          ListTile(
            leading: const Icon(Icons.ios_share_outlined),
            title: const Text('Export & share backup'),
            subtitle: const Text('Saves messages, categories, and parsed transactions as JSON'),
            onTap: () => _exportBackup(context),
          ),
          ListTile(
            leading: const Icon(Icons.file_open_outlined),
            title: const Text('Restore from backup file'),
            onTap: () => _restoreBackup(context),
          ),
          const Divider(),
          _SectionHeader('About'),
          const ListTile(
            leading: Icon(Icons.privacy_tip_outlined),
            title: Text('Your data stays on-device'),
            subtitle: Text(
              'Categorisation and transaction parsing run locally. Nothing is sent to a server.',
            ),
          ),
        ],
      ),
    );
  }

  String _categoryNotificationHint(SmsCategory category) {
    switch (category) {
      case SmsCategory.personal:
        return 'Notify for messages from people';
      case SmsCategory.promotional:
        return 'Notify for offers, sales, and marketing SMS';
      case SmsCategory.transactional:
        return 'Notify for bank/card/UPI alerts';
      case SmsCategory.otp:
        return 'Notify for one-time passwords';
      case SmsCategory.updates:
        return 'Notify for delivery, booking, and statement notices';
    }
  }

  Future<void> _confirmRecalculate(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Recalculate categorisation?'),
        content: const Text(
          'This clears the cached categories and transactions and re-scans every '
          'message from scratch. It may take a moment on a large inbox.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Recalculate')),
        ],
      ),
    );
    if (confirmed != true) return;

    final provider = context.read<SmsProvider>();
    await provider.recalculateAll();
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Recalculated from scratch.')));
    }
  }

  Future<void> _exportBackup(BuildContext context) async {
    final provider = context.read<SmsProvider>();
    try {
      await provider.backup.exportAndShare(
        messages: provider.allMessages,
        transactions: provider.transactions,
        investments: provider.investments,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    }
  }

  Future<void> _restoreBackup(BuildContext context) async {
    final provider = context.read<SmsProvider>();
    try {
      const typeGroup = XTypeGroup(label: 'JSON', extensions: ['json']);
      final file = await openFile(acceptedTypeGroups: [typeGroup]);
      if (file == null) return;
      final bundle = await provider.backup.restoreFromFile(File(file.path));
      await provider.restoreFromBackup(bundle);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Backup restored.')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Restore failed: $e')));
      }
    }
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}
