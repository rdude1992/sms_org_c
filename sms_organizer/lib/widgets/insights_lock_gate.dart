import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/security_settings_provider.dart';

/// Wraps [child] (the Insights or Accounts tab) behind a lock screen while
/// SecuritySettingsProvider.lockEnabled is on and the app hasn't been
/// unlocked yet this session. Both are PageView tabs kept alive for the
/// app's whole lifetime (see HomeScreen._KeepAlivePage), not pushed routes,
/// so this can't rely on a route guard — instead it observes app lifecycle
/// directly and re-locks on every backgrounding, regardless of which tab
/// happens to be showing at the time. [SecuritySettingsProvider]'s
/// unlock/lock state is shared app-wide, so unlocking from either gated tab
/// unlocks both — no double authentication prompt.
class InsightsLockGate extends StatefulWidget {
  final Widget child;

  /// Shown in the lock screen's title ("$label is locked") and used to
  /// distinguish which tab's gate this is — defaults to "Insights" so the
  /// existing call site doesn't need updating.
  final String label;

  const InsightsLockGate({super.key, required this.child, this.label = 'Insights'});

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
    return _InsightsLockScreen(label: widget.label);
  }
}

class _InsightsLockScreen extends StatefulWidget {
  final String label;
  const _InsightsLockScreen({required this.label});

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
                '${widget.label} is locked',
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
