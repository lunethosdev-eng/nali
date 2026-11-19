import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';

Future<String?> persistFont(String name, Uint8List bytes) async {
  final directory = await getApplicationSupportDirectory();
  final fontsDir = Directory('${directory.path}/fonts');
  await fontsDir.create(recursive: true);
  final safeName = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  final destination = File('${fontsDir.path}/${DateTime.now().millisecondsSinceEpoch}_$safeName');
  await destination.writeAsBytes(bytes, flush: true);
  return destination.path;
}

Future<Uint8List?> readFont(String path) async {
  final file = File(path);
  if (!await file.exists()) return null;
  return file.readAsBytes();
}
