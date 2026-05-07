import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../daily/daily_challenge_screen.dart';
import '../solo/level_select_screen.dart';
import '../../services/daily_challenge_service.dart';
import '../../services/life_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Map<String, dynamic>? _lifeState;
  bool _loadingLives = true;
  Timer? _lifeTimer;

  int? _lastSeenStreak;
  bool _showStreakPopup = false;
  bool _streakGlow = false;

  late final String uid;

  @override
  void initState() {
    super.initState();
    uid = FirebaseAuth.instance.currentUser!.uid;
    _initLives();
    _startLifeTimer();
  }

  Future<void> _initLives() async {
    await LifeService.instance.ensureUserLifeDoc(uid);
    await _refreshLives();
  }

  void _startLifeTimer() {
    _lifeTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _refreshLives();
    });
  }

  Future<void> _refreshLives() async {
    final state = await LifeService.instance.refreshLives(uid);

    if (!mounted) return;

    setState(() {
      _lifeState = state;
      _loadingLives = false;
    });
  }

  void _handleStreakChange(int streak) {
    if (_lastSeenStreak == null) {
      _lastSeenStreak = streak;
      return;
    }

    if (streak > _lastSeenStreak!) {
      _lastSeenStreak = streak;

      HapticFeedback.mediumImpact();

      setState(() {
        _showStreakPopup = true;
        _streakGlow = true;
      });

      Future.delayed(const Duration(milliseconds: 1300), () {
        if (!mounted) return;
        setState(() {
          _showStreakPopup = false;
          _streakGlow = false;
        });
      });
    } else {
      _lastSeenStreak = streak;
    }
  }

  @override
  void dispose() {
    _lifeTimer?.cancel();
    super.dispose();
  }

  String _formatCountdown(int? totalSeconds) {
    if (totalSeconds == null) return '--:--';
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;
    final userRef = db.collection('users').doc(uid);

    final categoriesQuery =
        db.collection('fixed_categories').where('isActive', isEqualTo: true);

    return Scaffold(
      appBar: AppBar(
        title: const Text('TriviaIA'),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: userRef.snapshots(),
                  builder: (context, snap) {
                    if (!snap.hasData) {
                      return const LinearProgressIndicator();
                    }

                    final data = snap.data!.data() ?? {};
                    final coins = data['coins'] ?? 0;
                    final xp = data['xp'] ?? 0;
                    final passes = data['freeTopicPasses'] ?? 0;
                    final streak = ((data['dailyStreak'] ?? 0) as num).toInt();

                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) _handleStreakChange(streak);
                    });

                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.black12,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: _StatCard(
                                  icon: Icons.favorite,
                                  label: 'Vidas',
                                  value: _lifeState == null
                                      ? '...'
                                      : '${LifeService.instance.formatLives(_lifeState!['lifeUnits'])} / ${LifeService.instance.formatLives(_lifeState!['maxLifeUnits'])}',
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _StatCard(
                                  icon: Icons.timer,
                                  label: 'Recarga',
                                  value: _lifeState == null
                                      ? '--:--'
                                      : _formatCountdown(
                                          _lifeState![
                                              'secondsToNextHalfLife'],
                                        ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _StatCard(
                                  icon: Icons.monetization_on,
                                  label: 'Monedas',
                                  value: '$coins',
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _StatCard(
                                  icon: Icons.auto_awesome,
                                  label: 'XP',
                                  value: '$xp',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _StatCard(
                            icon: Icons.style,
                            label: 'Tema libre',
                            value: '$passes',
                            fullWidth: true,
                          ),
                          const SizedBox(height: 14),
                          _StreakCard(
                            streak: streak,
                            glow: _streakGlow,
                          ),
                        ],
                      ),
                    );
                  },
                ),

                const SizedBox(height: 16),

                FilledButton.icon(
                  onPressed: () async {
                    final alreadyPlayed =
                        await DailyChallengeService.instance.hasPlayedToday(uid);

                    if (!context.mounted) return;

                    if (alreadyPlayed) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Ya jugaste el Daily hoy'),
                        ),
                      );
                      return;
                    }

                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => DailyChallengeScreen(uid: uid),
                      ),
                    );
                  },
                  icon: const Icon(Icons.calendar_today),
                  label: const Text('Daily Challenge'),
                ),

                const SizedBox(height: 20),

                Expanded(
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: categoriesQuery.snapshots(),
                    builder: (context, snap) {
                      if (!snap.hasData) {
                        return const Center(
                          child: CircularProgressIndicator(),
                        );
                      }

                      final docs = snap.data!.docs;

                      return ListView.builder(
                        itemCount: docs.length,
                        itemBuilder: (_, i) {
                          final doc = docs[i];
                          final data = doc.data();
                          final name = (data['name'] ?? doc.id).toString();

                          return ListTile(
                            title: Text(name),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => LevelSelectScreen(
                                    categoryId: doc.id,
                                    categoryName: name,
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),

          if (_showStreakPopup)
            Center(
              child: AnimatedScale(
                scale: _showStreakPopup ? 1.0 : 0.7,
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutBack,
                child: AnimatedOpacity(
                  opacity: _showStreakPopup ? 1 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 26,
                      vertical: 18,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.deepOrange.withOpacity(0.95),
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '🔥 STREAK UP!',
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(height: 6),
                        Text(
                          'Keep coming back daily',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool fullWidth;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    this.fullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: fullWidth ? double.infinity : null,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon),
          const SizedBox(width: 8),
          Expanded(child: Text('$label: $value')),
        ],
      ),
    );
  }
}

class _StreakCard extends StatelessWidget {
  final int streak;
  final bool glow;

  const _StreakCard({
    required this.streak,
    required this.glow,
  });

  Color _color() {
    if (streak >= 7) return Colors.red;
    if (streak >= 3) return Colors.orange;
    return Colors.grey;
  }

  String _subtitle() {
    if (streak >= 14) return 'Legendary streak!';
    if (streak >= 7) return 'On fire!';
    if (streak >= 3) return 'Keep it going!';
    return 'Start your streak today';
  }

  @override
  Widget build(BuildContext context) {
    final color = _color();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(glow ? 0.30 : 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withOpacity(glow ? 0.9 : 0.35),
          width: glow ? 2 : 1,
        ),
        boxShadow: glow
            ? [
                BoxShadow(
                  color: color.withOpacity(0.45),
                  blurRadius: 18,
                  spreadRadius: 2,
                ),
              ]
            : [],
      ),
      child: Row(
        children: [
          AnimatedScale(
            scale: glow ? 1.25 : 1.0,
            duration: const Duration(milliseconds: 300),
            child: Icon(
              Icons.local_fire_department,
              color: color,
              size: 30,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Streak: $streak días',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: color,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _subtitle(),
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
          if (streak > 0 && streak % 3 == 0)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                color: Colors.amber,
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text(
                'Reward!',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: Colors.black,
                ),
              ),
            ),
        ],
      ),
    );
  }
}