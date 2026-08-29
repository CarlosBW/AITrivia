import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/match_service.dart';
import '../../services/presence_service.dart';
import '../../widgets/player_avatar_widget.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../theme/app_theme.dart';
import 'match_play_screen.dart';
import '../../widgets/profile_avatar_button.dart';

class MatchLobbyScreen extends StatefulWidget {
  final String matchId;

  const MatchLobbyScreen({
    super.key,
    required this.matchId,
  });

  @override
  State<MatchLobbyScreen> createState() => _MatchLobbyScreenState();
}

class _MatchLobbyScreenState extends State<MatchLobbyScreen> {
  final _presenceService = PresenceService.instance;
  final _service = MatchService();

  // Held rather than rebuilt in `build()`: the opponent-presence poll ticks
  // every ten seconds, and each tick used to re-subscribe this.
  late final _matchDoc = FirebaseFirestore.instance
      .collection('matches')
      .doc(widget.matchId)
      .snapshots();

  bool _navigatingToMatch = false;

  // Updated on every StreamBuilder snapshot so the periodic presence timer
  // below always checks the current opponent, not a stale one captured at
  // initState time.
  String? _opponentUid;
  DateTime? _opponentUnavailableSince;
  Timer? _opponentPresenceTimer;

  // Memoized so the fixed_categories lookup only ever runs once per
  // categoryId, no matter how many times the StreamBuilder below rebuilds.
  final Map<String, Future<String>> _categoryNameFutures = {};

