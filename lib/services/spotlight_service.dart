import 'package:shared_preferences/shared_preferences.dart';

/// Tracks which first-visit spotlight hints (see widgets/spotlight_hint.dart)
/// this device has already dismissed, so each one only shows once — purely
/// a local UI preference, not synced across devices, mirroring
/// locale_controller.dart's use of SharedPreferences for the same reason.
class SpotlightService {
  SpotlightService._();

  static final SpotlightService instance = SpotlightService._();

  static const _prefsKey = 'seenSpotlights';

  Future<bool> hasSeen(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getStringList(_prefsKey) ?? [];
    return seen.contains(id);
  }

  Future<void> markSeen(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getStringList(_prefsKey) ?? [];
    if (seen.contains(id)) return;

    seen.add(id);
    await prefs.setStringList(_prefsKey, seen);
  }
}
