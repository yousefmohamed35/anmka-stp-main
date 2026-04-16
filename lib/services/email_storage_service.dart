import 'package:shared_preferences/shared_preferences.dart';

class EmailStorageService {
  static const String _savedEmailsKey = 'saved_login_emails';

  Future<List<String>> getSavedEmails() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final emails = prefs.getStringList(_savedEmailsKey) ?? <String>[];
      return emails.where((email) => email.trim().isNotEmpty).toList();
    } catch (_) {
      return <String>[];
    }
  }

  Future<void> saveEmail(String email) async {
    final normalizedEmail = email.trim();
    if (normalizedEmail.isEmpty) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final existing = prefs.getStringList(_savedEmailsKey) ?? <String>[];
      final alreadySaved = existing.any(
        (savedEmail) =>
            savedEmail.toLowerCase() == normalizedEmail.toLowerCase(),
      );
      if (alreadySaved) return;

      final updated = <String>[normalizedEmail, ...existing];
      await prefs.setStringList(_savedEmailsKey, updated);
    } catch (_) {
      // Keep login flow safe even if local storage fails.
    }
  }
}
