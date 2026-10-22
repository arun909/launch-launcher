import '../../core/platform/system_apps_platform.dart';

/// How safe it is to disable a system app.
enum RiskLevel {
  /// Known extra; disabling only loses that app.
  safe,

  /// Other features may depend on it, or it's unknown. Warn before disabling.
  caution,

  /// Disabling would break the phone. The switch is locked.
  protected,
}

class AppRisk {
  const AppRisk(this.level, [this.reason]);

  final RiskLevel level;

  /// Why it isn't [RiskLevel.safe]; shown to the user.
  final String? reason;
}

/// Assesses [app]. Current default-role holders are always protected; the
/// rest comes from the catalogue below (built from an iQOO / Android 16 phone,
/// extend it as you meet new apps). Native code enforces its own blocklist
/// too, so this list is for guidance, not the only safety net.
AppRisk assessRisk(SystemApp app) {
  final role = app.defaultRole;
  if (role != null) return AppRisk(RiskLevel.protected, 'Your $role. Switch the default first.');
  final protectedReason = _protected[app.packageName];
  if (protectedReason != null) return AppRisk(RiskLevel.protected, protectedReason);
  final cautionReason = _caution[app.packageName];
  if (cautionReason != null) return AppRisk(RiskLevel.caution, cautionReason);
  if (_safe.contains(app.packageName)) return const AppRisk(RiskLevel.safe);
  return const AppRisk(RiskLevel.caution, 'Not in the known list. Check what it does before disabling.');
}

const _protected = {
  'com.android.settings': 'Android Settings',
  'com.android.vending': 'Play Store: installs and updates every app',
  'com.android.bbk.lockscreen3': 'iQOO lock screen',
  'com.vivo.imanager': 'iQOO i Manager: permissions and security',
  'com.bbk.theme': 'iQOO themes: wallpaper, fonts and icons',
  'com.vivo.simplelauncher': 'iQOO simple-mode home screen',
  'com.android.systemui': 'Status bar and navigation',
  'com.android.phone': 'Calls and mobile network',
  'com.google.android.gms': 'Google Play services',
};

const _caution = {
  'com.android.deskclock': 'Alarms stop working while it is disabled',
  'com.android.camera': 'Other apps open it to take photos',
  'com.android.filemanager': 'Some apps use it to pick files',
  'com.vivo.gallery': "The camera's thumbnail opens it",
  'com.android.contacts': "Also contains iQOO's dialer",
  'com.vivo.soundrecorder': 'iQOO call recording may depend on it',
  'com.bbk.cloud': 'iQOO backups stop',
  'com.google.android.googlequicksearchbox': 'Google search, Assistant and the search widget',
  'com.vivo.weather': 'The weather widget stops updating',
};

const _safe = {
  'com.vivo.browser',
  'com.iqoo.website',
  'com.vivo.game',
  'com.vivo.Tips',
  'com.vivo.feedback',
  'com.vivo.easyshare',
  'com.vivo.exhealth',
  'com.vivo.compass',
  'com.vivo.notes',
  'com.vivo.vhome',
  'com.android.VideoPlayer',
  'com.vivo.calculator',
  'com.android.bbkmusic',
  'com.google.android.youtube',
  'com.google.android.apps.maps',
  'com.google.android.apps.photos',
  'com.google.android.gm',
  'com.google.android.calendar',
  'com.google.android.apps.wellbeing',
  'com.google.android.apps.nbu.files',
  'com.google.android.apps.nbu.paisa.user',
  'com.google.android.contacts',
};
