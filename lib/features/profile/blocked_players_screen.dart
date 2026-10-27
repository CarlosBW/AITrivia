import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../l10n/user_facing_error.dart';
import '../../services/player_safety_service.dart';
import '../../widgets/app_bar_title.dart';
import '../../widgets/load_error_view.dart';

/// The players this one blocked, with a way to unblock each. Reached from
/// Profile.
class BlockedPlayersScreen extends StatefulWidget {
  const BlockedPlayersScreen({super.key});

  @override
  State<BlockedPlayersScreen> createState() => _BlockedPlayersScreenState();
}

class _BlockedPlayersScreenState extends State<BlockedPlayersScreen> {
  late Stream<QuerySnapshot<Map<String, dynamic>>> _blocked =
      PlayerSafetyService.instance.watchBlockedPlayers();
  String? _unblocking;

  Future<void> _unblock(String uid, String name) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _unblocking = uid);
    try {
      await PlayerSafetyService.instance.unblock(uid);
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.playerUnblocked(name))),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(userFacingError(l10n, e))),
      );
    } finally {
      if (mounted) setState(() => _unblocking = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: AppBarTitle(l10n.blockedPlayersTitle)),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _blocked,
        builder: (context, snap) {
          if (snap.hasError) {
            return LoadErrorView(
              message: userFacingError(l10n, snap.error!),
              onRetry: () => setState(() {
                _blocked = PlayerSafetyService.instance.watchBlockedPlayers();
              }),
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snap.data!.docs;
          if (docs.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  l10n.blockedPlayersEmpty,
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          return ListView(
            padding: EdgeInsets.fromLTRB(
              16, 16, 16, 16 + MediaQuery.paddingOf(context).bottom,
            ),
            children: [
              for (final doc in docs)
                Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    leading: const Icon(Icons.block),
                    title: Text(
                      (doc.data()['username'] ?? '').toString().isEmpty
                          ? l10n.commonPlayerFallback
                          : doc.data()['username'].toString(),
                    ),
                    trailing: _unblocking == doc.id
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : TextButton(
                            onPressed: _unblocking != null
                                ? null
                                : () => _unblock(
                                      doc.id,
                                      (doc.data()['username'] ??
                                              l10n.commonPlayerFallback)
                                          .toString(),
                                    ),
                            child: Text(l10n.playerActionsUnblock),
                          ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
