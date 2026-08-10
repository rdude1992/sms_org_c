import 'dart:io';
import 'package:file_selector/file_selector.dart' show openFile, XTypeGroup;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/category.dart';
import '../providers/notification_settings_provider.dart';
import '../providers/security_settings_provider.dart';
import '../providers/sms_provider.dart';
import '../providers/theme_provider.dart';
import '../services/sms_platform_service.dart';
import '../widgets/ui/grouped_card.dart';
import 'uncategorised_review_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with WidgetsBindingObserver {
  // The OS's real, current importance for each category's channel — may be
  // out of sync with NotificationSettingsProvider.isMuted if the user
  // changed it directly in system settings rather than through this app.
  // Absent (not yet loaded) entries are treated as "nothing to flag".
  Map<SmsCategory, int> _channelImportance = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshChannelStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // The user may have just come back from the system channel-settings
  // screen (opened via the "tune" button below), so re-check on resume
  // rather than only once when this screen first loads.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshChannelStatus();
  }

  Future<void> _refreshChannelStatus() async {
    final provider = context.read<SmsProvider>();
    final entries = await Future.wait(
      SmsCategory.values.map((c) async => MapEntry(c, await provider.channelImportanceFor(c))),
    );
    if (mounted) setState(() => _channelImportance = Map.fromEntries(entries));
  }

  @override
  Widget build(BuildContext context) {
    final smsProvider = context.watch<SmsProvider>();
    final themeProvider = context.watch<ThemeProvider>();
    final notificationSettings = context.watch<NotificationSettingsProvider>();
    final securitySettings = context.watch<SecuritySettingsProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          _SectionHeader('Appearance'),
          GroupedCard(
            children: [
              SwitchListTile(
                title: const Text('Dark mode'),
                subtitle: const Text('Overrides system setting'),
                value: themeProvider.isDark,
                onChanged: (v) => themeProvider.setDark(v),
              ),
              ListTile(
                leading: const Icon(Icons.brightness_auto_outlined),
                title: const Text('Use system default'),
                onTap: themeProvider.useSystemDefault,
              ),
            ],
          ),
          _SectionHeader('Default SMS app'),
          GroupedCard(
            children: [
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
            ],
          ),
          _SectionHeader('Notifications'),
          GroupedCard(
            children: [
              for (final category in SmsCategory.values)
                _NotificationCategoryRow(
                  category: category,
                  muted: notificationSettings.isMuted(category),
                  importance: _channelImportance[category],
                  hint: _categoryNotificationHint(category),
                  onToggle: (enabled) async {
                    await context.read<NotificationSettingsProvider>().setMuted(category, !enabled);
                    // The native side just applied this to the category's
                    // actual OS channel importance too (see
                    // NotificationChannels.syncMuteState) — re-read it so
                    // the "Silenced in system settings" banner reflects the
                    // toggle immediately instead of waiting for this screen
                    // to next resume.
                    _refreshChannelStatus();
                  },
                  onCustomize: () => context.read<SmsProvider>().openChannelSettingsFor(category),
                ),
            ],
          ),
          _SectionHeader('Privacy & security'),
          GroupedCard(
            children: [
              SwitchListTile(
                title: const Text('Lock Insights'),
                subtitle: const Text('Require fingerprint, face, or device PIN to view Insights'),
                value: securitySettings.lockEnabled,
                onChanged: (enabled) => _onToggleInsightsLock(context, enabled),
              ),
            ],
          ),
          _SectionHeader('Message counts'),
          GroupedCard(
            children: [
              ListTile(
                leading: const Icon(Icons.forum_outlined),
                title: const Text('Total messages'),
                trailing: Text(
                  '${smsProvider.totalMessageCount}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
              for (final entry in smsProvider.categoryCounts.entries)
                ListTile(
                  leading: Icon(entry.key.icon, color: entry.key.color),
                  title: Text(entry.key.label),
                  trailing: Text('${entry.value}', style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
            ],
          ),
          _SectionHeader('Data & sync'),
          GroupedCard(
            children: [
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
                  'this if something looks miscategorised. Categories you\'ve '
                  'manually changed are kept as-is.',
                ),
                onTap: () => _confirmRecalculate(context),
              ),
              ListTile(
                leading: const Icon(Icons.label_off_outlined),
                title: const Text('Review uncategorised transactions'),
                subtitle: Text(
                  '${smsProvider.transactions.where((t) => t.spendCategory == null).length} '
                  'transactions grouped by merchant — tag a whole group at once',
                ),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const UncategorisedReviewScreen()),
                ),
              ),
            ],
          ),
          _SectionHeader('Backup & restore'),
          GroupedCard(
            children: [
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
            ],
          ),
          _SectionHeader('About'),
          GroupedCard(
            children: [
              const ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('SmartSMS'),
                // Version is a plain string rather than read via
                // package_info_plus (not a dependency here) — keep it in
                // sync with pubspec.yaml's `version:` by hand on release.
                subtitle: Text(
                  'Version 0.1.0 · Smart SMS organiser with categorisation, '
                  'expense & investment insights.',
                ),
              ),
              const ListTile(
                leading: Icon(Icons.privacy_tip_outlined),
                title: Text('Your data stays on-device'),
                subtitle: Text(
                  'Categorisation and transaction parsing run locally. Nothing is sent to a server.',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Turning the lock off just clears it — nothing to verify. Turning it
  /// on first checks the device actually has a screen lock or biometric
  /// enrolled (otherwise the toggle would strand the user with no way to
  /// ever unlock Insights again), then requires a successful
  /// authentication right away so the toggle can't end up "on" without
  /// ever having been tested — see SecuritySettingsProvider.setLockEnabled
  /// for why that same auth also means the very next Insights visit this
  /// session doesn't re-prompt redundantly.
  Future<void> _onToggleInsightsLock(BuildContext context, bool enabled) async {
    final security = context.read<SecuritySettingsProvider>();
    if (!enabled) {
      await security.setLockEnabled(false);
      return;
    }

    final supported = await security.isBiometricSupported;
    if (!supported) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Set a screen lock (PIN, pattern, or biometric) on this device first.'),
          ),
        );
      }
      return;
    }

    final authenticated = await security.authenticate();
    if (!authenticated) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Authentication failed — Insights lock wasn't enabled.")),
        );
      }
      return;
    }

    await security.setLockEnabled(true);
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

