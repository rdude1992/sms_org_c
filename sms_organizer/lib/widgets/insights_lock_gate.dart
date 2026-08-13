import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/security_settings_provider.dart';

/// Wraps [child] (the Insights tab) behind a lock screen while
/// SecuritySettingsProvider.lockEnabled is on and the app hasn't been
/// unlocked yet this session. It's a PageView tab kept alive for the app's
/// whole lifetime (see HomeScreen._KeepAlivePage), not a pushed route, so
/// this can't rely on a route guard — instead it observes app lifecycle
/// directly and re-locks on every backgrounding, regardless of which tab
/// happens to be showing at the time.
class InsightsLockGate extends StatefulWidget {
  final Widget child;

  const InsightsLockGate({super.key, required this.child});

  @override
  State<InsightsLockGate> createState() => _InsightsLockGateState();
}

class _InsightsLockGateState extends State<InsightsLockGate> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      context.read<SecuritySettingsProvider>().lock();
    }
  }

  @override
  Widget build(BuildContext context) {
    final security = context.watch<SecuritySettingsProvider>();
    if (!security.lockEnabled || security.isUnlocked) return widget.child;
    return const _InsightsLockScreen();
  }
}

class _InsightsLockScreen extends StatefulWidget {
  const _InsightsLockScreen();

  @override
  State<_InsightsLockScreen> createState() => _InsightsLockScreenState();
}

class _InsightsLockScreenState extends State<_InsightsLockScreen> {
  bool _authenticating = false;
  bool _failed = false;

  Future<void> _unlock() async {
    setState(() {
      _authenticating = true;
      _failed = false;
    });
    final ok = await context.read<SecuritySettingsProvider>().authenticate();
    if (!mounted) return;
    setState(() {
      _authenticating = false;
      _failed = !ok;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline, size: 56, color: scheme.onSurfaceVariant),
              const SizedBox(height: 16),
              Text(
                'Insights is locked',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: scheme.onSurface),
              ),
              const SizedBox(height: 8),
              Text(
                "Verify it's you to view your transactions and spending.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _authenticating ? null : _unlock,
                icon: _authenticating
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.fingerprint),
                label: Text(_authenticating ? 'Verifying…' : 'Unlock'),
              ),
              if (_failed) ...[
                const SizedBox(height: 12),
                Text(
                  'Authentication failed — try again.',
                  style: TextStyle(fontSize: 12.5, color: scheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
