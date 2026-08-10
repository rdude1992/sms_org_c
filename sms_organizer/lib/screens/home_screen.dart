import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/sms_provider.dart';
import '../widgets/insights_lock_gate.dart';
import '../widgets/ui/floating_nav_bar.dart';
import 'compose_screen.dart';
import 'inbox_screen.dart';
import 'insights_screen.dart';
import 'settings_screen.dart';
import 'thread_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tabIndex = 0;
  final _pageController = PageController();
  StreamSubscription<int>? _threadTapSub;

  final _tabs = const [
    InboxScreen(),
    InsightsLockGate(child: InsightsScreen()),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();

    final provider = context.read<SmsProvider>();

    // Warm case: app already running, a notification was tapped. Subscribe
    // before anything async below so a tap during startup isn't missed.
    _threadTapSub = provider.onNotificationThreadTapped.listen(_openThread);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await provider.initialize();
      if (!mounted) return;

      final composeExtras = await provider.checkLaunchComposeExtras();
      if (composeExtras != null && mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ComposeScreen(
              initialAddress: composeExtras['address'],
              initialBody: composeExtras['body'],
            ),
          ),
        );
        return;
      }

      // Cold-start case: app was fully killed and relaunched by tapping a
      // notification, so there's no onNewIntent to push a live event —
      // read it directly off the launch intent instead.
      final threadId = await provider.checkLaunchNotificationThreadId();
      if (threadId != null) _openThread(threadId);
    });
  }

  void _openThread(int threadId) {
    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => ThreadScreen(threadId: threadId)));
  }

  @override
  void dispose() {
    _threadTapSub?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _goToTab(int index) {
    setState(() => _tabIndex = index);
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Swipe left/right to switch tabs, same as the drilldown tabs — each
      // page keeps its state alive (provider-backed, but InsightsScreen's
      // local filter selection lives in widget state) via _KeepAlivePage so
      // swiping away and back doesn't reset it.
      body: PageView(
        controller: _pageController,
        // Swiping between main tabs conflicts with swiping between category
        // tabs / list-item slide actions within each tab — the bottom nav
        // bar is the only way to switch tabs, so this only animates via
        // _goToTab's programmatic animateToPage.
        physics: const NeverScrollableScrollPhysics(),
        onPageChanged: (i) => setState(() => _tabIndex = i),
        children: [for (final tab in _tabs) _KeepAlivePage(child: tab)],
      ),
      floatingActionButton: _tabIndex == 0
          ? FloatingActionButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ComposeScreen()),
              ),
              child: const Icon(Icons.edit_outlined),
            )
          : null,
      bottomNavigationBar: FloatingNavBar(
        selectedIndex: _tabIndex,
        onSelected: _goToTab,
        items: const [
          FloatingNavItem(icon: Icons.inbox_outlined, selectedIcon: Icons.inbox, label: 'Inbox'),
          FloatingNavItem(icon: Icons.insights_outlined, selectedIcon: Icons.insights, label: 'Insights'),
          FloatingNavItem(icon: Icons.settings_outlined, selectedIcon: Icons.settings, label: 'Settings'),
        ],
      ),
    );
  }
}

/// Keeps a PageView child mounted (and its state, if it has any — e.g.
/// InsightsScreen's date-range filter) after it scrolls off-screen, instead
/// of PageView's default of disposing pages that aren't the current or
/// adjacent one.
class _KeepAlivePage extends StatefulWidget {
  final Widget child;
  const _KeepAlivePage({required this.child});

  @override
  State<_KeepAlivePage> createState() => _KeepAlivePageState();
}

class _KeepAlivePageState extends State<_KeepAlivePage> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