  @override
  void initState() {
    super.initState();

    Future.microtask(() async {
      try {
        await _presenceService.setInMatch();
      } catch (_) {}
    });

    // No per-second countdown exists in the lobby (unlike match_play_screen)
    // to naturally keep rebuilding, so this timer is what actually drives
    // periodic re-checks — without it, a player left alone here after the
    // other side leaves would wait forever with no way out.
    _opponentPresenceTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _checkOpponentPresence();
    });
  }

  @override
  void dispose() {
    _opponentPresenceTimer?.cancel();

    if (!_navigatingToMatch) {
      _presenceService.setAvailable();
    }

    super.dispose();
  }

  Future<void> _checkOpponentPresence() async {
    if (!mounted) return;

    final opponentUid = _opponentUid;
    if (opponentUid == null || opponentUid.isEmpty) return;

    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(opponentUid)
          .get();

      final presence = Map<String, dynamic>.from(
        snap.data()?['presence'] as Map? ?? {},
      );

      if (_presenceService.isProbablyOnline(presence)) {
        _opponentUnavailableSince = null;
        return;
      }

      _opponentUnavailableSince ??= DateTime.now();

      final unavailableFor = DateTime.now().difference(
        _opponentUnavailableSince!,
      );

      if (unavailableFor < const Duration(seconds: 30)) return;

      // Sets status: 'cancelled' — the existing StreamBuilder below already
      // watches for that and leaves with a snackbar, so no new UI is needed
      // here beyond triggering it.
      await _service.cancelWaitingMatch(widget.matchId);
    } catch (_) {}
  }

  Future<void> _leaveBecauseMatchUnavailable(String message) async {
    if (_navigatingToMatch) return;

    _navigatingToMatch = true;

    try {
      await _presenceService.setAvailable();
    } catch (_) {}

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );

    Navigator.pop(context);
  }

  // Shows the real fixed_categories name (e.g. "Música") instead of the
  // raw doc id (e.g. "musica") stored on the match doc.
  Future<String> _displayCategory(AppLocalizations l10n, String categoryId) {
    if (categoryId == 'random') {
      return Future.value(l10n.friendChallengeCategoryRandom);
    }
    if (categoryId.isEmpty) {
      return Future.value(l10n.createMatchCategory);
    }

    return _categoryNameFutures.putIfAbsent(categoryId, () async {
      try {
        final snap = await FirebaseFirestore.instance
            .collection('fixed_categories')
            .doc(categoryId)
            .get();
        final name = snap.data()?['name'];
        if (name is String && name.isNotEmpty) return name;
      } catch (_) {}

      return categoryId[0].toUpperCase() + categoryId.substring(1);
    });
  }

  String _statusText(
    AppLocalizations l10n, {
    required bool myReady,
    required bool opponentReady,
    required bool hasGuest,
  }) {
    if (!hasGuest) {
      return l10n.matchLobbyWaitingFriendJoin;
    }

    if (myReady && opponentReady) {
      return l10n.matchLobbyAllReadyStarting;
    }

    if (myReady && !opponentReady) {
      return l10n.matchLobbyReadyWaitingOpponent;
    }

    if (!myReady && opponentReady) {
      return l10n.matchLobbyOpponentReadyConfirm;
    }

    return l10n.matchLobbyWaitingBothReady;
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final service = MatchService();
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        actions: const [ProfileAvatarButton()],
        title: Text(l10n.matchLobbyTitle),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _matchDoc,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = snap.data!.data();

          if (data == null) {
            return Center(child: Text(l10n.matchLobbyNotFound));
          }

          final status = (data['status'] ?? 'waiting').toString();

          if ((status == 'cancelled' || status == 'expired') &&
              !_navigatingToMatch) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              _leaveBecauseMatchUnavailable(
                l10n.matchLobbyNoLongerAvailable,
              );
            });
          }

          if (status == 'playing' && !_navigatingToMatch) {
            _navigatingToMatch = true;

            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!context.mounted) return;

              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (_) => MatchPlayScreen(
                    matchId: widget.matchId,
                  ),
                ),
              );
            });
          }

          final mode = (data['mode'] ?? 'fixed').toString();
          final categoryId = (data['categoryId'] ?? 'cine').toString();
          final code = (data['matchCode'] ?? widget.matchId).toString();

          final totalQuestions =
              ((data['totalQuestions'] ?? 10) as num).toInt();
          final timePerQuestionSec =
              ((data['timePerQuestionSec'] ?? 15) as num).toInt();

          final hostUid = (data['hostUid'] ?? '').toString();
          final guestUid = (data['guestUid'] ?? '').toString();

          final opponentUid = uid == hostUid ? guestUid : hostUid;
          _opponentUid = opponentUid.isEmpty ? null : opponentUid;

          final players = Map<String, dynamic>.from(data['players'] ?? {});

          final hostPlayer = Map<String, dynamic>.from(
            players[hostUid] ?? {},
          );
          final guestPlayer = Map<String, dynamic>.from(
            players[guestUid] ?? {},
          );
          final me = Map<String, dynamic>.from(players[uid] ?? {});

          final hostName =
              (hostPlayer['displayName'] ?? l10n.matchLobbyPlayer1).toString();
          final guestName = guestUid.isEmpty
              ? l10n.matchLobbyWaitingOpponentButton
              : (guestPlayer['displayName'] ?? l10n.matchLobbyPlayer2).toString();

          final hostReady = hostPlayer['ready'] == true;
          final guestReady = guestPlayer['ready'] == true;
          final myReady = me['ready'] == true;

          final opponentReady = uid == hostUid ? guestReady : hostReady;
          final hasGuest = guestUid.isNotEmpty;

          final statusMessage = _statusText(
            l10n,
            myReady: myReady,
            opponentReady: opponentReady,
            hasGuest: hasGuest,
          );

          return SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(18),
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(context.radii.lg),
                    boxShadow: context.surfaces.shadowsOr(null),
                    border: context.surfaces.borderOr(Border.all(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.22),
                    )),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        '⚔️',
                        style: TextStyle(fontSize: 48),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l10n.matchLobbyHeading,
                        style: context.heading(25),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        statusMessage,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _InfoCard(
                  children: [
                    FutureBuilder<String>(
                      future: _displayCategory(l10n, categoryId),
                      builder: (context, snap) {
                        return _InfoRow(
                          icon: Icons.category_outlined,
                          label: l10n.matchLobbyTopicLabel,
                          value: snap.data ?? categoryId,
                        );
                      },
                    ),
                    _InfoRow(
                      icon: Icons.auto_awesome_outlined,
                      label: l10n.matchLobbyModeLabel,
                      value: mode == 'fixed' ? l10n.matchLobbyModeFixed : l10n.matchLobbyModeAi,
                    ),
                    _InfoRow(
                      icon: Icons.quiz_outlined,
                      label: l10n.createMatchQuestions,
                      value: '$totalQuestions',
                    ),
                    _InfoRow(
                      icon: Icons.timer_outlined,
                      label: l10n.matchLobbyTimeLabel,
                      value: l10n.matchLobbySecondsPerQuestion(timePerQuestionSec),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _PlayersCard(
                  hostPlayer: hostPlayer,
                  guestPlayer: guestPlayer,
                  hostName: hostName,
                  guestName: guestName,
                  hostReady: hostReady,
                  guestReady: guestReady,
                  hasGuest: hasGuest,
                ),
                const SizedBox(height: 16),
                _RoomCodeCard(
                  code: code,
                  onCopy: () async {
                    await Clipboard.setData(
                      ClipboardData(text: code),
                    );

                    if (!context.mounted) return;

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(l10n.matchLobbyCodeCopied),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 24),
                if (status == 'waiting') ...[
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: !hasGuest || myReady
                          ? null
                          : () async {
                              await service.setReady(
                                widget.matchId,
                                true,
                              );
                            },
                      icon: Icon(
                        myReady
                            ? Icons.hourglass_top
                            : Icons.check_circle_outline,
                      ),
                      label: Text(
                        !hasGuest
                            ? l10n.matchLobbyWaitingOpponentButton
                            : myReady
                                ? l10n.matchLobbyWaitingOpponentEllipsis
                                : l10n.matchLobbyImReady,
                      ),
                    ),
                  ),
                  if (myReady) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () async {
                          await service.setReady(
                            widget.matchId,
                            false,
                          );
                        },
                        child: Text(l10n.matchLobbyCancelReady),
                      ),
                    ),
                  ],
                ] else if (status != 'playing') ...[
                  Center(
                    child: Text(
                      l10n.matchLobbyRoomStatus(status),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final List<Widget> children;

  const _InfoCard({
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(context.radii.lg),
        border: context.surfaces.borderOr(null),
        boxShadow: context.surfaces.shadowsOr(null),
      ),
      child: Column(
        children: children,
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Icon(icon, size: 22, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlayersCard extends StatelessWidget {
  final Map<String, dynamic> hostPlayer;
  final Map<String, dynamic> guestPlayer;
  final String hostName;
  final String guestName;
  final bool hostReady;
  final bool guestReady;
  final bool hasGuest;

  const _PlayersCard({
    required this.hostPlayer,
    required this.guestPlayer,
    required this.hostName,
    required this.guestName,
    required this.hostReady,
    required this.guestReady,
    required this.hasGuest,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _PlayerStatusCard(
          player: hostPlayer,
          name: hostName,
          ready: hostReady,
          waiting: false,
        ),
        const SizedBox(height: 12),
        _PlayerStatusCard(
          player: guestPlayer,
          name: guestName,
          ready: hasGuest && guestReady,
          waiting: !hasGuest,
        ),
      ],
    );
  }
}

class _PlayerStatusCard extends StatelessWidget {
  final Map<String, dynamic> player;
  final String name;
  final bool ready;
  final bool waiting;

  const _PlayerStatusCard({
    required this.player,
    required this.name,
    required this.ready,
    this.waiting = false,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final Color borderColor = ready ? context.appColors.success : context.appColors.reward;

    final IconData icon =
        ready ? Icons.check_circle_outline : Icons.access_time;

    final String statusText = waiting
        ? l10n.matchLobbyWaitingOpponentEllipsis
        : ready
            ? l10n.matchLobbyReadyLabel
            : l10n.matchLobbyWaitingLabel;

    final Color statusColor = ready ? context.appColors.success : context.appColors.reward;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ready
            ? context.appColors.success.withValues(alpha: 0.10)
            : context.appColors.reward.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(context.radii.md),
        boxShadow: context.surfaces.shadowsOr(null),
        border: context.surfaces.borderOr(Border.all(
          color: borderColor,
        )),
      ),
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              PlayerAvatarWidget.fromPlayer(
                waiting ? null : player,
                radius: 26,
              ),
              Positioned(
                bottom: -2,
                right: -2,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    size: 18,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  statusText,
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RoomCodeCard extends StatelessWidget {
  final String code;
  final VoidCallback onCopy;

  const _RoomCodeCard({
    required this.code,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(context.radii.lg),
        boxShadow: context.surfaces.shadowsOr(null),
        border: context.surfaces.borderOr(Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.18),
        )),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.matchLobbyRoomCodeLabel,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          SelectableText(
            code,
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onCopy,
              icon: const Icon(Icons.copy_outlined),
              label: Text(l10n.matchLobbyCopyCodeButton),
            ),
          ),
        ],
      ),
    );
  }
}
