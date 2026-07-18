import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../home/home_screen.dart';
import '../profile/profile_screen.dart';
import '../social/friends_screen.dart';
import '../versus/pvp_screen.dart';
import '../versus/match_lobby_screen.dart';
import '../solo/solo_screen.dart';
import '../notifications/notifications_screen.dart';
import '../../services/notification_service.dart';
import '../../services/analytics_service.dart';
import '../../widgets/notification_bell_button.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _index = 0;
  bool _isOpeningNotifications = false;

  int _lastUnreadCount = 0;
  bool _hasInitializedUnread = false;
  bool _showNotificationOverlay = false;
  Timer? _overlayTimer;

  String? _lastNotificationId;
  bool _showingChallengeAcceptedDialog = false;
  bool _navigatingToAcceptedChallenge = false;

  final Set<int> _visitedTabs = {0};

  static const _tabNames = ['home', 'solo', 'pvp', 'friends', 'profile'];

  void _selectTab(int index) {
    if (_index == index) return;

    setState(() {
      _index = index;
      _visitedTabs.add(index);
    });

    final tabName = index >= 0 && index < _tabNames.length
        ? _tabNames[index]
        : 'unknown';

    AnalyticsService.instance
        .logNavTabSelected(tab: tabName)
        .catchError((_) {});
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

  Future<void> _checkSpecialNotifications(
    QuerySnapshot<Map<String, dynamic>> snap,
  ) async {
    if (_showingChallengeAcceptedDialog) return;
    if (_navigatingToAcceptedChallenge) return;
    if (_isOpeningNotifications) return;
    if (snap.docs.isEmpty) return;

    final doc = snap.docs.first;

    if (_lastNotificationId == doc.id) return;
    _lastNotificationId = doc.id;

    final notification = doc.data();
    final type = (notification['type'] ?? '').toString();

    if (type != 'realtime_invite_accepted') return;

    final payload = Map<String, dynamic>.from(notification['data'] ?? {});
    final matchId = (payload['matchId'] ?? '').toString();

    if (matchId.isEmpty || !mounted) return;

    _showingChallengeAcceptedDialog = true;

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        final body = (notification['body'] ?? '').toString();

        return AlertDialog(
          title: const Row(
            children: [
              Icon(
                Icons.sports_esports,
                color: Colors.deepPurple,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text('Reto aceptado'),
              ),
            ],
          ),
          content: Text(
            body.isEmpty ? 'Tu invitación fue aceptada.' : body,
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
              },
              child: const Text('Luego'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(dialogContext);

                if (!mounted) return;

                setState(() {
                  _navigatingToAcceptedChallenge = true;
                  _showNotificationOverlay = false;
                });

                try {
                  await NotificationService.instance.markAsRead(
                    notificationId: doc.id,
                  );
                } catch (_) {}

                if (!mounted) return;

                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MatchLobbyScreen(
                      matchId: matchId,
                    ),
                  ),
                );

                if (!mounted) return;

                setState(() {
                  _navigatingToAcceptedChallenge = false;
                });
              },
              child: const Text('Jugar ahora'),
            ),
          ],
        );
      },
    );

    _showingChallengeAcceptedDialog = false;
  }

  Future<void> _openNotifications() async {
    if (_isOpeningNotifications) return;

    setState(() {
      _isOpeningNotifications = true;
      _showNotificationOverlay = false;
    });

    _overlayTimer?.cancel();

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

  void _handleUnreadCountChanged(int unreadCount) {
    if (!_hasInitializedUnread) {
      _hasInitializedUnread = true;
      _lastUnreadCount = unreadCount;
      return;
    }

    if (unreadCount > _lastUnreadCount && !_isOpeningNotifications) {
      _showBigNotificationOverlay();
    }

    _lastUnreadCount = unreadCount;
  }

  void _showBigNotificationOverlay() {
    _overlayTimer?.cancel();

    if (!mounted) return;

    setState(() => _showNotificationOverlay = true);

    _overlayTimer = Timer(const Duration(milliseconds: 2200), () {
      if (!mounted) return;
      setState(() => _showNotificationOverlay = false);
    });
  }

  @override
  void dispose() {
    _overlayTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: NotificationService.instance.watchMyUnreadNotifications(
          limit: 99,
        ),
        builder: (context, snap) {
          final unreadSnapshot = snap.data;
          final unreadCount = unreadSnapshot?.docs.length ?? 0;

          if (unreadSnapshot != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              _checkSpecialNotifications(unreadSnapshot);
            });
          }

          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _handleUnreadCountChanged(unreadCount);
          });

          return Stack(
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
                child: Material(
                  color: Colors.transparent,
                  child: NotificationBellButton(
                    unreadCount: unreadCount,
                    onPressed:
                        _isOpeningNotifications ? () {} : _openNotifications,
                  ),
                ),
              ),
              if (_showNotificationOverlay) const _NewNotificationOverlay(),
            ],
          );
        },
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

class _NewNotificationOverlay extends StatelessWidget {
  const _NewNotificationOverlay();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.75, end: 1.0),
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutBack,
          builder: (context, scale, child) {
            return Transform.scale(
              scale: scale,
              child: child,
            );
          },
          child: AnimatedOpacity(
            opacity: 1,
            duration: const Duration(milliseconds: 250),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 28,
                vertical: 22,
              ),
              decoration: BoxDecoration(
                color: Colors.amber.shade700,
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.28),
                    blurRadius: 22,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.notifications_active,
                    color: Colors.white,
                    size: 58,
                  ),
                  SizedBox(height: 10),
                  Text(
                    'Nueva notificación',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 23,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Revisa la campana',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}