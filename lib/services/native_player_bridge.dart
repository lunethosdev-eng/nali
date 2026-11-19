import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android bridge to the native Media3/BitChord playback stack.
/// Web and iOS keep their existing Flutter audio implementation.
class NativePlayerBridge {
  NativePlayerBridge._();
  static final NativePlayerBridge instance = NativePlayerBridge._();
  static const MethodChannel _methods = MethodChannel('nali/player');
  static const EventChannel _events = EventChannel('nali/player/events');

  bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  Stream<Map<String, dynamic>> get states => _events.receiveBroadcastStream().map(
        (event) => Map<String, dynamic>.from(event as Map),
      );

  Future<T?> invoke<T>(String method, [Map<String, dynamic>? args]) async {
    if (!supported) return null;
    return _methods.invokeMethod<T>(method, args);
  }

  static Map<String, dynamic> safeSong(Map<String, dynamic> song) {
    dynamic clean(dynamic value) {
      if (value == null || value is String || value is num || value is bool) return value;
      if (value is List) return value.map(clean).toList();
      if (value is Map) return value.map((k, v) => MapEntry(k.toString(), clean(v)));
      return value.toString();
    }
    return song.map((key, value) => MapEntry(key, clean(value)));
  }
}
