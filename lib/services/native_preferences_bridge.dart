import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Shares Android Canvas switches with BitChord through the existing DataStore.
/// Other platforms keep their Flutter player and do not expose native switches.
class NativePreferencesBridge {
  NativePreferencesBridge._();
  static final instance = NativePreferencesBridge._();
  static const _channel = MethodChannel('nali/native_preferences');

  bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<Map<String, bool>> loadCanvasSettings() async {
    if (!supported) return const {};
    final raw = await _channel.invokeMapMethod<String, dynamic>('getCanvasSettings');
    return (raw ?? const {}).map((key, value) => MapEntry(key, value == true));
  }

  Future<void> setCanvasSetting(String key, bool enabled) async {
    if (!supported) return;
    await _channel.invokeMethod<bool>('setCanvasSetting', {
      'key': key,
      'enabled': enabled,
    });
  }
}
