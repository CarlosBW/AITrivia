import 'package:flutter/material.dart';

import '../../services/match_service.dart';
import '../../services/realtime_invite_service.dart';
import 'async_match_play_screen.dart';

class FriendChallengeSetupScreen extends StatefulWidget {
  final String friendUid;
  final String friendName;
  final bool isOnline;

  const FriendChallengeSetupScreen({
    super.key,
    required this.friendUid,
    required this.friendName,
    required this.isOnline,
  });

  @override
  State<FriendChallengeSetupScreen> createState() =>
      _FriendChallengeSetupScreenState();
}

class _FriendChallengeSetupScreenState
    extends State<FriendChallengeSetupScreen> {
  final _matchService = MatchService();
  final _realtimeInviteService = RealtimeInviteService.instance;

  bool _loading = false;
  String? _error;

  Future<void> _startAsyncChallenge() async {
    if (_loading) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final myName = await _matchService.getMyDisplayNameFallback('Player');

      final matchId = await _matchService.createAsyncFixedMatch(
        challengedUid: widget.friendUid,
        categoryId: 'random',
        difficulty: 1,
        totalQuestions: 10,
        timePerQuestionSec: 10,
        winReward: 2,
        challengerDisplayName: myName,
        challengedDisplayName: widget.friendName,
      );

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => AsyncMatchPlayScreen(asyncMatchId: matchId),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _startRealtimeChallenge() async {
    if (_loading) return;

    if (!widget.isOnline) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Tu amigo no está conectado para jugar en tiempo real.',
          ),
        ),
      );
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final myName = await _matchService.getMyDisplayNameFallback(
        'Player',
      );

      await _realtimeInviteService.createInvite(
        toUid: widget.friendUid,
        toName: widget.friendName,
        fromName: myName,
        categoryId: 'random',
        difficulty: 1,
        totalQuestions: 10,
        timePerQuestionSec: 10,
        winReward: 2,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Realtime invite sent to ${widget.friendName}',
          ),
        ),
      );

      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final onlineText = widget.isOnline ? 'Online' : 'Offline';
    final onlineColor = widget.isOnline ? Colors.green : Colors.grey;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Challenge Friend'),
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.sports_esports, size: 42),
                    const SizedBox(height: 12),
                    Text(
                      widget.friendName,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: onlineColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          onlineText,
                          style: TextStyle(
                            color: onlineColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              if (_error != null) ...[
                Text(
                  _error!,
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
              ],

              FilledButton.icon(
                onPressed: _loading || !widget.isOnline
                    ? null
                    : _startRealtimeChallenge,
                icon: Icon(
                  widget.isOnline ? Icons.bolt : Icons.lock,
                ),
                label: Text(
                  widget.isOnline
                      ? 'Realtime Challenge'
                      : 'Realtime Challenge Locked',
                ),
              ),

              const SizedBox(height: 12),

              OutlinedButton.icon(
                onPressed: _loading ? null : _startAsyncChallenge,
                icon: const Icon(Icons.schedule),
                label: const Text('Async Challenge'),
              ),

              const SizedBox(height: 18),

              const Text(
                'Realtime requires both players to be online. Async can be played anytime.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54),
              ),
            ],
          ),

          if (_loading)
            Container(
              color: Colors.black.withOpacity(0.25),
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
        ],
      ),
    );
  }
}