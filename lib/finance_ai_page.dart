import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'config.dart';

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
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          Container(
            color: const Color(0xFF0F2027),
            child: const TabBar(
              labelColor: Color(0xFF00C9A7),
              unselectedLabelColor: Colors.white70,
              indicatorColor: Color(0xFF00C9A7),
              tabs: [
                Tab(text: 'Cartões'),
                Tab(text: 'Empréstimos'),
                Tab(text: 'Calculadoras'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _FinanceAiChatPanel(
                  userId: userId,
                  workspaceId: workspaceId,
                  mode: 'credit_cards',
                  emptyStateTitle: 'Acompanhamento de cartões de crédito',
                  emptyStateSubtitle: 'Pergunte sobre limites, fatura, juros do rotativo, melhor dia de compra e como organizar seus cartões.',
                  suggestionChips: [
                    'Como organizar meu limite e fatura?',
                    'Qual o melhor dia de compra?',
                    'Rotativo: como sair?',
                  ],
                ),
                _FinanceAiChatPanel(
                  userId: userId,
                  workspaceId: workspaceId,
                  mode: 'loans',
                  emptyStateTitle: 'Gestão de empréstimos e financiamentos',
                  emptyStateSubtitle: 'Pergunte sobre amortização, taxa de juros, antecipação de parcelas e comparação de cenários.',
                  suggestionChips: [
                    'Vale antecipar parcelas?',
                    'Como comparar duas propostas?',
                    'Como reduzir juros?',
                  ],
                ),
                _FinanceAiChatPanel(
                  userId: userId,
                  workspaceId: workspaceId,
                  mode: 'calculators',
                  emptyStateTitle: 'Calculadoras financeiras',
                  emptyStateSubtitle: 'Peça cálculos de juros, parcelamento, inflação, valor futuro e simulações simples.',
                  suggestionChips: [
                    'Simular juros compostos',
                    'Calcular parcela e CET',
                    'Corrigir pela inflação',
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
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

class _FinanceAiChatPanel extends StatefulWidget {
  final int userId;
  final int? workspaceId;
  final String mode;
  final String emptyStateTitle;
  final String emptyStateSubtitle;
  final List<String> suggestionChips;

  const _FinanceAiChatPanel({
    required this.userId,
    required this.workspaceId,
    required this.mode,
    required this.emptyStateTitle,
    required this.emptyStateSubtitle,
    required this.suggestionChips,
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
  void dispose() {
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

    return Column(
      children: [
        Expanded(
          child: _messages.isEmpty ? _buildEmptyState(context) : _buildMessages(context),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(
              top: BorderSide(color: Colors.black.withOpacity(0.06)),
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
                  textInputAction: TextInputAction.send,
                  onSubmitted: (v) => _send(v),
                  decoration: InputDecoration(
                    hintText: 'Digite sua pergunta…',
                    filled: true,
                    fillColor: const Color(0xFFF3F4F6),
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
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          widget.emptyStateTitle,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          widget.emptyStateSubtitle,
          style: TextStyle(color: Colors.black.withOpacity(0.65)),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: widget.suggestionChips
              .map(
                (t) => ActionChip(
                  label: Text(t),
                  onPressed: () => _send(t),
                ),
              )
              .toList(),
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
              color: isUser ? const Color(0xFF00C9A7) : const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              m.content,
              style: TextStyle(
                color: isUser ? Colors.white : Colors.black87,
                height: 1.25,
              ),
            ),
          ),
        );
      },
    );
  }
}
