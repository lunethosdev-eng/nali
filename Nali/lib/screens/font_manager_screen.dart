import 'package:flutter/material.dart';
import 'package:nali/services/font_manager_service.dart';
import 'package:nali/services/settings_service.dart';
import 'package:nali/widgets/liquid_glass.dart';

class FontManagerScreen extends StatefulWidget {
  const FontManagerScreen({super.key});
  @override
  State<FontManagerScreen> createState() => _FontManagerScreenState();
}

class _FontManagerScreenState extends State<FontManagerScreen> {
  bool _importing = false;

  String t(String es, String en) => SettingsService.instance.locale == 'en' ? en : es;

  Future<void> _import() async {
    setState(() => _importing = true);
    final error = await FontManagerService.instance.importFont();
    if (!mounted) return;
    setState(() => _importing = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(error ?? t('Fuente importada correctamente.', 'Font imported successfully.')),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final settings = SettingsService.instance;
    return AnimatedBuilder(
      animation: settings,
      builder: (context, _) => Scaffold(
        backgroundColor: settings.amoled ? Colors.black : const Color(0xFF0C0C0E),
        appBar: AppBar(
          title: Text(t('Fuentes', 'Fonts')),
          backgroundColor: Colors.transparent,
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Text(t('Elige la tipografía de Nali', 'Choose Nali typography'),
              style: const TextStyle(color: Colors.white70, fontSize: 14)),
            const SizedBox(height: 12),
            LiquidGlass(
              borderRadius: BorderRadius.circular(16),
              child: Column(children: FontManagerService.options.map((font) {
                final selected = settings.selectedFontId == font.id;
                return RadioListTile<String>(
                  value: font.id,
                  groupValue: settings.selectedFontId,
                  activeColor: const Color(0xfffc3c44),
                  title: Text(font.name, style: TextStyle(color: Colors.white, fontFamily: font.family, fontSize: 18)),
                  subtitle: Text(font.id, style: const TextStyle(color: Colors.white38, fontSize: 11)),
                  secondary: selected ? const Icon(Icons.check_circle, color: Color(0xfffc3c44)) : null,
                  onChanged: (_) async {
                    final loaded = await FontManagerService.instance.selectBuiltIn(font);
                    if (!mounted) return;
                    setState(() {});
                    if (!loaded) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(t('Agrega el archivo a assets/fonts para activarlo.', 'Add the font file to assets/fonts to activate it.')),
                      ));
                    }
                  },
                );
              }).toList()),
            ),
            const SizedBox(height: 18),
            LiquidGlass(
              borderRadius: BorderRadius.circular(16),
              child: ListTile(
                leading: const Icon(Icons.add_circle_outline, color: Colors.white70),
                title: Text(t('Importar fuente', 'Import font'), style: const TextStyle(color: Colors.white)),
                subtitle: Text(t('Añade archivos .TTF o .OTF desde tu dispositivo', 'Add .TTF or .OTF files from your device'), style: const TextStyle(color: Colors.white45, fontSize: 12)),
                trailing: _importing ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.chevron_right, color: Colors.white54),
                onTap: _importing ? null : _import,
              ),
            ),
            if (settings.customFontPath != null) ...[
              const SizedBox(height: 10),
              Text(t('Fuente personalizada activa', 'Custom font active'), style: const TextStyle(color: Colors.white54, fontSize: 12)),
              Text(settings.selectedFontId.replaceFirst('custom:', ''), style: const TextStyle(color: Colors.white70)),
            ],
            const SizedBox(height: 14),
            Text(t('La fuente predeterminada es Nothing Font 5x7. Los archivos incluidos en el ZIP se agregan manualmente en assets/fonts.', 'The default font is Nothing Font 5x7. Add the font files manually to assets/fonts.'), style: const TextStyle(color: Colors.white38, fontSize: 12, height: 1.4)),
          ],
        ),
      ),
    );
  }
}
