import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nali/services/supabase_service.dart';

class PasswordRecoveryScreen extends StatefulWidget {
  const PasswordRecoveryScreen({super.key});
  @override
  State<PasswordRecoveryScreen> createState() => _PasswordRecoveryScreenState();
}
class _PasswordRecoveryScreenState extends State<PasswordRecoveryScreen> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _saving = false;
  @override
  void dispose() { _password.dispose(); _confirm.dispose(); super.dispose(); }
  Future<void> _submit() async {
    if (_password.text.length < 8) { _show('La contraseña debe tener al menos 8 caracteres.'); return; }
    if (_password.text != _confirm.text) { _show('Las contraseñas no coinciden.'); return; }
    setState(() => _saving = true);
    try {
      await SupabaseService.kokoro.auth.updateUser(UserAttributes(password: _password.text));
      if (mounted) { _show('Contraseña actualizada.'); Navigator.of(context).pop(); }
    } catch (e) { if (mounted) _show('No se pudo actualizar: $e'); }
    if (mounted) setState(() => _saving = false);
  }
  void _show(String message) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message))); }
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Nueva contraseña')), body: ListView(padding: const EdgeInsets.all(24), children: [
    const Text('Escribe y confirma tu nueva contraseña.'),
    const SizedBox(height: 16), TextField(controller: _password, obscureText: true, decoration: const InputDecoration(labelText: 'Nueva contraseña', border: OutlineInputBorder())),
    const SizedBox(height: 12), TextField(controller: _confirm, obscureText: true, decoration: const InputDecoration(labelText: 'Confirmar contraseña', border: OutlineInputBorder())),
    const SizedBox(height: 20), FilledButton(onPressed: _saving ? null : _submit, child: Text(_saving ? 'Guardando…' : 'Actualizar contraseña')),
  ]));
}
