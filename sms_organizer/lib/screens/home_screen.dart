import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/sms_provider.dart';
import 'all_messages_tab.dart';
import 'conversations_tab.dart';
import 'compose_screen.dart';
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
  StreamSubscription<int>? _threadTapSub;

  final _tabs = const [
    ConversationsTab(),
    AllMessagesTab(),
    InsightsScreen(),
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _tabIndex, children: _tabs),
      floatingActionButton: _tabIndex <= 1
          ? FloatingActionButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ComposeScreen()),
              ),
              child: const Icon(Icons.edit_outlined),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (i) => setState(() => _tabIndex = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.chat_bubble_outline), label: 'Chats'),
          NavigationDestination(icon: Icon(Icons.list_alt_outlined), label: 'All'),
          NavigationDestination(icon: Icon(Icons.insights_outlined), label: 'Insights'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'Settings'),
        ],
      ),
    );
  }
}
