import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../providers/sms_provider.dart';
import 'home_screen.dart';

class PermissionOnboardingScreen extends StatefulWidget {
  const PermissionOnboardingScreen({super.key});

  @override
  State<PermissionOnboardingScreen> createState() => _PermissionOnboardingScreenState();
}

class _PermissionOnboardingScreenState extends State<PermissionOnboardingScreen> {
  bool _requesting = false;
  bool _permissionsGranted = false;

  @override
  void initState() {
    super.initState();
    _checkExisting();
  }

  Future<void> _checkExisting() async {
    final granted = await _hasRuntimePermissions();
    final smsProvider = context.read<SmsProvider>();
    final isDefault = await smsProvider.checkIsDefaultSmsApp();
    if (granted && isDefault) {
      _goToHome();
    } else {
      setState(() => _permissionsGranted = granted);
    }
  }

  Future<bool> _hasRuntimePermissions() async {
    final sms = await Permission.sms.status;
    final contacts = await Permission.contacts.status;
    return sms.isGranted && contacts.isGranted;
  }

  Future<void> _requestRuntimePermissions() async {
    setState(() => _requesting = true);
    final results = await [
      Permission.sms,
      Permission.contacts,
      Permission.notification,
      // For dual-SIM detection (which SIM sent/received each message, and
      // choosing a SIM to send from) — best-effort, so it's requested here
      // but doesn't gate _permissionsGranted below.
      Permission.phone,
    ].request();
    final granted = results[Permission.sms]?.isGranted ?? false;
    setState(() {
      _requesting = false;
      _permissionsGranted = granted;
    });
  }

  Future<void> _requestDefaultApp() async {
    setState(() => _requesting = true);
    final provider = context.read<SmsProvider>();
    final isDefault = await provider.requestDefaultSmsRole();
    setState(() => _requesting = false);
    if (isDefault) {
      _goToHome();
    }
  }

  void _goToHome() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(),
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(Icons.forum_outlined, size: 30, color: Theme.of(context).colorScheme.primary),
              ),
              const SizedBox(height: 24),
              Text('Set up SmartSMS', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 12),
              Text(
                'To read, send, and organise your messages — including detecting '
                'transactions and investments from bank SMS — this app needs a '
                'couple of permissions and needs to become your default SMS app.',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.4),
              ),
              const SizedBox(height: 32),
              _StepTile(
                step: 1,
                title: 'Grant SMS & contacts permission',
                done: _permissionsGranted,
                onPressed: _permissionsGranted ? null : _requestRuntimePermissions,
              ),
              const SizedBox(height: 12),
              _StepTile(
                step: 2,
                title: 'Set as default SMS app',
                subtitle: 'Required so the app can receive and send messages directly.',
                done: false,
                onPressed: _permissionsGranted ? _requestDefaultApp : null,
              ),
              const Spacer(),
              if (_requesting) const Center(child: CircularProgressIndicator()),
              const SizedBox(height: 8),
              Text(
                'Your messages stay on your device. Nothing is uploaded anywhere by this app.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepTile extends StatelessWidget {
  final int step;
  final String title;
  final String? subtitle;
  final bool done;
  final VoidCallback? onPressed;

  const _StepTile({
    required this.step,
    required this.title,
    required this.done,
    this.subtitle,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: CircleAvatar(
          backgroundColor: done ? const Color(0xFF10B981) : Theme.of(context).colorScheme.primary,
          foregroundColor: Colors.white,
          child: done ? const Icon(Icons.check) : Text('$step'),
        ),
        title: Text(title),
        subtitle: subtitle != null ? Text(subtitle!) : null,
        trailing: done
            ? null
            : FilledButton(
                onPressed: onPressed,
                child: const Text('Grant'),
              ),
      ),
    );
  }
}
