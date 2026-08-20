import 'dart:io';
import 'package:file_selector/file_selector.dart' show openFile, XTypeGroup;
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import '../models/category.dart';
import '../providers/notification_settings_provider.dart';
import '../providers/security_settings_provider.dart';
import '../providers/sms_provider.dart';
import '../providers/theme_provider.dart';
import '../services/sms_platform_service.dart';
import '../theme/app_colors.dart';
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

  // Read from the platform (which derives it from the installed build's own
  // version/build number — see android/app/build.gradle's flutterVersionName)
  // rather than hardcoded, so About always matches whatever's actually
  // installed instead of drifting from pubspec.yaml on release.
  PackageInfo? _packageInfo;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshChannelStatus();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _packageInfo = info);
    });
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
              _AccentColorPicker(
                selected: themeProvider.accentColor,
                onSelected: (color) => themeProvider.setAccentColor(color),
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
                subtitle: const Text('Repopulates this app\'s cache only — device SMS store untouched'),
                onTap: () => _restoreBackup(context),
              ),
              ListTile(
                leading: const Icon(Icons.sms_outlined),
                title: const Text('Restore SMS to device'),
                subtitle: const Text('Writes backed-up messages into your phone\'s SMS store'),
                onTap: () => _restoreToDeviceStore(context),
              ),
            ],
          ),
          _SectionHeader('About'),
          GroupedCard(
            children: [
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('SmartSMS'),
                subtitle: Text(
                  _packageInfo == null
                      ? 'Smart SMS organiser with categorisation, expense & investment insights.'
                      : 'Version ${_packageInfo!.version} (${_packageInfo!.buildNumber}) · Smart SMS '
                          'organiser with categorisation, expense & investment insights.',
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

  /// Restores a backup file's messages into the actual Android SMS store
  /// (content://sms), not just this app's cache — see [_restoreBackup] for
  /// that. Requires being the default SMS app; if the device's SMS store
  /// already has messages, asks whether to add the backup alongside them
  /// (risking duplicates if the backup came from this same device) or wipe
  /// the store first and replace it entirely, with a second, explicit
  /// confirmation before anything destructive happens.
  Future<void> _restoreToDeviceStore(BuildContext context) async {
    final provider = context.read<SmsProvider>();

    if (!provider.isDefaultSmsApp) {
      final setDefault = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Default SMS app required'),
          content: const Text(
            'Writing messages into your phone\'s SMS store requires SmartSMS '
            'to be the default SMS app first.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Set default')),
          ],
        ),
      );
      if (setDefault != true) return;
      final became = await provider.requestDefaultSmsRole();
      if (!became) return;
    }

    try {
      const typeGroup = XTypeGroup(label: 'JSON', extensions: ['json']);
      final file = await openFile(acceptedTypeGroups: [typeGroup]);
      if (file == null) return;
      final bundle = await provider.backup.restoreFromFile(File(file.path));
      if (bundle.messages.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Backup has no messages to restore.')));
        }
        return;
      }

      var clearExisting = false;
      if (provider.allMessages.isNotEmpty) {
        if (!context.mounted) return;
        final choice = await showDialog<_DeviceRestoreChoice>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Messages already on this device'),
            content: Text(
              'Your phone\'s SMS store already has ${provider.allMessages.length} '
              'messages. The backup has ${bundle.messages.length}.\n\n'
              '"Add to existing" keeps both — this can create duplicates if the '
              'backup was taken from this same device.\n\n'
              '"Clear & replace" permanently deletes every message currently on '
              'the device first, then restores only the backup. This cannot be '
              'undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, _DeviceRestoreChoice.cancel),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, _DeviceRestoreChoice.merge),
                child: const Text('Add to existing'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
                onPressed: () => Navigator.pop(ctx, _DeviceRestoreChoice.clearAndReplace),
                child: const Text('Clear & replace'),
              ),
            ],
          ),
        );
        if (choice == null || choice == _DeviceRestoreChoice.cancel) return;
        clearExisting = choice == _DeviceRestoreChoice.clearAndReplace;
      }

      if (clearExisting) {
        if (!context.mounted) return;
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Clear all SMS on this device?'),
            content: const Text(
              'This permanently deletes every message currently in your phone\'s '
              'SMS store, then restores only what\'s in the backup file. This '
              'cannot be undone.',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Clear & restore'),
              ),
            ],
          ),
        );
        if (confirmed != true) return;
      }

      final inserted = await provider.restoreMessagesToDeviceStore(
        bundle.messages,
        clearExisting: clearExisting,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Restored $inserted messages to the device SMS store.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Restore failed: $e')));
      }
    }
  }
}

enum _DeviceRestoreChoice { cancel, merge, clearAndReplace }

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

/// A "Default" swatch (the tuned terracotta brand color) plus every
/// [AppColors.accentOptions] entry — [selected] is null for Default, or one
/// of those option colors. Swatches rather than a full color wheel: an
/// arbitrary user-picked hue would need its own contrast-safe onPrimary
/// computed on the fly (fine — see [AppTheme]) but would also drift away
/// from every other color already used across the app (categories,
/// direction indicators), so this keeps accent picks visually consistent
/// with the rest of the UI instead of introducing brand-new colors.
class _AccentColorPicker extends StatelessWidget {
  final Color? selected;
  final ValueChanged<Color?> onSelected;
  const _AccentColorPicker({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final defaultColor = isDark ? AppColors.darkPrimary : AppColors.lightPrimary;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Accent color',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: scheme.onSurface),
          ),
          const SizedBox(height: 2),
          Text(
            'Used for buttons, switches, and highlights',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _Swatch(
                label: 'Default',
                color: defaultColor,
                selected: selected == null,
                onTap: () => onSelected(null),
              ),
              for (final entry in AppColors.accentOptions.entries)
                _Swatch(
                  label: entry.key,
                  color: entry.value,
                  selected: selected == entry.value,
                  onTap: () => onSelected(entry.value),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  const _Swatch({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final checkColor =
        ThemeData.estimateBrightnessForColor(color) == Brightness.dark ? Colors.white : Colors.black;
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: selected ? Border.all(color: scheme.onSurface, width: 2.5) : null,
          ),
          child: selected ? Icon(Icons.check, color: checkColor, size: 18) : null,
        ),
      ),
    );
  }
}
