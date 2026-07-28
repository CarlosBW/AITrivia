import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocaleController {
  LocaleController._();

  static final LocaleController instance = LocaleController._();

  static const _prefsKey = 'languageCode';
  static const supportedLanguageCodes = ['es', 'en'];

  final ValueNotifier<Locale> locale = ValueNotifier(const Locale('es'));

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_prefsKey);

    if (stored != null && supportedLanguageCodes.contains(stored)) {
      locale.value = Locale(stored);
      return;
    }

    final deviceCode = WidgetsBinding.instance.platformDispatcher.locale
        .languageCode;

    locale.value = Locale(
      supportedLanguageCodes.contains(deviceCode) ? deviceCode : 'es',
    );
  }

  Future<void> setLocale(String languageCode) async {
    if (!supportedLanguageCodes.contains(languageCode)) return;

    locale.value = Locale(languageCode);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, languageCode);

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set(
        {'languageCode': languageCode},
        SetOptions(merge: true),
      );
    } catch (_) {}
  }
}
