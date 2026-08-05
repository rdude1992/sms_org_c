import '../models/category.dart';
import 'sms_platform_service.dart';

/// Persists muted-category preferences in NATIVE Android SharedPreferences
/// rather than via the shared_preferences Flutter plugin. This has to be
/// readable by plain Kotlin code running inside a BroadcastReceiver with no
/// Flutter engine alive (see NotificationPrefsRepository.kt /
/// IncomingSmsNotifier.kt on the native side), so both the Settings UI and
/// the background receiver read/write the exact same underlying storage
/// through the platform channel.
class NotificationPreferencesService {
  final SmsPlatformService _platform = SmsPlatformService.instance;

  Future<Set<SmsCategory>> loadMuted() async {
    final names = await _platform.getMutedCategories();
    return names
        .map((name) => SmsCategory.values.where((c) => c.name == name))
        .where((matches) => matches.isNotEmpty)
        .map((matches) => matches.first)
        .toSet();
  }

  Future<void> saveMuted(Set<SmsCategory> categories) async {
    await _platform.setMutedCategories(categories.map((c) => c.name).toSet());
  }
}
