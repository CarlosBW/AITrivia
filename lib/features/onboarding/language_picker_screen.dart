import 'package:flutter/material.dart';

import '../../services/locale_controller.dart';
import '../../theme/app_theme.dart';

/// First-launch language picker — shown once, before anything else in the
/// app (including auth), since every screen's text depends on this choice.
/// Deliberately bilingual in its own copy rather than using
/// AppLocalizations: there's no chosen locale yet at this point.
class LanguagePickerScreen extends StatefulWidget {
  final VoidCallback onSelected;

  const LanguagePickerScreen({super.key, required this.onSelected});

  @override
  State<LanguagePickerScreen> createState() => _LanguagePickerScreenState();
}

class _LanguagePickerScreenState extends State<LanguagePickerScreen> {
  bool _saving = false;

  Future<void> _choose(String languageCode) async {
    if (_saving) return;
    setState(() => _saving = true);

    await LocaleController.instance.setLocale(languageCode);
    widget.onSelected();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('🧠', style: TextStyle(fontSize: 64)),
              const SizedBox(height: 16),
              Text(
                'TriviaIA',
                style: context.heading(32),
              ),
              const SizedBox(height: 40),
              const Text(
                'Elige tu idioma\nChoose your language',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saving ? null : () => _choose('es'),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 6),
                    child: Text('🇪🇸  Español', style: TextStyle(fontSize: 16)),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saving ? null : () => _choose('en'),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 6),
                    child: Text('🇬🇧  English', style: TextStyle(fontSize: 16)),
                  ),
                ),
              ),
              if (_saving) ...[
                const SizedBox(height: 24),
                const CircularProgressIndicator(),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
