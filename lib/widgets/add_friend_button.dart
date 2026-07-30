import 'package:flutter/material.dart';

import '../services/friend_service.dart';
import '../l10n/generated/app_localizations.dart';

/// Small "add friend" affordance for player rows outside the Friends tab
/// (leaderboards) — the only other place a player can discover someone by
/// seeing their name, since search there requires already knowing a
/// username. Relies on [FriendService.sendFriendRequest]'s own
/// self/already-friends/already-sent checks rather than pre-fetching
/// relationship state for every row.
class AddFriendButton extends StatefulWidget {
  final String targetUid;

  const AddFriendButton({super.key, required this.targetUid});

  @override
  State<AddFriendButton> createState() => _AddFriendButtonState();
}

class _AddFriendButtonState extends State<AddFriendButton> {
  bool _sending = false;
  bool _sent = false;

  Future<void> _send() async {
    if (_sending || _sent) return;

    setState(() => _sending = true);

    try {
      await FriendService.instance.sendFriendRequest(
        targetUid: widget.targetUid,
      );

      if (!mounted) return;

      setState(() => _sent = true);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).friendsRequestSent)),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_sending) {
      return const SizedBox(
        width: 36,
        height: 36,
        child: Padding(
          padding: EdgeInsets.all(8),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    return IconButton(
      visualDensity: VisualDensity.compact,
      icon: Icon(_sent ? Icons.check_circle_outline : Icons.person_add_alt_1),
      tooltip: AppLocalizations.of(context).friendsAddButton,
      onPressed: _sent ? null : _send,
    );
  }
}
