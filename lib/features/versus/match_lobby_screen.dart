import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/match_service.dart';
import '../../services/presence_service.dart';
import '../../widgets/player_avatar_widget.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../theme/app_theme.dart';
import 'match_play_screen.dart';

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

  bool _navigatingToMatch = false;

  @override
  void initState() {
    super.initState();

    Future.microtask(() async {
      try {
        await _presenceService.setInMatch();
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    if (!_navigatingToMatch) {
      _presenceService.setAvailable();
    }

    super.dispose();
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

  String _displayCategory(AppLocalizations l10n, String categoryId) {
    if (categoryId == 'random') return l10n.friendChallengeCategoryRandom;
    if (categoryId.isEmpty) return l10n.createMatchCategory;
    return categoryId[0].toUpperCase() + categoryId.substring(1);
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
    final ref =
        FirebaseFirestore.instance.collection('matches').doc(widget.matchId);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.matchLobbyTitle),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: ref.snapshots(),
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
              ((data['timePerQuestionSec'] ?? 10) as num).toInt();

          final hostUid = (data['hostUid'] ?? '').toString();
          final guestUid = (data['guestUid'] ?? '').toString();

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
                    borderRadius: BorderRadius.circular(26),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.22),
                    ),
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
                        style: GoogleFonts.baloo2(
                          fontSize: 25,
                          fontWeight: FontWeight.w800,
                        ),
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
                    _InfoRow(
                      icon: Icons.category_outlined,
                      label: l10n.matchLobbyTopicLabel,
                      value: _displayCategory(l10n, categoryId),
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
        borderRadius: BorderRadius.circular(22),
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
    final Color borderColor = ready ? AppColors.success : AppColors.reward;

    final IconData icon =
        ready ? Icons.check_circle_outline : Icons.access_time;

    final String statusText = waiting
        ? l10n.matchLobbyWaitingOpponentEllipsis
        : ready
            ? l10n.matchLobbyReadyLabel
            : l10n.matchLobbyWaitingLabel;

    final Color statusColor = ready ? AppColors.success : AppColors.reward;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ready
            ? AppColors.success.withValues(alpha: 0.10)
            : AppColors.reward.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: borderColor,
        ),
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
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.18),
        ),
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