/// One notification-category row: the mute switch plus a "tune" button
/// that deep-links into the OS's own per-channel settings (sound,
/// vibration, priority conversation) — controls this screen otherwise has
/// no UI for. When the OS reports the channel itself has been silenced or
/// blocked while [muted] is still off (i.e. without the user having asked
/// for it here — most likely changed by hand in system settings, or an OEM
/// default), a small banner surfaces that directly rather than leaving
/// notifications silently not showing up with no explanation. Muting a
/// category from the switch above silences its OS channel too (see
/// NotificationChannels.syncMuteState) — that's the expected, intentional
/// case, so it's excluded here rather than flagged as something to "fix".
class _NotificationCategoryRow extends StatelessWidget {
  final SmsCategory category;
  final bool muted;
  final int? importance;
  final String hint;
  final ValueChanged<bool> onToggle;
  final VoidCallback onCustomize;

  const _NotificationCategoryRow({
    required this.category,
    required this.muted,
    required this.importance,
    required this.hint,
    required this.onToggle,
    required this.onCustomize,
  });

  bool get _silencedByOs =>
      !muted && importance != null && NotificationImportance.isSilencedByOs(importance!);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        ListTile(
          contentPadding: const EdgeInsets.only(left: 16, right: 4),
          leading: Icon(category.icon, color: category.color),
          title: Text(category.label, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(hint, style: const TextStyle(fontSize: 12.5)),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Switch(value: !muted, onChanged: onToggle),
              IconButton(
                icon: const Icon(Icons.tune, size: 20),
                tooltip: 'Customize in system settings',
                onPressed: onCustomize,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
        if (_silencedByOs)
          InkWell(
            onTap: onCustomize,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  Icon(Icons.notifications_off_outlined, size: 14, color: scheme.error),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Silenced in system settings — tap to fix',
                      style: TextStyle(fontSize: 11.5, color: scheme.error, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
