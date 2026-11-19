import 'dart:typed_data';

final Map<String, Uint8List> _memoryFonts = <String, Uint8List>{};

Future<String?> persistFont(String name, Uint8List bytes) async {
  final key = 'memory:$name';
  _memoryFonts[key] = Uint8List.fromList(bytes);
  return key;
}

Future<Uint8List?> readFont(String key) async => _memoryFonts[key];
