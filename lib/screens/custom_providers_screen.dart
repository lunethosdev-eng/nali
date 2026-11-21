import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:nali/services/custom_provider_service.dart';

class CustomProvidersScreen extends StatefulWidget {
  const CustomProvidersScreen({super.key});
  @override
  State<CustomProvidersScreen> createState() => _CustomProvidersScreenState();
}

class _CustomProvidersScreenState extends State<CustomProvidersScreen> {
  final service = CustomProviderService.instance;
  @override
  void initState() { super.initState(); service.load(); }

  Future<void> _edit([CustomProviderConfig? existing]) async {
    final name = TextEditingController(text: existing?.name ?? '');
    final endpoint = TextEditingController(text: existing?.endpoint ?? '');
    final headers = TextEditingController(text: existing == null ? '{}' : const JsonEncoder.withIndent('  ').convert(existing.headers));
    final results = TextEditingController(text: existing?.resultsPath ?? 'results');
    final title = TextEditingController(text: existing?.titlePath ?? 'title');
    final artist = TextEditingController(text: existing?.artistPath ?? 'artist');
    final audio = TextEditingController(text: existing?.audioPath ?? 'audio_url');
    final cover = TextEditingController(text: existing?.coverPath ?? 'cover_url');
    final lyrics = TextEditingController(text: existing?.lyricsPath ?? 'lyrics');
    final queryParam = TextEditingController(text: existing?.queryParam ?? 'q');
    final priority = TextEditingController(text: (existing?.priority ?? 100).toString());
    bool enabled = existing?.enabled ?? true;
    String kind = existing?.kind ?? 'music';
    String method = existing?.method ?? 'GET';
    final formKey = GlobalKey<FormState>();

    final save = await showDialog<bool>(context: context, builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialog) => AlertDialog(
        backgroundColor: const Color(0xff1b1b20),
        title: Text(existing == null ? 'Añadir proveedor' : 'Editar proveedor', style: const TextStyle(color: Colors.white)),
        content: SizedBox(width: 520, child: Form(key: formKey, child: SingleChildScrollView(child: Column(
          mainAxisSize: MainAxisSize.min, children: [
            _field(name, 'Nombre', required: true),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(value: kind, dropdownColor: const Color(0xff29292f),
              decoration: _decoration('Tipo'), items: const [
                DropdownMenuItem(value: 'music', child: Text('Catálogo de música')),
                DropdownMenuItem(value: 'lyrics', child: Text('Proveedor de letras')),
                DropdownMenuItem(value: 'connector', child: Text('Conector / servicio')),
              ], onChanged: (v) => setDialog(() => kind = v ?? 'music')),
            const SizedBox(height: 10),
            _field(endpoint, kind == 'connector' ? 'URL HTTPS' : 'Endpoint HTTPS', required: true,
              hint: kind == 'lyrics' ? 'https://api.example.com/lyrics?title={title}&artist={artist}' : 'https://api.example.com/search'),
            _field(priority, 'Prioridad (menor número = primero)'),
            const SizedBox(height: 10),
            SwitchListTile(contentPadding: EdgeInsets.zero, value: enabled, title: const Text('Proveedor activo', style: TextStyle(color: Colors.white)), onChanged: (v) => setDialog(() => enabled = v)),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(value: method, dropdownColor: const Color(0xff29292f),
              decoration: _decoration('Método HTTP'), items: const [
                DropdownMenuItem(value: 'GET', child: Text('GET')),
                DropdownMenuItem(value: 'POST', child: Text('POST')),
              ], onChanged: (v) => setDialog(() => method = v ?? 'GET')),
            if (kind != 'connector') ...[
              const SizedBox(height: 10),
              if (kind == 'music') _field(queryParam, 'Parámetro de búsqueda'),
              if (kind == 'music') ...[
                const SizedBox(height: 10), _field(results, 'Ruta de resultados', hint: 'results.items'),
                const SizedBox(height: 10), _field(title, 'Ruta del título'),
                const SizedBox(height: 10), _field(artist, 'Ruta del artista'),
                const SizedBox(height: 10), _field(audio, 'Ruta del audio HTTPS'),
                const SizedBox(height: 10), _field(cover, 'Ruta de portada'),
              ],
              if (kind == 'lyrics') ...[
                const SizedBox(height: 10), _field(lyrics, 'Ruta de letras'),
              ],
            ],
            const SizedBox(height: 10),
            _field(headers, 'Headers JSON (opcional)', maxLines: 3, hint: '{"Authorization":"Bearer ..."}'),
            const SizedBox(height: 10),
            const Text('Los endpoints deben usar HTTPS. Las claves se guardan en el almacenamiento seguro del dispositivo. Los proveedores son declarativos: Nali no ejecuta código externo.',
              style: TextStyle(color: Colors.white54, fontSize: 12, height: 1.4)),
          ],
        )))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () {
            if (!formKey.currentState!.validate()) return;
            Navigator.pop(dialogContext, true);
          }, child: const Text('Guardar')),
        ],
      ),
    ));

    if (save == true) {
      try {
        final decodedHeaders = jsonDecode(headers.text.isEmpty ? '{}' : headers.text);
        if (decodedHeaders is! Map) throw const FormatException('Headers debe ser un objeto JSON.');
        await service.saveProvider(CustomProviderConfig(
          id: existing?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
          name: name.text.trim(), kind: kind, endpoint: endpoint.text.trim(),
          enabled: enabled, priority: int.tryParse(priority.text.trim()) ?? 100,
          method: method, queryParam: queryParam.text.trim().isEmpty ? 'q' : queryParam.text.trim(),
          resultsPath: results.text.trim().isEmpty ? 'results' : results.text.trim(),
          titlePath: title.text.trim().isEmpty ? 'title' : title.text.trim(),
          artistPath: artist.text.trim().isEmpty ? 'artist' : artist.text.trim(),
          audioPath: audio.text.trim().isEmpty ? 'audio_url' : audio.text.trim(),
          coverPath: cover.text.trim().isEmpty ? 'cover_url' : cover.text.trim(),
          lyricsPath: lyrics.text.trim().isEmpty ? 'lyrics' : lyrics.text.trim(),
          headers: Map<String, String>.from(decodedHeaders),
        ));
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se guardó: $e')));
      }
    }
  }

  Future<void> _runConnector(CustomProviderConfig provider) async {
    try {
      final result = await service.runConnector(provider.id);
      if (!mounted) return;
      showDialog(context: context, builder: (_) => AlertDialog(backgroundColor: const Color(0xff1b1b20), title: Text(provider.name, style: const TextStyle(color: Colors.white)), content: SizedBox(width: 520, child: SingleChildScrollView(child: SelectableText(result, style: const TextStyle(color: Colors.white70, fontFamily: 'monospace')))), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar'))]));
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Conector: $e'))); }
  }

  InputDecoration _decoration(String label) => InputDecoration(labelText: label, labelStyle: const TextStyle(color: Colors.white70),
    filled: true, fillColor: Colors.white.withOpacity(.05), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)));

  Widget _field(TextEditingController c, String label, {bool required = false, String? hint, int maxLines = 1}) => TextFormField(
    controller: c, maxLines: maxLines, style: const TextStyle(color: Colors.white),
    decoration: _decoration(label).copyWith(hintText: hint, hintStyle: const TextStyle(color: Colors.white30)),
    validator: required ? (v) => v == null || v.trim().isEmpty ? 'Campo obligatorio' : null : null,
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xff0c0c0e),
    appBar: AppBar(backgroundColor: const Color(0xff0c0c0e), foregroundColor: Colors.white,
      title: const Text('Proveedores personalizados')),
    floatingActionButton: FloatingActionButton.extended(onPressed: _edit,
      backgroundColor: const Color(0xfffc3c44), foregroundColor: Colors.white,
      icon: const Icon(Icons.add_rounded), label: const Text('Añadir')),
    body: AnimatedBuilder(animation: service, builder: (context, _) {
      final providers = service.providers;
      if (providers.isEmpty) return const Center(child: Padding(padding: EdgeInsets.all(28),
        child: Text('Todavía no agregaste proveedores. Puedes conectar catálogos de música, servicios de letras y otros conectores compatibles con HTTPS.',
          textAlign: TextAlign.center, style: TextStyle(color: Colors.white54, height: 1.5))));
      return ListView.separated(padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        itemCount: providers.length, separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final p = providers[i];
          final type = switch (p.kind) {'music' => 'Catálogo de música', 'lyrics' => 'Letras', _ => 'Conector'};
          return Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(
            color: const Color(0xff1a1a1f), borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(.07))),
            child: Row(children: [
              Container(width: 42, height: 42, decoration: BoxDecoration(color: Colors.white.withOpacity(.07), borderRadius: BorderRadius.circular(12)),
                child: Icon(p.kind == 'music' ? Icons.library_music_rounded : p.kind == 'lyrics' ? Icons.lyrics_rounded : Icons.extension_rounded, color: Colors.white70)),
              const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                Text('$type · ${p.enabled ? 'Activo' : 'Desactivado'} · prioridad ${p.priority}', style: const TextStyle(color: Colors.white54, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(Uri.tryParse(p.endpoint)?.host ?? p.endpoint, style: const TextStyle(color: Colors.white38, fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis),
              ])),
              Switch(value: p.enabled, onChanged: (v) => service.setEnabled(p.id, v)),
              if (p.kind == 'connector') ...[
                IconButton(onPressed: () => _runConnector(p), tooltip: 'Ejecutar conector', icon: const Icon(Icons.play_arrow_rounded, color: Colors.white70)),
                IconButton(onPressed: () => launchUrl(Uri.parse(p.endpoint), mode: LaunchMode.externalApplication), tooltip: 'Abrir enlace', icon: const Icon(Icons.open_in_new, color: Colors.white70)),
              ],
              IconButton(onPressed: () => _edit(p), icon: const Icon(Icons.edit_outlined, color: Colors.white70)),
              IconButton(onPressed: () => service.remove(p.id), icon: const Icon(Icons.delete_outline, color: Colors.redAccent)),
            ]),
          );
        });
    }),
  );
}
