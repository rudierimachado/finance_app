import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import 'add_transaction.dart';
import 'config.dart';
import 'dashboard.dart';
import 'planning_page.dart';
import 'transactions_page.dart';
import 'workspace_selector.dart';

class HomeShell extends StatefulWidget {
  final int userId;
  final int? initialWorkspaceId;
  final String? initialWorkspaceName;

  const HomeShell({
    super.key,
    required this.userId,
    this.initialWorkspaceId,
    this.initialWorkspaceName,
  });

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  int? _activeWorkspaceId;
  String _activeWorkspaceName = 'Workspace';
  String? _workspaceOwnerName;
  Timer? _refreshTimer;
  int _lastWorkspaceId = 0;

  void _applyWorkspaceChange(int? workspaceId) {
    if (workspaceId != null) {
      setState(() {
        _activeWorkspaceId = workspaceId;
        _lastWorkspaceId = workspaceId;
      });
    }
    _loadActiveWorkspaceName();
    financeRefreshTick.value = financeRefreshTick.value + 1;
  }

  @override
  void initState() {
    super.initState();
    _activeWorkspaceId = widget.initialWorkspaceId;
    if (widget.initialWorkspaceName != null && widget.initialWorkspaceName!.isNotEmpty) {
      _activeWorkspaceName = widget.initialWorkspaceName!;
    }
    if (_activeWorkspaceId != null) {
      _lastWorkspaceId = _activeWorkspaceId!;
    }
    _loadActiveWorkspaceName();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _startAutoRefresh() {
    // Auto-refresh a cada 10 segundos para detectar mudanças de workspace
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      _checkWorkspaceChanges();
    });
  }

  Future<void> _checkWorkspaceChanges() async {
    if (!mounted) return;
    
    try {
      final uri = Uri.parse('$apiBaseUrl/gerenciamento-financeiro/api/workspaces/active?user_id=${widget.userId}');
      final response = await http.get(uri, headers: {'Content-Type': 'application/json'});
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['workspace'] != null) {
          final newWorkspaceId = data['workspace']['id'] as int?;
          
          // Se workspace mudou, atualizar UI e dados
          if (newWorkspaceId != null && newWorkspaceId != _lastWorkspaceId) {
            print('[AUTO_REFRESH] Workspace mudou de $_lastWorkspaceId para $newWorkspaceId');
            _lastWorkspaceId = newWorkspaceId;
            
            // Recarregar dados do workspace
            await _loadActiveWorkspaceName();
            
            // Trigger refresh nos componentes filhos
            financeRefreshTick.value = financeRefreshTick.value + 1;
            
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Workspace sincronizado automaticamente'),
                  duration: Duration(seconds: 2),
                  backgroundColor: Color(0xFF00C9A7),
                ),
              );
            }
          }
        }
      }
    } catch (e) {
      // Silenciar erros de conectividade para não spam o usuário
      print('[AUTO_REFRESH] Erro: $e');
    }
  }

  Future<void> _loadActiveWorkspaceName() async {
    try {
      final params = <String, String>{
        'user_id': widget.userId.toString(),
        if (_activeWorkspaceId != null) 'workspace_id': _activeWorkspaceId.toString(),
      };
      final uri = Uri.parse('$apiBaseUrl/gerenciamento-financeiro/api/workspaces/active')
          .replace(queryParameters: params);
      print('[HOME_SHELL] Carregando workspace ativo para userId=${widget.userId}');
      print('[HOME_SHELL] URL: $uri');
      
      final response = await http.get(uri, headers: {'Content-Type': 'application/json'});
      print('[HOME_SHELL] Status: ${response.statusCode}');
      print('[HOME_SHELL] Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('[HOME_SHELL] Parsed data: $data');
        
        if (data['success'] == true && data['workspace'] != null) {
          final workspace = data['workspace'];
          final isOwner = workspace['is_owner'] as bool? ?? true;
          final ownerName = workspace['owner_name']?.toString();
          final workspaceName = workspace['name']?.toString() ?? 'Workspace';
          final workspaceId = workspace['id'] as int?;

          if (_activeWorkspaceId != null && workspaceId != null && _activeWorkspaceId != workspaceId) {
            print('[HOME_SHELL] Ignorando resposta do servidor: workspaceId=$workspaceId (cliente está em $_activeWorkspaceId)');
            return;
          }
          
          print('[HOME_SHELL] Workspace name: $workspaceName');
          print('[HOME_SHELL] Is owner: $isOwner');
          print('[HOME_SHELL] Owner name: $ownerName');
          
          if (mounted) {
            setState(() {
              _activeWorkspaceId = workspaceId;
              _activeWorkspaceName = workspaceName;
              _workspaceOwnerName = !isOwner && ownerName != null ? ownerName : null;
            });
            
            // Atualizar controle de mudanças
            if (workspaceId != null) {
              _lastWorkspaceId = workspaceId;
            }
            
            print('[HOME_SHELL] Estado atualizado - Nome: $_activeWorkspaceName, Owner: $_workspaceOwnerName, ID: $_activeWorkspaceId');
          }
        }
      } else {
        print('[HOME_SHELL] Erro HTTP: ${response.statusCode}');
      }
    } catch (e) {
      print('Error loading active workspace name: $e');
      if (mounted) {
        setState(() {
          _activeWorkspaceName = 'Workspace';
          _workspaceOwnerName = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.workspaces, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _activeWorkspaceName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 18,
                  ),
                ),
                if (_workspaceOwnerName != null)
                  Text(
                    'por $_workspaceOwnerName',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
              ],
            ),
          ],
        ),
        backgroundColor: const Color(0xFF0F2027),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white70),
            onPressed: () => setState(() => _index = 3),
            tooltip: 'Ajustes',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'main_fab',
        onPressed: () async {
          final changed = await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (_) => AddTransactionPage(
                userId: widget.userId,
                workspaceId: _activeWorkspaceId,
              ),
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
      body: IndexedStack(
        index: _index,
        children: [
          DashboardPage(userId: widget.userId, workspaceId: _activeWorkspaceId),
          TransactionsPage(userId: widget.userId, workspaceId: _activeWorkspaceId),
          PlanningPage(userId: widget.userId, workspaceId: _activeWorkspaceId),
          _SettingsPlaceholderPage(
            userId: widget.userId,
            activeWorkspaceId: _activeWorkspaceId,
            onWorkspaceChanged: _applyWorkspaceChange,
          ),
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
              icon: Icon(Icons.insights_outlined),
              activeIcon: Icon(Icons.insights),
              label: 'Planejamento',
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

class ShareDialog extends StatefulWidget {
  final int userId;
  final int? workspaceId;
  final String? workspaceName;

  const ShareDialog({
    super.key,
    required this.userId,
    this.workspaceId,
    this.workspaceName,
  });

  @override
  State<ShareDialog> createState() => _ShareDialogState();
}

class _ShareDialogState extends State<ShareDialog> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  String _role = 'viewer';
  bool _isLoading = false;
  bool _loadingWorkspace = true;
  String? _workspaceName;
  int? _workspaceId;
  String? _workspaceError;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    if (widget.workspaceId != null) {
      _workspaceId = widget.workspaceId;
      _workspaceName = widget.workspaceName;
      _loadingWorkspace = false;
    } else {
      _loadActiveWorkspace();
    }
  }

  Future<void> _loadActiveWorkspace() async {
    setState(() {
      _loadingWorkspace = true;
      _workspaceError = null;
    });

    final uri = Uri.parse('$apiBaseUrl/gerenciamento-financeiro/api/user/active-workspace?user_id=${widget.userId}');
    try {
      final resp = await http.get(uri, headers: {'Content-Type': 'application/json'});
      final code = resp.statusCode;
      if (kDebugMode) {
        print('[INVITE][ACTIVE_WS] status=$code body=${resp.body}');
      }

      if (code == 200) {
        final data = jsonDecode(resp.body);
        setState(() {
          _workspaceId = data['workspace_id'] as int?;
          _workspaceName = data['name']?.toString();
          _loadingWorkspace = false;
        });
      } else {
        final data = jsonDecode(resp.body);
        final msg = data['message']?.toString() ?? 'Erro ao carregar workspace';
        setState(() {
          _workspaceError = msg;
          _loadingWorkspace = false;
        });
      }
    } catch (e) {
      if (kDebugMode) print('[INVITE][ACTIVE_WS][ERR] $e');
      setState(() {
        _workspaceError = 'Erro de conexão';
        _loadingWorkspace = false;
      });
    }
  }

  void _sendInvite() async {
    if (!_formKey.currentState!.validate()) return;

    final workspaceId = _workspaceId;
    if (workspaceId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Workspace ativo não encontrado.')),
      );
      return;
    }

    setState(() => _isLoading = true);

    final email = _emailController.text.trim();
    final role = _role;

    final uri = Uri.parse('$apiBaseUrl/gerenciamento-financeiro/api/workspace/invite');
    if (kDebugMode) {
      print('[INVITE] Enviando convite: email=$email role=$role workspace_id=$workspaceId user_id=${widget.userId}');
    }

    try {
      final resp = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'workspace_id': workspaceId,
          'recipient_email': email,
          'role': role,
          'user_id': widget.userId,
        }),
      );

      if (kDebugMode) {
        print('[INVITE] status=${resp.statusCode} body=${resp.body}');
      }

      String message = 'Convite enviado!';
      if (resp.statusCode == 200 || resp.statusCode == 201) {
        if (!mounted) return;
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
        return;
      } else if (resp.statusCode == 400) {
        final data = jsonDecode(resp.body);
        message = data['message']?.toString() ?? 'Dados inválidos';
      } else if (resp.statusCode == 403) {
        message = 'Você não tem permissão para convidar';
      } else if (resp.statusCode == 404) {
        message = 'Workspace não encontrado';
      } else {
        message = 'Erro ao enviar convite. Tente novamente.';
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().contains('SocketException')
          ? 'Erro de conexão'
          : 'Erro inesperado';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      if (kDebugMode) {
        print('[INVITE][ERR] $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  int? _getCurrentWorkspaceId() {
    return _workspaceId;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: const Color(0xFF2C5364),
      title: const Text(
        'Compartilhar Workspace',
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
      ),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_loadingWorkspace) ...[
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 8.0),
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                ),
              ),
              const SizedBox(height: 12),
            ] else if (_workspaceError != null) ...[
              Text(
                _workspaceError!,
                style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
            ] else if (_workspaceName != null) ...[
              Text(
                'Workspace: ${_workspaceName!}',
                style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
            ],
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: 'Email',
                labelStyle: const TextStyle(color: Colors.white70),
                filled: true,
                fillColor: Colors.white.withOpacity(0.08),
                hintText: 'pessoa@email.com',
                hintStyle: const TextStyle(color: Colors.white54),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              style: const TextStyle(color: Colors.white),
              validator: (value) {
                final v = (value ?? '').trim();
                if (v.isEmpty) return 'Email obrigatório';
                if (!v.contains('@')) return 'Email inválido';
                return null;
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _role,
              items: const [
                DropdownMenuItem(value: 'viewer', child: Text('Viewer')),
                DropdownMenuItem(value: 'editor', child: Text('Editor')),
              ],
              onChanged: (val) => setState(() => _role = val ?? 'viewer'),
              decoration: InputDecoration(
                labelText: 'Permissão',
                labelStyle: const TextStyle(color: Colors.white70),
                filled: true,
                fillColor: Colors.white.withOpacity(0.08),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              dropdownColor: const Color(0xFF2C5364),
              style: const TextStyle(color: Colors.white),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar', style: TextStyle(color: Colors.white70)),
        ),
        ElevatedButton(
          onPressed: _isLoading || _loadingWorkspace || _workspaceId == null ? null : _sendInvite,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF00C9A7),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: _isLoading
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Enviar Convite', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}

class _SettingsPlaceholderPage extends StatefulWidget {
  final int userId;
  final int? activeWorkspaceId;
  final ValueChanged<int?>? onWorkspaceChanged;
  
  const _SettingsPlaceholderPage({required this.userId, this.activeWorkspaceId, this.onWorkspaceChanged});

  @override
  State<_SettingsPlaceholderPage> createState() => _SettingsPlaceholderPageState();
}

class _SettingsPlaceholderPageState extends State<_SettingsPlaceholderPage> {
  @override
  Widget build(BuildContext context) {
    return _SettingsPage(
      userId: widget.userId,
      activeWorkspaceId: widget.activeWorkspaceId,
      onWorkspaceChanged: widget.onWorkspaceChanged,
    );
  }
}

class _SettingsPage extends StatefulWidget {
  final int userId;
  final int? activeWorkspaceId;
  final ValueChanged<int?>? onWorkspaceChanged;

  const _SettingsPage({required this.userId, this.activeWorkspaceId, this.onWorkspaceChanged});

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

  Future<void> _openWorkspaceManager() async {
    final result = await showModalBottomSheet<dynamic>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final size = MediaQuery.of(ctx).size;
        final bottomPadding = MediaQuery.of(ctx).padding.bottom;
        final bottomGap = kBottomNavigationBarHeight + bottomPadding + 8;
        final heightFactor = ((size.height - bottomGap) / size.height).clamp(0.75, 0.95);

        return Padding(
          padding: EdgeInsets.only(bottom: bottomGap),
          child: FractionallySizedBox(
            heightFactor: heightFactor,
            alignment: Alignment.bottomCenter,
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
              child: WorkspaceManagerPage(
                userId: widget.userId,
                initialActiveWorkspaceId: widget.activeWorkspaceId,
              ),
            ),
          ),
        );
      },
    );

    if (widget.onWorkspaceChanged == null) return;

    if (result is int) {
      widget.onWorkspaceChanged!(result);
      return;
    }

    if (result == true) {
      widget.onWorkspaceChanged!(null);
    }
  }

  void _openShareDialog(BuildContext context) {
    showDialog<bool>(
      context: context,
      builder: (_) => ShareDialog(userId: widget.userId),
    ).then((result) {
      if (!mounted) return;
      if (result == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Convite enviado (mock).')),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                            onTap: _openWorkspaceManager,
                            leading: const Icon(Icons.workspaces, color: Colors.white),
                            title: const Text(
                              'Workspaces',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              'Trocar, editar e compartilhar workspaces',
                              style: TextStyle(color: Colors.white.withOpacity(0.75)),
                            ),
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

class WorkspaceManagerPage extends StatefulWidget {
  final int userId;
  final int? initialActiveWorkspaceId;
  
  const WorkspaceManagerPage({super.key, required this.userId, this.initialActiveWorkspaceId});

  @override
  State<WorkspaceManagerPage> createState() => _WorkspaceManagerPageState();
}

class _Workspace {
  final int id;
  String name;
  String? description;
  String? color;

  _Workspace({
    required this.id,
    required this.name,
    this.description,
    this.color,
  });

  factory _Workspace.fromJson(Map<String, dynamic> json) {
    return _Workspace(
      id: json['id'] as int,
      name: json['name']?.toString() ?? 'Workspace',
      description: json['description']?.toString(),
      color: json['color']?.toString(),
    );
  }
}

class _WorkspaceManagerPageState extends State<WorkspaceManagerPage> {

  final _nameController = TextEditingController();
  final _newNameController = TextEditingController();

  List<_Workspace> _workspaces = [];
  int? _activeId;
  bool _loading = true;
  bool _saving = false;
  bool _switching = false;

  void _openShareDialog(BuildContext context) {
    final active = _workspaces.firstWhere((w) => w.id == _activeId, orElse: () => _workspaces.first);
    showDialog<bool>(
      context: context,
      builder: (_) => ShareDialog(
        userId: widget.userId,
        workspaceId: active.id,
        workspaceName: active.name,
      ),
    ).then((result) {
      if (!mounted) return;
      if (result == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Convite enviado (mock).')),
        );
      }
    });
  }

  Future<void> _renameWorkspace(_Workspace workspace, String newName, {String? description, String? color}) async {
    if (newName.trim().isEmpty) return;

    setState(() {
      _saving = true;
    });

    try {
      final uri = Uri.parse('$apiBaseUrl/gerenciamento-financeiro/api/workspaces/${workspace.id}?user_id=${widget.userId}');
      final response = await http.put(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'name': newName.trim(),
          if (description != null) 'description': description,
          if (color != null) 'color': color,
        }),
      );

      setState(() {
        _saving = false;
      });

      if (response.statusCode == 200) {
        setState(() {
          workspace.name = newName.trim();
          if (description != null) {
            workspace.description = description;
          }
          if (color != null) {
            workspace.color = color;
          }
          if (_activeId == workspace.id) {
            _nameController.text = workspace.name;
          }
        });

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: const [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 12),
                Text('Workspace renomeado com sucesso!'),
              ],
            ),
            backgroundColor: const Color(0xFF00C9A7),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            duration: const Duration(seconds: 2),
          ),
        );
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: const [
                Icon(Icons.error_outline, color: Colors.white),
                SizedBox(width: 12),
                Text('Erro ao renomear workspace'),
              ],
            ),
            backgroundColor: Colors.red.shade400,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      print('Error renaming workspace: $e');
      setState(() {
        _saving = false;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: const [
              Icon(Icons.error_outline, color: Colors.white),
              SizedBox(width: 12),
              Text('Erro de conexão'),
            ],
          ),
          backgroundColor: Colors.red.shade400,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  Future<void> _promptEditWorkspace(_Workspace workspace) async {
    final nameController = TextEditingController(text: workspace.name);
    final descController = TextEditingController(text: workspace.description ?? '');

    final palette = <String>[
      '#00C9A7',
      '#00B4D8',
      '#3b82f6',
      '#8b5cf6',
      '#f97316',
      '#ef4444',
      '#22c55e',
      '#64748B',
    ];

    String normalizeHex(String? hex) {
      final h = (hex ?? '').trim();
      if (h.isEmpty) return palette.first;
      return h.startsWith('#') ? h : '#$h';
    }

    var selectedColor = normalizeHex(workspace.color);
    if (!palette.contains(selectedColor)) {
      selectedColor = palette.first;
    }

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text('Editar workspace'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(labelText: 'Nome'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descController,
                      decoration: const InputDecoration(labelText: 'Descrição'),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Cor',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: palette.map((hex) {
                        final isSelected = selectedColor == hex;
                        return InkWell(
                          onTap: () {
                            setStateDialog(() {
                              selectedColor = hex;
                            });
                          },
                          borderRadius: BorderRadius.circular(18),
                          child: Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: _colorFromHex(hex),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isSelected ? const Color(0xFF00C9A7) : Colors.transparent,
                                width: 3,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(null),
                  child: const Text('Cancelar'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop({
                    'name': nameController.text,
                    'description': descController.text,
                    'color': selectedColor,
                  }),
                  child: const Text('Salvar'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == null) return;
    final newName = (result['name']?.toString() ?? '').trim();
    final newDesc = result['description']?.toString();
    final newColor = result['color']?.toString();
    await _renameWorkspace(workspace, newName, description: newDesc, color: newColor);
  }

  @override
  void initState() {
    super.initState();
    _loadWorkspaces();
  }

  Future<void> _loadWorkspaces() async {
    try {
      final uri = Uri.parse('$apiBaseUrl/gerenciamento-financeiro/api/workspaces?user_id=${widget.userId}');
      final response = await http.get(uri, headers: {'Content-Type': 'application/json'});

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          _workspaces = (data['workspaces'] as List<dynamic>)
              .map((json) => _Workspace.fromJson(json))
              .toList();
        }
      }

      // Se não retornou workspaces, o backend já criou um padrão
      // Não criar workspace local, sempre usar o do banco
      if (_workspaces.isEmpty) {
        print('Nenhum workspace retornado - backend deve ter criado um padrão');
        setState(() {
          _loading = false;
        });
        return;
      }

      // Priorizar workspace ativo vindo do app (determinístico)
      final hinted = widget.initialActiveWorkspaceId;
      if (hinted != null && _workspaces.any((w) => w.id == hinted)) {
        _activeId = hinted;
      } else {
        // Fallback: buscar workspace ativo no servidor (se necessário)
        try {
          final params = <String, String>{
            'user_id': widget.userId.toString(),
            if (hinted != null) 'workspace_id': hinted.toString(),
          };
          final activeUri = Uri.parse('$apiBaseUrl/gerenciamento-financeiro/api/workspaces/active')
              .replace(queryParameters: params);
          final activeResponse = await http.get(activeUri, headers: {'Content-Type': 'application/json'});

          if (activeResponse.statusCode == 200) {
            final activeData = jsonDecode(activeResponse.body);
            if (activeData['success'] == true && activeData['workspace'] != null) {
              _activeId = activeData['workspace']['id'];
            }
          }
        } catch (e) {
          print('Error loading active workspace: $e');
        }
      }

      _activeId ??= _workspaces.first.id;

      if (_workspaces.isNotEmpty) {
        _nameController.text = _workspaces
            .firstWhere((w) => w.id == _activeId, orElse: () => _workspaces.first)
            .name;
      }

      setState(() {
        _loading = false;
      });
    } catch (e) {
      print('Error loading workspaces: $e');
      setState(() {
        _loading = false;
      });
    }
  }


  Future<void> _renameActive() async {
    final active = _workspaces.firstWhere((w) => w.id == _activeId, orElse: () => _workspaces.first);
    final newName = _nameController.text.trim();
    if (newName.isEmpty) return;

    setState(() {
      _saving = true;
    });

    try {
      final uri = Uri.parse('$apiBaseUrl/gerenciamento-financeiro/api/workspaces/${active.id}?user_id=${widget.userId}');
      final response = await http.put(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'name': newName}),
      );

      setState(() {
        _saving = false;
      });

      if (response.statusCode == 200) {
        setState(() {
          active.name = newName;
        });

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: const [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 12),
                Text('Workspace renomeado com sucesso!'),
              ],
            ),
            backgroundColor: const Color(0xFF00C9A7),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            duration: const Duration(seconds: 2),
          ),
        );
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: const [
                Icon(Icons.error_outline, color: Colors.white),
                SizedBox(width: 12),
                Text('Erro ao renomear workspace'),
              ],
            ),
            backgroundColor: Colors.red.shade400,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      print('Error renaming workspace: $e');
      setState(() {
        _saving = false;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: const [
              Icon(Icons.error_outline, color: Colors.white),
              SizedBox(width: 12),
              Text('Erro de conexão'),
            ],
          ),
          backgroundColor: Colors.red.shade400,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  Future<void> _createWorkspace() async {
    final name = _newNameController.text.trim();
    if (name.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe um nome para o novo workspace.')),
      );
      return;
    }

    try {
      final uri = Uri.parse('$apiBaseUrl/gerenciamento-financeiro/api/workspaces?user_id=${widget.userId}');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'name': name}),
      );

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['workspace'] != null) {
          final newWorkspace = _Workspace.fromJson(data['workspace']);

          setState(() {
            _workspaces.add(newWorkspace);
            _activeId = newWorkspace.id;
            _nameController.text = name;
            _newNameController.clear();
          });

          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Workspace criado com saldo zerado.')),
          );
        }
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erro ao criar workspace.')),
        );
      }
    } catch (e) {
      print('Error creating workspace: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erro ao criar workspace.')),
      );
    }
  }

  Future<void> _onActiveChanged(int? newId) async {
    if (newId == null || newId == _activeId) return;

    setState(() {
      _switching = true;
    });

    try {
      final uri = Uri.parse('$apiBaseUrl/gerenciamento-financeiro/api/workspaces/$newId/activate?user_id=${widget.userId}');
      final response = await http.post(uri, headers: {'Content-Type': 'application/json'});

      setState(() {
        _switching = false;
      });

      if (response.statusCode == 200) {
        setState(() {
          _activeId = newId;
          _nameController.text = _workspaces.firstWhere((w) => w.id == newId).name;
        });

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: const [
                Icon(Icons.swap_horiz, color: Colors.white),
                SizedBox(width: 12),
                Text('Workspace alterado com sucesso!'),
              ],
            ),
            backgroundColor: const Color(0xFF00C9A7),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            duration: const Duration(seconds: 2),
          ),
        );
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: const [
                Icon(Icons.error_outline, color: Colors.white),
                SizedBox(width: 12),
                Text('Erro ao trocar workspace'),
              ],
            ),
            backgroundColor: Colors.red.shade400,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      print('Error changing active workspace: $e');
      setState(() {
        _switching = false;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: const [
              Icon(Icons.error_outline, color: Colors.white),
              SizedBox(width: 12),
              Text('Erro de conexão'),
            ],
          ),
          backgroundColor: Colors.red.shade400,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _newNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isMobile = screenSize.width < 600; // Consider mobile if width < 600

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Garantir que sempre há um workspace antes de acessar
    if (_workspaces.isEmpty) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.white70),
              const SizedBox(height: 16),
              const Text(
                'Erro ao carregar workspaces',
                style: TextStyle(color: Colors.white, fontSize: 18),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Voltar'),
              ),
            ],
          ),
        ),
        backgroundColor: const Color(0xFF0F2027),
      );
    }

    final active = _workspaces.firstWhere((w) => w.id == _activeId, orElse: () => _workspaces.first);

    return WillPopScope(
      onWillPop: () async {
        Navigator.of(context).pop(_activeId ?? true);
        return false;
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF0F2027), Color(0xFF203A43), Color(0xFF2C5364)],
            ),
          ),
          child: CustomScrollView(
            slivers: [
              SliverAppBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                pinned: true,
                leading: IconButton(
                  icon: const Icon(Icons.chevron_left, color: Colors.white),
                  onPressed: () => Navigator.of(context).pop(_activeId ?? true),
                  tooltip: 'Voltar',
                ),
                title: const Text(
                  'Workspaces',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                ),
                centerTitle: true,
              ),
              SliverToBoxAdapter(
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(isMobile ? 12 : 16, 12, isMobile ? 12 : 16, 0),
                    child: _buildSettingsCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_switching)
                            const LinearProgressIndicator(
                              minHeight: 3,
                              backgroundColor: Colors.transparent,
                              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00C9A7)),
                            ),
                          if (_switching) const SizedBox(height: 12),
                          Row(
                            children: [
                              Container(
                                width: isMobile ? 36 : 42,
                                height: isMobile ? 36 : 42,
                                decoration: BoxDecoration(
                                  color: _colorFromHex(active.color ?? '#64748B').withOpacity(0.25),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: Colors.white.withOpacity(0.12)),
                                ),
                                child: Icon(Icons.workspaces, color: _colorFromHex(active.color ?? '#64748B')),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      active.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: isMobile ? 14 : 16,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      (active.description ?? '').trim().isEmpty
                                          ? 'Workspace ativo'
                                          : active.description!,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: isMobile ? 12 : 14),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF00C9A7).withOpacity(0.16),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(color: const Color(0xFF00C9A7).withOpacity(0.35)),
                                ),
                                child: Text(
                                  'Ativo',
                                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: isMobile ? 10 : 12),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          if (isMobile)
                            Column(
                              children: [
                                OutlinedButton.icon(
                                  onPressed: _switching ? null : () => _openShareDialog(context),
                                  icon: const Icon(Icons.share, size: 18),
                                  label: const Text('Compartilhar'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.white,
                                    side: BorderSide(color: Colors.white.withOpacity(0.18)),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    minimumSize: const Size.fromHeight(44),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                ElevatedButton.icon(
                                  onPressed: _saving ? null : () => _promptEditWorkspace(active),
                                  icon: const Icon(Icons.edit, size: 18),
                                  label: const Text('Editar'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF00C9A7),
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    minimumSize: const Size.fromHeight(44),
                                    disabledBackgroundColor: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            )
                          else
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: _switching ? null : () => _openShareDialog(context),
                                    icon: const Icon(Icons.share, size: 18),
                                    label: const Text('Compartilhar'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.white,
                                      side: BorderSide(color: Colors.white.withOpacity(0.18)),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: _saving ? null : () => _promptEditWorkspace(active),
                                    icon: const Icon(Icons.edit, size: 18),
                                    label: const Text('Editar'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF00C9A7),
                                      foregroundColor: Colors.white,
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      disabledBackgroundColor: Colors.grey.shade600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(isMobile ? 12 : 16, isMobile ? 12 : 16, isMobile ? 12 : 16, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSectionTitle('Seus workspaces'),
                        const SizedBox(height: 12),
                        ..._workspaces.map((w) {
                          final isActive = w.id == _activeId;
                          final dotColor = _colorFromHex(w.color ?? '#64748B');
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _buildSettingsCard(
                              child: InkWell(
                                onTap: _switching ? null : () => _onActiveChanged(w.id),
                                borderRadius: BorderRadius.circular(20),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 12,
                                        height: 12,
                                        decoration: BoxDecoration(
                                          color: dotColor,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              w.name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w700,
                                                fontSize: isMobile ? 14 : 16,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              (w.description ?? '').trim().isEmpty
                                                  ? (isActive ? 'Workspace ativo' : 'Toque para trocar')
                                                  : w.description!,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(color: Colors.white.withOpacity(0.72), fontSize: isMobile ? 12 : 14),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (isActive)
                                        Container(
                                          margin: const EdgeInsets.only(right: 6),
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF00C9A7).withOpacity(0.16),
                                            borderRadius: BorderRadius.circular(999),
                                            border: Border.all(color: const Color(0xFF00C9A7).withOpacity(0.35)),
                                          ),
                                          child: Text(
                                            'Ativo',
                                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: isMobile ? 10 : 12),
                                          ),
                                        ),
                                      IconButton(
                                        onPressed: _saving ? null : () => _promptEditWorkspace(w),
                                        icon: const Icon(Icons.edit, color: Colors.white70),
                                        tooltip: 'Editar',
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                        const SizedBox(height: 8),
                        _buildSectionTitle('Criar novo workspace'),
                        const SizedBox(height: 12),
                        _buildSettingsCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              TextFormField(
                                controller: _newNameController,
                                style: const TextStyle(color: Colors.white),
                                decoration: InputDecoration(
                                  labelText: 'Nome',
                                  labelStyle: const TextStyle(color: Colors.white70),
                                  hintText: 'Ex: Pessoal, Trabalho, Família',
                                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.35)),
                                  border: const OutlineInputBorder(),
                                  filled: true,
                                  fillColor: Colors.white.withOpacity(0.06),
                                  enabledBorder: OutlineInputBorder(
                                    borderSide: BorderSide(color: Colors.white.withOpacity(0.16)),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderSide: const BorderSide(color: Color(0xFF00C9A7), width: 2),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  icon: const Icon(Icons.add),
                                  label: const Text('Criar workspace'),
                                  onPressed: _createWorkspace,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF00C9A7),
                                    foregroundColor: Colors.white,
                                    minimumSize: const Size.fromHeight(48),
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _buildAppBar(BuildContext context, {int? activeWorkspaceId}) {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
    child: Row(
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left, color: Colors.white),
          onPressed: () {
            Navigator.of(context).pop(activeWorkspaceId ?? true);
          },
          tooltip: 'Voltar',
        ),
        const Expanded(
          child: Text(
            'Gerenciar workspaces',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 48),
      ],
    ),
  );
}

Widget _buildSectionTitle(String title) {
  return Text(
    title,
    style: const TextStyle(
      color: Colors.white,
      fontSize: 16,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.3,
    ),
  );
}

Widget _buildSettingsCard({required Widget child}) {
  return Card(
    color: Colors.white.withOpacity(0.08),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    elevation: 0,
    child: Padding(
      padding: const EdgeInsets.all(16.0),
      child: child,
    ),
  );
}

Color _colorFromHex(String hex) {
  final cleaned = hex.trim().replaceAll('#', '');
  if (cleaned.length == 6) {
    final value = int.tryParse('FF$cleaned', radix: 16);
    return Color(value ?? 0xFF64748B);
  }
  if (cleaned.length == 8) {
    final value = int.tryParse(cleaned, radix: 16);
    return Color(value ?? 0xFF64748B);
  }
  return const Color(0xFF64748B);
}
