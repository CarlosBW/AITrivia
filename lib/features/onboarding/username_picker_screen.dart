import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';
import '../auth/user_bootstrap.dart';
import '../../theme/app_theme.dart';
import '../../widgets/save_progress_sheet.dart';

/// 3-20 chars, letters/numbers/underscore only. Returns null if [username]
/// is valid, else a symbolic reason ('length' or 'chars') for the caller
/// to localize.
String? usernameFormatError(String username) {
  if (username.length < 3 || username.length > 20) return 'length';
  if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(username)) return 'chars';
  return null;
}

/// First-launch username picker — shown once for brand-new accounts, right
/// after the language picker. The chosen name becomes the account's
/// permanent, unique username (used to add friends) and can't be edited
/// afterward.
class UsernamePickerScreen extends StatefulWidget {
  final Future<void> Function(String username) onSubmit;

  const UsernamePickerScreen({super.key, required this.onSubmit});

  @override
  State<UsernamePickerScreen> createState() => _UsernamePickerScreenState();
}

class _UsernamePickerScreenState extends State<UsernamePickerScreen> {
  final _controller = TextEditingController();
  bool _saving = false;
  String? _errorText;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return;

    final l10n = AppLocalizations.of(context);
    final username = _controller.text.trim();

    final formatError = usernameFormatError(username);
    if (formatError != null) {
      setState(() {
        _errorText = formatError == 'length'
            ? l10n.profileUsernameLengthError
            : l10n.profileUsernameCharsError;
      });
      return;
    }

    setState(() {
      _saving = true;
      _errorText = null;
    });

    try {
      final usernameLower = username.toLowerCase();

      final existing = await FirebaseFirestore.instance
          .collection('users')
          .where('usernameLower', isEqualTo: usernameLower)
          .limit(1)
          .get();

      if (existing.docs.isNotEmpty) {
        throw UsernameTakenException();
      }

      await widget.onSubmit(username);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _errorText = e is UsernameTakenException
            ? l10n.profileUsernameTaken
            : l10n.authGateConnectionError;
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// For a player reinstalling or on a new phone, who has a game saved
  /// under a sign-in and should not have to start a new one to reach it.
  Future<void> _recoverAccount() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);

    // Comes back only when that sign-in had no saved game. With one, the
    // app restarts straight into it and this screen is gone.
    final linked = await showSaveProgressSheet(context, recovering: true);
    if (!linked || !mounted) return;

    messenger.showSnackBar(
      SnackBar(content: Text(l10n.saveProgressNoSavedGame)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      body: SafeArea(
        // Scrolls instead of overflowing: with the keyboard up there is
        // little room left, and the field is focused from the start.
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              children: [
                const Text('🧠', style: TextStyle(fontSize: 64)),
                const SizedBox(height: 16),
                Text(
                  l10n.usernamePickerTitle,
                  textAlign: TextAlign.center,
                  style: context.heading(26),
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.usernamePickerSubtitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 15),
                ),
                const SizedBox(height: 28),
                TextField(
                  controller: _controller,
                  autofocus: true,
                  maxLength: 20,
                  textAlign: TextAlign.center,
                  enabled: !_saving,
                  decoration: InputDecoration(
                    hintText: l10n.usernamePickerHint,
                    helperText: l10n.profileUsernameHelper,
                    errorText: _errorText,
                    border: const OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _saving ? null : _submit,
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(l10n.usernamePickerContinue),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _saving ? null : _recoverAccount,
                  child: Text(l10n.usernamePickerHaveAccount),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
