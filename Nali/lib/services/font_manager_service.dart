import 'dart:typed_data';
import 'font_storage_stub.dart'
    if (dart.library.io) 'font_storage_io.dart' as font_storage;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nali/services/settings_service.dart';

class NaliFontOption {
  final String id;
  final String name;
  final String asset;
  final String family;
  const NaliFontOption(this.id, this.name, this.asset, this.family);
}

class FontManagerService {
  FontManagerService._();
  static final instance = FontManagerService._();
  final Set<String> _loadedFamilies = <String>{};

  static const options = <NaliFontOption>[
    NaliFontOption('nothing-font-5x7.otf', 'Nothing Font 5x7', 'assets/fonts/nothing-font-5x7.otf', 'NaliNothing5x7'),
    NaliFontOption('Clamofte-4nB54.otf', 'Clamofte', 'assets/fonts/Clamofte-4nB54.otf', 'NaliClamofte'),
    NaliFontOption('Rogbold-3llGM.otf', 'Rogbold', 'assets/fonts/Rogbold-3llGM.otf', 'NaliRogbold'),
    NaliFontOption('Alkia.ttf', 'Alkia', 'assets/fonts/Alkia.ttf', 'NaliAlkia'),
  ];

  Future<void> applySavedFont() async {
    final settings = SettingsService.instance;
    final custom = settings.customFontPath;
    if (custom != null && custom.isNotEmpty) {
      try {
        final bytes = await font_storage.readFont(custom);
        if (bytes != null) {
          final family = settings.fontFamily?.startsWith('NaliImported_') == true
              ? settings.fontFamily!
              : 'NaliImportedFont';
          await _loadBytes(family, bytes);
          settings.fontFamily = family;
          return;
        }
      } catch (_) {}
    }
    final option = options.firstWhere(
      (item) => item.id == settings.selectedFontId,
      orElse: () => options.first,
    );
    try {
      final data = await rootBundle.load(option.asset);
      await _loadAssetFont(option.family, data);
      settings.fontFamily = option.family;
    } catch (_) {
      // The user supplies the OTF/TTF files after receiving the project ZIP.
      settings.fontFamily = null;
    }
  }

  Future<bool> selectBuiltIn(NaliFontOption option) async {
    final settings = SettingsService.instance;
    settings.selectedFontId = option.id;
    settings.customFontPath = null;
    await applySavedFont();
    await settings.save();
    settings.notifyListeners();
    return settings.fontFamily == option.family;
  }

  Future<String?> importFont() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['ttf', 'otf'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final picked = result.files.single;
    final bytes = picked.bytes;
    if (bytes == null || bytes.isEmpty) return 'No se pudieron leer los datos de la fuente.';
    String? destination;
    try {
      final safeFamily = picked.name.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
      final family = 'NaliImported_${safeFamily.isEmpty ? 'Font' : safeFamily}';
      await _loadBytes(family, bytes);
      destination = await font_storage.persistFont(picked.name, Uint8List.fromList(bytes));
      final settings = SettingsService.instance;
      settings.fontFamily = family;
    } catch (error) {
      return 'El archivo no parece ser una fuente válida: $error';
    }
    final settings = SettingsService.instance;
    settings.customFontPath = destination;
    settings.selectedFontId = 'custom:${picked.name}';
    await settings.save();
    settings.notifyListeners();
    return null;
  }

  Future<void> _loadAssetFont(String family, ByteData data) async {
    if (_loadedFamilies.contains(family)) return;
    final loader = FontLoader(family)..addFont(Future.value(data));
    await loader.load();
    _loadedFamilies.add(family);
  }

  Future<void> _loadBytes(String family, List<int> bytes) async {
    if (_loadedFamilies.contains(family)) return;
    final data = ByteData.sublistView(Uint8List.fromList(bytes));
    final loader = FontLoader(family)..addFont(Future.value(data));
    await loader.load();
    _loadedFamilies.add(family);
  }
}
