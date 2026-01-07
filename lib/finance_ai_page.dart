import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'config.dart';

// Notificador para limpar o chat de fora do widget
final ValueNotifier<int> financeAiClearNotifier = ValueNotifier<int>(0);

class FinanceAiPage extends StatelessWidget {
  final int userId;
  final int? workspaceId;

  const FinanceAiPage({
    super.key,
    required this.userId,
    required this.workspaceId,
  });

  @override
  Widget build(BuildContext context) {
    return _FinanceAiChatPanel(
       userId: userId,
       workspaceId: workspaceId,
       mode: 'finance',
       emptyStateTitle: 'Assistente Financeiro Nexus',
       emptyStateSubtitle: 'Pergunte sobre seus gastos, rendimentos, saldo por categoria ou qualquer dúvida sobre suas transações.',
     );
  }
}

enum _AiRole { user, assistant }

class _AiMsg {
  final _AiRole role;
  final String content;
  final DateTime createdAt;

  _AiMsg({
    required this.role,
    required this.content,
    required this.createdAt,
  });
}

// Mapa estático para manter o histórico de mensagens durante a sessão do app
final Map<String, List<Map<String, dynamic>>> _sessionChatHistory = {};

class _FinanceAiChatPanel extends StatefulWidget {
  final int userId;
  final int? workspaceId;
  final String mode;
  final String emptyStateTitle;
  final String emptyStateSubtitle;

  const _FinanceAiChatPanel({
    required this.userId,
    required this.workspaceId,
    required this.mode,
    required this.emptyStateTitle,
    required this.emptyStateSubtitle,
  });

  @override
  State<_FinanceAiChatPanel> createState() => _FinanceAiChatPanelState();
}

class _FinanceAiChatPanelState extends State<_FinanceAiChatPanel> with AutomaticKeepAliveClientMixin {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  final List<_AiMsg> _messages = [];
  bool _loading = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    financeAiClearNotifier.addListener(_clearChat);
    // Carregar histórico da sessão se existir
    final historyKey = "${widget.userId}_${widget.workspaceId}_${widget.mode}";
    if (_sessionChatHistory.containsKey(historyKey)) {
      final history = _sessionChatHistory[historyKey]!;
      _messages.addAll(history.map((m) => _AiMsg(
            role: m['role'] == 'user' ? _AiRole.user : _AiRole.assistant,
            content: m['content'] as String,
            createdAt: DateTime.parse(m['createdAt'] as String),
          )));
    }
  }

  void _clearChat() {
    if (!mounted) return;
    setState(() {
      _messages.clear();
    });
    final historyKey = "${widget.userId}_${widget.workspaceId}_${widget.mode}";
    _sessionChatHistory.remove(historyKey);
  }

  void _saveToSessionHistory() {
    final historyKey = "${widget.userId}_${widget.workspaceId}_${widget.mode}";
    _sessionChatHistory[historyKey] = _messages
        .map((m) => {
              'role': m.role == _AiRole.user ? 'user' : 'assistant',
              'content': m.content,
              'createdAt': m.createdAt.toIso8601String(),
            })
        .toList();
  }

  @override
  void dispose() {
    financeAiClearNotifier.removeListener(_clearChat);
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send(String text) async {
    final msg = text.trim();
    if (msg.isEmpty) return;
    if (_loading) return;

    if (widget.workspaceId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Selecione um workspace antes de usar a IA.'),
            backgroundColor: Color(0xFFEF4444),
          ),
        );
      }
      return;
    }

    setState(() {
        _loading = true;
        _messages.add(
          _AiMsg(
            role: _AiRole.user,
            content: msg,
            createdAt: DateTime.now(),
          ),
        );
        _controller.clear();
      });
      _saveToSessionHistory();

    await _scrollToBottom();

    try {
      final uri = Uri.parse('$apiBaseUrl/gerenciamento-financeiro/api/finance-ai');
      final payload = {
        'user_id': widget.userId,
        'workspace_id': widget.workspaceId,
        'mode': widget.mode,
        'message': msg,
        'context': {
          'app': 'finance_app',
        },
      };

      final resp = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 20));

      Map<String, dynamic>? data;
      try {
        data = jsonDecode(resp.body) as Map<String, dynamic>;
      } catch (_) {
        data = null;
      }

      if (resp.statusCode != 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(data?['message']?.toString() ?? 'Falha ao consultar IA (HTTP ${resp.statusCode}).'),
              backgroundColor: const Color(0xFFEF4444),
            ),
          );
        }
        return;
      }

      if (data == null || data['success'] != true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(data?['message']?.toString() ?? 'Falha ao consultar IA.'),
              backgroundColor: const Color(0xFFEF4444),
            ),
          );
        }
        return;
      }

      final answer = data['answer']?.toString().trim();
      if (answer == null || answer.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('IA retornou resposta vazia.'),
              backgroundColor: Color(0xFFEF4444),
            ),
          );
        }
        return;
      }

      setState(() {
        _messages.add(
          _AiMsg(
            role: _AiRole.assistant,
            content: answer,
            createdAt: DateTime.now(),
          ),
        );
      });
      _saveToSessionHistory();

      await _scrollToBottom();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Erro ao conectar na IA.'),
            backgroundColor: Color(0xFFEF4444),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _scrollToBottom() async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Container(
      color: const Color(0xFF0F2027),
      child: Column(
        children: [
          Expanded(
            child: _messages.isEmpty ? _buildEmptyState(context) : _buildMessages(context),
          ),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1E3C72).withOpacity(0.3),
              border: Border(
                top: BorderSide(color: Colors.white.withOpacity(0.08)),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    minLines: 1,
                    maxLines: 4,
                    style: const TextStyle(color: Colors.white),
                    textInputAction: TextInputAction.send,
                    onSubmitted: (v) => _send(v),
                    decoration: InputDecoration(
                      hintText: 'Digite sua pergunta…',
                      hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.05),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  height: 44,
                  width: 44,
                  child: ElevatedButton(
                    onPressed: _loading ? null : () => _send(_controller.text),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00C9A7),
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _loading
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.send),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          widget.emptyStateTitle,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          widget.emptyStateSubtitle,
          style: TextStyle(color: Colors.white.withOpacity(0.65)),
        ),

      ],
    );
  }

  Widget _buildMessages(BuildContext context) {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final m = _messages[index];
        final isUser = m.role == _AiRole.user;
        return Align(
          alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 560),
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isUser ? const Color(0xFF00C9A7) : Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              m.content,
              style: TextStyle(
                color: Colors.white,
                height: 1.25,
              ),
            ),
          ),
        );
      },
    );
  }
}
