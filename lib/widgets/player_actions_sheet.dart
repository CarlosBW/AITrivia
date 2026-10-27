import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../l10n/user_facing_error.dart';
import '../services/player_safety_service.dart';
import '../theme/app_theme.dart';

/// Report or block another player: the sheet behind every place one
/// player sees another (friends, search, rankings, a finished match).
/// Does nothing for the player's own row.
Future<void> showPlayerActions(
  BuildContext context, {
  required String uid,
  required String name,
  String? matchId,
}) async {
  if (uid.isEmpty || uid == FirebaseAuth.instance.currentUser?.uid) return;

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => _PlayerActionsSheet(
      uid: uid,
      name: name,
      matchId: matchId,
      // The sheet closes before its dialogs open, so they need a context
      // that outlives it.
      hostContext: context,
    ),
  );
}

class _PlayerActionsSheet extends StatelessWidget {
  final String uid;
  final String name;
  final String? matchId;
  final BuildContext hostContext;

  const _PlayerActionsSheet({
    required this.uid,
    required this.name,
    required this.matchId,
    required this.hostContext,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final danger = context.appColors.danger;

    return SafeArea(
      child: StreamBuilder<Set<String>>(
        stream: PlayerSafetyService.instance.watchBlocked(),
        builder: (context, snap) {
          final blocked = snap.data?.contains(uid) ?? false;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Text(
                  name,
                  style: context.heading(18),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              ListTile(
                leading: const Icon(Icons.flag_outlined),
                title: Text(l10n.playerActionsReport),
                onTap: () {
                  Navigator.pop(context);
                  _report(hostContext, uid: uid, name: name, matchId: matchId);
                },
              ),
              ListTile(
                leading: Icon(
                  blocked ? Icons.lock_open_outlined : Icons.block,
                  color: blocked ? null : danger,
                ),
                title: Text(
                  blocked ? l10n.playerActionsUnblock : l10n.playerActionsBlock,
                  style: blocked ? null : TextStyle(color: danger),
                ),
                onTap: () {
                  Navigator.pop(context);
                  if (blocked) {
                    _unblock(hostContext, uid: uid, name: name);
                  } else {
                    _block(hostContext, uid: uid, name: name);
                  }
                },
              ),
              const SizedBox(height: 8),
            ],
          );
        },
      ),
    );
  }
}

Future<void> _report(
  BuildContext context, {
  required String uid,
  required String name,
  String? matchId,
}) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);

  final sent = await showDialog<bool>(
    context: context,
    builder: (_) => _ReportDialog(uid: uid, name: name, matchId: matchId),
  );
  if (sent == true) {
    messenger.showSnackBar(SnackBar(content: Text(l10n.reportSent)));
  }
}

Future<void> _block(
  BuildContext context, {
  required String uid,
  required String name,
}) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.blockPlayerTitle(name)),
      content: Text(l10n.blockPlayerBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(l10n.commonCancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(
            l10n.blockPlayerConfirm,
            style: TextStyle(color: dialogContext.appColors.danger),
          ),
        ),
      ],
    ),
  );
  if (confirmed != true) return;

  try {
    await PlayerSafetyService.instance.block(uid);
    messenger.showSnackBar(SnackBar(content: Text(l10n.playerBlocked(name))));
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text(userFacingError(l10n, e))),
    );
  }
}

Future<void> _unblock(
  BuildContext context, {
  required String uid,
  required String name,
}) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  try {
    await PlayerSafetyService.instance.unblock(uid);
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.playerUnblocked(name))),
    );
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text(userFacingError(l10n, e))),
    );
  }
}

class _ReportDialog extends StatefulWidget {
  final String uid;
  final String name;
  final String? matchId;

  const _ReportDialog({
    required this.uid,
    required this.name,
    required this.matchId,
  });

  @override
  State<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<_ReportDialog> {
  final _details = TextEditingController();
  PlayerReportReason? _reason;
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  String _label(AppLocalizations l10n, PlayerReportReason reason) {
    return switch (reason) {
      PlayerReportReason.offensiveName => l10n.reportReasonOffensiveName,
      PlayerReportReason.cheating => l10n.reportReasonCheating,
      PlayerReportReason.spamOrHarassment => l10n.reportReasonSpam,
      PlayerReportReason.other => l10n.reportReasonOther,
    };
  }

  Future<void> _send() async {
    final reason = _reason;
    if (reason == null || _sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await PlayerSafetyService.instance.report(
        targetUid: widget.uid,
        reason: reason,
        details: _details.text,
        matchId: widget.matchId,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = userFacingError(AppLocalizations.of(context), e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return AlertDialog(
      title: Text(l10n.reportPlayerTitle(widget.name)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.reportPlayerSubtitle),
            const SizedBox(height: 8),
            RadioGroup<PlayerReportReason>(
              groupValue: _reason,
              onChanged: (value) {
                if (!_sending) setState(() => _reason = value);
              },
              child: Column(
                children: [
                  for (final reason in PlayerReportReason.values)
                    RadioListTile<PlayerReportReason>(
                      value: reason,
                      title: Text(_label(l10n, reason)),
                      contentPadding: EdgeInsets.zero,
                    ),
                ],
              ),
            ),
            TextField(
              controller: _details,
              enabled: !_sending,
              maxLength: 500,
              maxLines: 3,
              minLines: 1,
              decoration: InputDecoration(hintText: l10n.reportDetailsHint),
            ),
            if (_error != null)
              Text(_error!, style: TextStyle(color: context.appColors.danger)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.pop(context, false),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          onPressed: _reason == null || _sending ? null : _send,
          child: _sending
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.reportSend),
        ),
      ],
    );
  }
}
