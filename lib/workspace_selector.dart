import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'config.dart';
import 'home_shell.dart';

class WorkspaceSelectorPage extends StatefulWidget {
  final int userId;

  const WorkspaceSelectorPage({super.key, required this.userId});

  @override
  State<WorkspaceSelectorPage> createState() => _WorkspaceSelectorPageState();
}

class _WorkspaceSelectorPageState extends State<WorkspaceSelectorPage> {
  List<_Workspace> _workspaces = [];
  bool _loading = true;
  bool _creating = false;
  final _newNameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadWorkspaces();
  }

  Future<void> _loadWorkspaces() async {
    try {
      final uri = Uri.parse('$apiBaseUrl/gerenciamento-financeiro/api/workspaces?user_id=${widget.userId}');
      print('[WORKSPACE_SELECTOR] Carregando workspaces para userId=${widget.userId}');
      print('[WORKSPACE_SELECTOR] URL: $uri');
      
      final response = await http.get(uri, headers: {'Content-Type': 'application/json'});
      print('[WORKSPACE_SELECTOR] Status: ${response.statusCode}');
      print('[WORKSPACE_SELECTOR] Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('[WORKSPACE_SELECTOR] Success: ${data['success']}');
        
        if (data['success'] == true) {
          final workspacesList = data['workspaces'] as List<dynamic>;
          print('[WORKSPACE_SELECTOR] Workspaces encontrados: ${workspacesList.length}');
          
          _workspaces = workspacesList
              .map((json) => _Workspace.fromJson(json))
              .toList();
          
          print('[WORKSPACE_SELECTOR] Workspaces carregados: ${_workspaces.map((w) => w.name).toList()}');
        }
      } else {
        print('[WORKSPACE_SELECTOR] Erro HTTP: ${response.statusCode}');
      }

      setState(() {
        _loading = false;
      });
    } catch (e) {
      print('[WORKSPACE_SELECTOR] Erro ao carregar workspaces: $e');
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _selectWorkspace(int workspaceId) async {
    try {
      final uri = Uri.parse('$apiBaseUrl/gerenciamento-financeiro/api/workspaces/$workspaceId/activate?user_id=${widget.userId}');
      final response = await http.post(uri, headers: {'Content-Type': 'application/json'});

      if (response.statusCode == 200) {
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => HomeShell(userId: widget.userId),
          ),
        );
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erro ao ativar workspace')),
        );
      }
    } catch (e) {
      print('Erro ao ativar workspace: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erro de conexão')),
      );
    }
  }

  Future<void> _createWorkspace() async {
    final name = _newNameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Digite um nome para o workspace')),
      );
      return;
    }

    // Evitar múltiplas chamadas simultâneas
    if (_creating) {
      print('[WORKSPACE_SELECTOR] Já está criando workspace, ignorando chamada duplicada');
      return;
    }

    setState(() {
      _creating = true;
    });

    try {
      print('[WORKSPACE_SELECTOR] Criando workspace: $name');
      final uri = Uri.parse('$apiBaseUrl/gerenciamento-financeiro/api/workspaces?user_id=${widget.userId}');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'name': name}),
      );

      print('[WORKSPACE_SELECTOR] Resposta criação: ${response.statusCode}');

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['workspace'] != null) {
          final newWorkspaceId = data['workspace']['id'] as int;
          final workspaceName = data['workspace']['name'] as String;
          print('[WORKSPACE_SELECTOR] Workspace criado: id=$newWorkspaceId, name=$workspaceName');
          
          // Não resetar _creating aqui, deixar até navegar
          if (!mounted) return;
          _selectWorkspace(newWorkspaceId);
        }
      } else {
        setState(() {
          _creating = false;
        });
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erro ao criar workspace')),
        );
      }
    } catch (e) {
      print('[WORKSPACE_SELECTOR] Erro ao criar workspace: $e');
      setState(() {
        _creating = false;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erro de conexão')),
      );
    }
  }

  @override
  void dispose() {
    _newNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0F2027), Color(0xFF203A43), Color(0xFF2C5364)],
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: Color(0xFF00C9A7)))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 40),
                      const Text(
                        'Bem-vindo! 👋',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Selecione um workspace para começar',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 40),
                      
                      // Lista de workspaces existentes
                      if (_workspaces.isNotEmpty) ...[
                        const Text(
                          'Seus workspaces',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 16),
                        ..._workspaces.map((workspace) => _buildWorkspaceCard(workspace)),
                        const SizedBox(height: 32),
                      ],

                      // Criar novo workspace
                      const Text(
                        'Criar novo workspace',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Card(
                        color: Colors.white.withOpacity(0.08),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            children: [
                              TextField(
                                controller: _newNameController,
                                style: const TextStyle(color: Colors.white),
                                decoration: InputDecoration(
                                  labelText: 'Nome do workspace',
                                  labelStyle: const TextStyle(color: Colors.white70),
                                  hintText: 'Ex: Pessoal, Trabalho, Família...',
                                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                                  border: const OutlineInputBorder(),
                                  filled: true,
                                  fillColor: Colors.white.withOpacity(0.05),
                                  enabledBorder: OutlineInputBorder(
                                    borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                                  ),
                                  focusedBorder: const OutlineInputBorder(
                                    borderSide: BorderSide(color: Color(0xFF00C9A7), width: 2),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: _creating ? null : _createWorkspace,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF00C9A7),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    disabledBackgroundColor: Colors.grey.shade600,
                                  ),
                                  child: _creating
                                      ? const SizedBox(
                                          height: 20,
                                          width: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                          ),
                                        )
                                      : Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: const [
                                            Icon(Icons.add_circle_outline),
                                            SizedBox(width: 8),
                                            Text(
                                              'Criar e começar',
                                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                                            ),
                                          ],
                                        ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildWorkspaceCard(_Workspace workspace) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: Colors.white.withOpacity(0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _selectWorkspace(workspace.id),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFF00C9A7).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.folder_outlined,
                  color: Color(0xFF00C9A7),
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      workspace.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (workspace.description != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        workspace.description!,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.6),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios,
                color: Colors.white54,
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Workspace {
  final int id;
  final String name;
  final String? description;
  final String? color;

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
