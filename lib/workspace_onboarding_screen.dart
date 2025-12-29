import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'config.dart';
import 'home_shell.dart';

class WorkspaceOnboardingScreen extends StatefulWidget {
  const WorkspaceOnboardingScreen({super.key});

  @override
  State<WorkspaceOnboardingScreen> createState() => _WorkspaceOnboardingScreenState();
}

class _WorkspaceOnboardingScreenState extends State<WorkspaceOnboardingScreen> {
  bool loading = false;

  late int workspaceId;
  String? workspaceName;
  String? role;
  int userId = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    workspaceId = args?['workspace_id'] is int ? args!['workspace_id'] as int : int.tryParse('${args?['workspace_id'] ?? ''}') ?? 0;
    workspaceName = args?['workspace_name']?.toString();
    role = args?['role']?.toString();
    final argUser = args?['user_id'];
    if (argUser is int) {
      userId = argUser;
    } else if (argUser != null) {
      userId = int.tryParse(argUser.toString()) ?? 0;
    }
  }

  Future<void> _completeOnboarding() async {
    if (workspaceId == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Workspace inválido.')),
      );
      return;
    }
    setState(() => loading = true);
    try {
      final uri = Uri.parse(
          '$apiBaseUrl/gerenciamento-financeiro/api/workspaces/$workspaceId/complete_onboarding');
      final resp = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          if (userId > 0) 'user_id': userId,
          // Compartilhamento sempre total; não envia toggles
          'share_preferences': {
            'share_transactions': true,
            'share_categories': true,
            'share_files': true,
          },
        }),
      );

      if (!mounted) return;
      if (resp.statusCode == 200) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => HomeShell(
              userId: userId,
              initialWorkspaceId: workspaceId,
              initialWorkspaceName: workspaceName,
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao concluir onboarding (${resp.statusCode})')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro de conexão: $e')),
      );
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(workspaceName ?? 'Onboarding'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Compartilhar workspace',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            const Text(
              'Ao concluir, todos os membros terão acesso total às transações, categorias e anexos deste workspace.',
              style: TextStyle(fontSize: 14),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: loading ? null : _completeOnboarding,
                child: loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Concluir'),
              ),
            )
          ],
        ),
      ),
    );
  }

  // Toggles removidos: compartilhamento agora é sempre total
}
