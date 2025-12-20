import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import 'add_transaction.dart';
import 'config.dart';
import 'dashboard.dart';
import 'transactions_page.dart';

class HomeShell extends StatefulWidget {
  final int userId;

  const HomeShell({
    super.key,
    required this.userId,
  });

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          DashboardPage(userId: widget.userId),
          TransactionsPage(userId: widget.userId),
          _SettingsPlaceholderPage(userId: widget.userId),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0F2027),
          border: Border(
            top: BorderSide(color: Colors.white.withOpacity(0.08)),
          ),
        ),
        child: BottomNavigationBar(
          currentIndex: _index,
          onTap: (i) => setState(() => _index = i),
          backgroundColor: const Color(0xFF0F2027),
          selectedItemColor: const Color(0xFF00C9A7),
          unselectedItemColor: Colors.white.withOpacity(0.65),
          type: BottomNavigationBarType.fixed,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.dashboard_outlined),
              activeIcon: Icon(Icons.dashboard),
              label: 'Dashboard',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.list_alt_outlined),
              activeIcon: Icon(Icons.list_alt),
              label: 'Transações',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.settings_outlined),
              activeIcon: Icon(Icons.settings),
              label: 'Ajustes',
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsPlaceholderPage extends StatelessWidget {
  final int userId;
  
  const _SettingsPlaceholderPage({required this.userId});

  @override
  Widget build(BuildContext context) {
    return _SettingsPage(userId: userId);
  }
}

class _SettingsPage extends StatefulWidget {
  final int userId;

  const _SettingsPage({required this.userId});

  @override
  State<_SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<_SettingsPage> {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
  );
  final LocalAuthentication _localAuth = LocalAuthentication();

  bool _biometricAvailable = false;
  bool _biometricEnabled = false;
  bool _toggleBusy = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final isDeviceSupported = await _localAuth.isDeviceSupported();
      final enabledRaw = await _storage.read(key: 'biometric_enabled');

      if (!mounted) return;
      setState(() {
        _biometricAvailable = canCheck && isDeviceSupported;
        _biometricEnabled = enabledRaw == 'true';
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao verificar biometria: $e')),
      );
      setState(() {
        _biometricAvailable = false;
        _biometricEnabled = false;
        _loading = false;
      });
    }
  }

  Future<void> _setBiometricEnabled(bool value) async {
    if (!mounted || _toggleBusy) return;
    final previousValue = _biometricEnabled;
    setState(() {
      _toggleBusy = true;
      _biometricEnabled = value;
    });

    if (value) {
      if (!_biometricAvailable) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Biometria indisponível neste dispositivo.')),
        );
        setState(() {
          _biometricEnabled = previousValue;
          _toggleBusy = false;
        });
        return;
      }

      // Verificar se já tem credenciais salvas da sessão atual
      final savedEmail = await _storage.read(key: 'saved_email');
      final savedPassword = await _storage.read(key: 'saved_password');
      
      if (savedEmail == null || savedPassword == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Faça login primeiro para ativar a biometria.'),
            duration: Duration(seconds: 3),
          ),
        );
        setState(() {
          _biometricEnabled = previousValue;
          _toggleBusy = false;
        });
        return;
      }

      // Autenticar com biometria
      try {
        final authenticated = await _localAuth.authenticate(
          localizedReason: 'Confirme sua identidade para ativar a biometria',
          options: const AuthenticationOptions(
            biometricOnly: true,
            stickyAuth: true,
          ),
        );
        
        if (!authenticated) {
          if (!mounted) return;
          setState(() {
            _biometricEnabled = previousValue;
            _toggleBusy = false;
          });
          return;
        }
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro na autenticação: $e')),
        );
        setState(() {
          _biometricEnabled = previousValue;
          _toggleBusy = false;
        });
        return;
      }
    }

    await _storage.write(key: 'biometric_enabled', value: value ? 'true' : 'false');
    if (!mounted) return;
    setState(() => _toggleBusy = false);
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Biometria ${value ? "ativada" : "desativada"} com sucesso!')),
    );
  }

  void _resetToggle(bool previousValue) {
    if (!mounted) return;
    setState(() {
      _biometricEnabled = previousValue;
      _toggleBusy = false;
    });
  }

  Future<void> _logout() async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Sair'),
          content: const Text('Deseja sair da sua conta?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Sair'),
            ),
          ],
        );
      },
    );

    if (shouldLogout != true) return;

    // NÃO apagar credenciais para manter biometria funcionando
    // await _storage.delete(key: 'saved_email');
    // await _storage.delete(key: 'saved_password');

    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final changed = await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (_) => AddTransactionPage(userId: widget.userId),
            ),
          );
          if (changed == true) {
            financeRefreshTick.value = financeRefreshTick.value + 1;
          }
        },
        backgroundColor: const Color(0xFF00C9A7),
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0F2027), Color(0xFF203A43), Color(0xFF2C5364)],
          ),
        ),
        child: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    const Text(
                      'Ajustes',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Card(
                      color: Colors.white.withOpacity(0.08),
                      child: Column(
                        children: [
                          SwitchListTile(
                            value: _biometricEnabled,
                            onChanged: _setBiometricEnabled,
                            title: const Text(
                              'Ativar biometria',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              _biometricAvailable
                                  ? 'Usar digital/FaceID para entrar'
                                  : 'Indisponível neste dispositivo',
                              style: TextStyle(color: Colors.white.withOpacity(0.75)),
                            ),
                            activeColor: const Color(0xFF00C9A7),
                          ),
                          ListTile(
                            onTap: _logout,
                            leading: const Icon(Icons.logout, color: Colors.white),
                            title: const Text(
                              'Sair',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              'Voltar para a tela de login',
                              style: TextStyle(color: Colors.white.withOpacity(0.75)),
                            ),
                          ),
                          ListTile(
                            onTap: () => SystemNavigator.pop(),
                            leading: const Icon(Icons.close, color: Colors.white),
                            title: const Text(
                              'Sair do app',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              'Fechar o aplicativo',
                              style: TextStyle(color: Colors.white.withOpacity(0.75)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
