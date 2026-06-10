import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../services/realtime_invite_service.dart';
import 'match_lobby_screen.dart';

class RealtimeInvitesScreen extends StatefulWidget {
  const RealtimeInvitesScreen({super.key});

  @override
  State<RealtimeInvitesScreen> createState() => _RealtimeInvitesScreenState();
}

class _RealtimeInvitesScreenState extends State<RealtimeInvitesScreen> {
  final _service = RealtimeInviteService.instance;

  bool _loadingAction = false;

  Future<void> _declineInvite(String inviteId) async {
    if (_loadingAction) return;

    setState(() => _loadingAction = true);

    try {
      await _service.declineInvite(inviteId: inviteId);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invite declined')),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.toString().replaceFirst('Exception: ', ''),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _loadingAction = false);
      }
    }
  }

  Future<void> _acceptInvite(String inviteId) async {
    if (_loadingAction) return;

    setState(() => _loadingAction = true);

    try {
      final matchId = await _service.acceptInvite(
        inviteId: inviteId,
      );

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => MatchLobbyScreen(
            matchId: matchId,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.toString().replaceFirst('Exception: ', ''),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _loadingAction = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Realtime Invites'),
      ),
      body: Stack(
        children: [
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _service.watchMyIncomingInvites(),
            builder: (context, snap) {
              if (snap.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Error loading invites:\n${snap.error}',
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }

              if (!snap.hasData) {
                return const Center(
                  child: CircularProgressIndicator(),
                );
              }

              final docs = snap.data!.docs;

              if (docs.isEmpty) {
                return const _EmptyInvites();
              }

              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: docs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final doc = docs[index];
                  final data = doc.data();

                  final fromName = (data['fromName'] ?? 'Player').toString();

                  final categoryId =
                      (data['categoryId'] ?? 'random').toString();

                  return Card(
                    elevation: 0,
                    color: Colors.deepPurple.withOpacity(0.12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                      side: BorderSide(
                        color: Colors.deepPurple.withOpacity(0.45),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                backgroundColor:
                                    Colors.deepPurple.withOpacity(0.18),
                                child: const Icon(Icons.bolt),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  '$fromName invited you',
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Realtime 1 vs 1 • Category: $categoryId',
                            style: const TextStyle(
                              color: Colors.black54,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _loadingAction
                                      ? null
                                      : () => _declineInvite(
                                            doc.id,
                                          ),
                                  icon: const Icon(
                                    Icons.close,
                                  ),
                                  label: const Text('Decline'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: _loadingAction
                                      ? null
                                      : () => _acceptInvite(
                                            doc.id,
                                          ),
                                  icon: const Icon(
                                    Icons.check,
                                  ),
                                  label: const Text('Accept'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
          if (_loadingAction)
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

class _EmptyInvites extends StatelessWidget {
  const _EmptyInvites();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bolt_outlined, size: 48),
            SizedBox(height: 12),
            Text(
              'No realtime invites right now.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
