import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:minimal_launcher/core/platform/system_apps_platform.dart';
import 'package:minimal_launcher/features/system_apps/app_risk.dart';

SystemApp _app(String pkg, {String? role}) =>
    SystemApp(packageName: pkg, label: pkg, icon: Uint8List(0), enabled: true, defaultRole: role);

void main() {
  test('a current default-role holder is protected, even if otherwise safe', () {
    final risk = assessRisk(_app('com.vivo.browser', role: 'default browser'));
    expect(risk.level, RiskLevel.protected);
    expect(risk.reason, contains('default browser'));
  });

  test('core system apps are protected', () {
    expect(assessRisk(_app('com.android.settings')).level, RiskLevel.protected);
    expect(assessRisk(_app('com.android.bbk.lockscreen3')).level, RiskLevel.protected);
  });

  test('apps others depend on need confirmation', () {
    expect(assessRisk(_app('com.android.deskclock')).level, RiskLevel.caution);
  });

  test('known extras are safe', () {
    expect(assessRisk(_app('com.vivo.game')).level, RiskLevel.safe);
  });

  test('unknown apps default to caution, never safe', () {
    expect(assessRisk(_app('com.example.unknown')).level, RiskLevel.caution);
  });
}
