import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../home/home_screen.dart';
import '../profile/profile_screen.dart';
import '../social/friends_screen.dart';
import '../versus/pvp_screen.dart';
import '../solo/solo_screen.dart';
import '../notifications/notifications_screen.dart';
import '../../services/notification_service.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _index = 0;
  bool _isOpeningNotifications = false;

  final Set<int> _visitedTabs = {0};

  void _selectTab(int index) {
    if (_index == index) return;

    setState(() {
      _index = index;
      _visitedTabs.add(index);
    });
  }

  Widget _lazyTab({
    required int tabIndex,
    required Widget child,
  }) {
    if (!_visitedTabs.contains(tabIndex)) {
      return const SizedBox.shrink();
    }

    return child;
  }

  Future<void> _openNotifications() async {
    if (_isOpeningNotifications) return;

    setState(() => _isOpeningNotifications = true);

    try {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const NotificationsScreen(),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isOpeningNotifications = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(
            index: _index,
            children: [
              _lazyTab(
                tabIndex: 0,
                child: const HomeScreen(),
              ),
              _lazyTab(
                tabIndex: 1,
                child: const SoloScreen(),
              ),
              _lazyTab(
                tabIndex: 2,
                child: const PvPScreen(),
              ),
              _lazyTab(
                tabIndex: 3,
                child: const FriendsScreen(),
              ),
              _lazyTab(
                tabIndex: 4,
                child: const ProfileScreen(),
              ),
            ],
          ),

          Positioned(
            top: MediaQuery.of(context).padding.top + 6,
            right: 10,
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: NotificationService.instance
                  .watchMyUnreadNotifications(limit: 1),
              builder: (context, snap) {
                final hasUnread = snap.data?.docs.isNotEmpty ?? false;

                return Material(
                  color: Colors.transparent,
                  child: IconButton(
                    tooltip: 'Notifications',
                    onPressed:
                        _isOpeningNotifications ? null : _openNotifications,
                    icon: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Icon(
                          Icons.notifications_rounded,
                          size: 30,
                          color: hasUnread
                              ? Colors.amber.shade700
                              : Colors.black87,
                        ),
                        if (hasUnread)
                          Positioned(
                            right: -1,
                            top: -1,
                            child: Container(
                              width: 11,
                              height: 11,
                              decoration: BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Theme.of(context)
                                      .scaffoldBackgroundColor,
                                  width: 1.4,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _selectTab,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map),
            label: 'Solo',
          ),
          NavigationDestination(
            icon: Icon(Icons.sports_esports_outlined),
            selectedIcon: Icon(Icons.sports_esports),
            label: 'PvP',
          ),
          NavigationDestination(
            icon: Icon(Icons.group_outlined),
            selectedIcon: Icon(Icons.group),
            label: 'Friends',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}