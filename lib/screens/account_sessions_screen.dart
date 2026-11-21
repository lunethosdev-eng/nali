import 'package:flutter/material.dart';
import 'package:nali/services/account_sessions_service.dart';
import 'package:nali/services/supabase_service.dart';

class AccountSessionsScreen extends StatefulWidget {
  const AccountSessionsScreen({super.key});
  @override
  State<AccountSessionsScreen> createState() => _AccountSessionsScreenState();
}
class _AccountSessionsScreenState extends State<AccountSessionsScreen> {
  List<Map<String, String>> _accounts = [];
  bool _loading = true;
  @override
  void initState() { super.initState(); _refresh(); }
  Future<void> _refresh() async {
    await AccountSessionsService.instance.saveCurrent();
    final data = await AccountSessionsService.instance.list();
    if (mounted) setState(() { _accounts = data; _loading = false; });
  }
  Future<void> _addAccount() async {
    final email = TextEditingController(), password = TextEditingController(), pin = TextEditingController();
    final values = await showDialog<List<String>>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Agregar cuenta Nali'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Correo')),
        TextField(controller: password, obscureText: true, decoration: const InputDecoration(labelText: 'Contraseña')),
        TextField(controller: pin, obscureText: true, decoration: const InputDecoration(labelText: 'PIN (si aplica)')),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')), FilledButton(onPressed: () => Navigator.pop(ctx, [email.text.trim(), password.text, pin.text]), child: const Text('Iniciar sesión'))],
    ));
    if (values == null) { email.dispose(); password.dispose(); pin.dispose(); return; }
    try {
      await SupabaseService.signIn(email: values[0], password: values[1], pin: values[2].isEmpty ? null : values[2]);
      await AccountSessionsService.instance.saveCurrent();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sesión agregada y guardada en almacenamiento seguro.')));
      await _refresh();
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo agregar: $e'))); }
    email.dispose(); password.dispose(); pin.dispose();
  }
  Widget _accountTile(Map<String, String> account) {
    final userId = account['userId'] ?? '';
    final isCurrent = userId == SupabaseService.currentUser?.id;
    return Card(
      child: ListTile(
        leading: const Icon(Icons.account_circle),
        title: Text(account['email'] ?? 'Cuenta'),
        subtitle: Text(isCurrent ? 'Cuenta actual' : 'Sesión guardada'),
        trailing: isCurrent
            ? const Icon(Icons.check_circle)
            : IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Quitar cuenta guardada',
                onPressed: () async {
                  await AccountSessionsService.instance.remove(userId);
                  await _refresh();
                },
              ),
        onTap: isCurrent
            ? null
            : () async {
                try {
                  await AccountSessionsService.instance.switchTo(
                    account['refreshToken'] ?? '',
                  );
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Cuenta cambiada.')),
                  );
                  await _refresh();
                } catch (error) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error al cambiar cuenta: $error')),
                  );
                }
              },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Administrar cuentas')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'Las sesiones guardadas se almacenan en el almacén seguro del dispositivo. Al cambiar de cuenta, Nali restaura la sesión mediante su token de renovación.',
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 12),
                ..._accounts.map(_accountTile),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _addAccount,
                  icon: const Icon(Icons.person_add_alt_1),
                  label: const Text('Agregar cuenta'),
                ),
              ],
            ),
    );
  }
}
