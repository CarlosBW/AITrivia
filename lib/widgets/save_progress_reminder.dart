import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../services/account_link_service.dart';
import '../services/my_profile_service.dart';
import '../theme/app_theme.dart';
import 'save_progress_sheet.dart';

/// A dismissible nudge for guests to save their game, shown once they have
/// progress worth losing. Renders nothing otherwise — see
/// [shouldRemindToSaveProgress] for when.
class SaveProgressReminder extends StatefulWidget {
  const SaveProgressReminder({super.key});

  @override
  State<SaveProgressReminder> createState() => _SaveProgressReminderState();
}

class _SaveProgressReminderState extends State<SaveProgressReminder> {
  // Held rather than built in `build()`, and the shared stream at that:
  // this sits on Home, which rebuilds constantly.
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _me =
      MyProfileService.instance.watchMe();

  DateTime? _dismissedAt;
  bool _prefsLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadDismissal();
  }

  Future<void> _loadDismissal() async {
    final dismissedAt = await AccountLinkService.instance.reminderDismissedAt();
    if (!mounted) return;

    setState(() {
      _dismissedAt = dismissedAt;
      _prefsLoaded = true;
    });
  }

  Future<void> _dismiss() async {
    setState(() => _dismissedAt = DateTime.now());
    await AccountLinkService.instance.dismissReminder();
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final saved = await showSaveProgressSheet(context);
    if (!saved || !mounted) return;

    // Rebuild: the account is no longer a guest, so the card goes away.
    setState(() {});
    messenger.showSnackBar(SnackBar(content: Text(l10n.saveProgressSaved)));
  }

  @override
  Widget build(BuildContext context) {
    // Until the dismissal is known, showing the card could flash it at a
    // player who closed it a minute ago.
    if (!_prefsLoaded) return const SizedBox.shrink();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _me,
      builder: (context, snap) {
        final xp = ((snap.data?.data()?['xp'] ?? 0) as num).toInt();

        final remind = shouldRemindToSaveProgress(
          isGuest: AccountLinkService.instance.isGuest,
          xp: xp,
          dismissedAt: _dismissedAt,
          now: DateTime.now(),
        );
        if (!remind) return const SizedBox.shrink();

        final l10n = AppLocalizations.of(context);

        return Container(
          margin: const EdgeInsets.only(bottom: 18),
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
          decoration: BoxDecoration(
            color: context.appColors.rewardBg,
            borderRadius: BorderRadius.circular(context.radii.md),
            border: context.surfaces.borderOr(null),
            boxShadow: context.surfaces.shadowsOr(null),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.cloud_upload_outlined,
                    color: context.appColors.reward,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      l10n.saveProgressTitle,
                      style: context.heading(18),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(l10n.saveProgressReminderBody),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _dismiss,
                    child: Text(l10n.saveProgressNotNow),
                  ),
                  FilledButton(
                    onPressed: _save,
                    child: Text(l10n.saveProgressReminderAction),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
