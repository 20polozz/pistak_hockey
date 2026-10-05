import 'dart:convert';

import 'package:drift/drift.dart';

import '../../core/ids.dart';
import '../../domain/sport/match_format.dart';
import '../db/app_database.dart';

/// Small key/value store for device-level settings, kept in the same SQLite
/// database as the matches (one storage engine, one durability guarantee).
class SettingsRepository {
  SettingsRepository(this.db, {this.ids = const UuidV7Generator()});

  final AppDatabase db;
  final IdGenerator ids;

  static const _deviceIdKey = 'device_id';
  static const _localeKey = 'locale';
  static const _onboardingKey = 'onboarding_done';
  static const _lastFormatKey = 'last_format';

  Future<String?> get(String key) async {
    final row = await (db.select(db.appSettings)
          ..where((s) => s.settingKey.equals(key)))
        .getSingleOrNull();
    return row?.settingValue;
  }

  Future<void> set(String key, String? value) async {
    if (value == null) {
      await (db.delete(db.appSettings)..where((s) => s.settingKey.equals(key)))
          .go();
    } else {
      await db.into(db.appSettings).insertOnConflictUpdate(AppSettingsCompanion(
            settingKey: Value(key),
            settingValue: Value(value),
          ));
    }
  }

  /// Stable id of this installation; generated once.
  Future<String> ensureDeviceId() async {
    final existing = await get(_deviceIdKey);
    if (existing != null) return existing;
    final id = ids.newId();
    await set(_deviceIdKey, id);
    return id;
  }

  /// null = follow the device language.
  Future<String?> localeCode() => get(_localeKey);
  Future<void> setLocaleCode(String? code) => set(_localeKey, code);

  Future<bool> isOnboardingDone() async => (await get(_onboardingKey)) == '1';
  Future<void> setOnboardingDone() => set(_onboardingKey, '1');

  /// Format used for the last match, proposed for the next NEW MATCH.
  Future<MatchFormat?> lastFormat() async {
    final raw = await get(_lastFormatKey);
    if (raw == null) return null;
    try {
      return MatchFormat.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> setLastFormat(MatchFormat f) =>
      set(_lastFormatKey, jsonEncode(f.toJson()));
}
