import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Canvas preferences use BitChord's Android DataStore through the native channel
/// and a SharedPreferences cache on Flutter platforms without that native bridge.
class NativePreferencesBridge {
  NativePreferencesBridge._();
  static final instance = NativePreferencesBridge._();
  static const _channel = MethodChannel('nali/native_preferences');

  bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static const _defaults = <String, bool>{
    'appleMusic': false,
    'spotify': false,
    'external': true,
    'repeat': true,
    'animatedCovers': true,
  };

  String _storageKey(String key) => 'nali_canvas_$key';


  Future<Map<String, bool>> loadCanvasSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (supported) {
      try {
        final raw = await _channel.invokeMapMethod<String, dynamic>('getCanvasSettings');
        final native = (raw ?? const {}).map((key, value) => MapEntry(key, value == true));
        for (final key in _defaults.keys) {
          if (native.containsKey(key)) await prefs.setBool(_storageKey(key), native[key]!);
        }
        return {..._defaults, ...native};
      } catch (_) {
        // If the native bridge is unavailable, use the local preference cache.
      }
    }
    return _defaults.map((key, value) => MapEntry(key, prefs.getBool(_storageKey(key)) ?? value));
  }


  Future<void> setCanvasSetting(String key, bool enabled) async {
    if (!_defaults.containsKey(key)) throw ArgumentError.value(key, 'key', 'Unknown Canvas setting');
    if (supported) {
      await _channel.invokeMethod<bool>('setCanvasSetting', {
        'key': key,
        'enabled': enabled,
      });
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_storageKey(key), enabled);
  }
}
