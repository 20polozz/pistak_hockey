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
  static const _categoriesKey = 'categories';

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

  /// User-defined categories (named match formats), e.g. "Aleví 2×15".
  Future<List<MatchFormat>> categories() async {
    final raw = await get(_categoriesKey);
    if (raw == null) return const [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => MatchFormat.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveCategory(MatchFormat f) async {
    final list = [...await categories()];
    final i = list.indexWhere((c) => c.id == f.id);
    if (i >= 0) {
      list[i] = f;
    } else {
      list.add(f);
    }
    await set(_categoriesKey, jsonEncode([for (final c in list) c.toJson()]));
  }

  Future<void> deleteCategory(String id) async {
    final list = (await categories()).where((c) => c.id != id).toList();
    await set(_categoriesKey, jsonEncode([for (final c in list) c.toJson()]));
  }
}
