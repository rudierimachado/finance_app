import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'add_transaction.dart';
import 'attachments_page.dart';
import 'config.dart';

class TransactionsPage extends StatefulWidget {
  final int userId;
  final int? workspaceId;

  const TransactionsPage({
    super.key,
    required this.userId,
    this.workspaceId,
  });

  @override
  State<TransactionsPage> createState() => _TransactionsPageState();
}

class _TransactionsPageState extends State<TransactionsPage> {
  late int _year;
  late int _month;
  String _typeFilter = 'all';
  final _queryController = TextEditingController();

  late final VoidCallback _refreshListener;

  late Future<List<_TxItem>> _future;
  List<_TxItem> _currentItems = <_TxItem>[];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _year = now.year;
    _month = now.month;
    _future = _fetch();

    _refreshListener = () {
      if (mounted) {
        setState(() {
          _currentItems = <_TxItem>[];
          _future = _fetch();
        });
      }
    };
    financeRefreshTick.addListener(_refreshListener);
  }

  @override
  void didUpdateWidget(covariant TransactionsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workspaceId != widget.workspaceId) {
      if (mounted) {
        setState(() {
          _currentItems = <_TxItem>[];
          _future = _fetch();
        });
      }
    }
  }

  @override
  void dispose() {
    financeRefreshTick.removeListener(_refreshListener);
    _queryController.dispose();
    super.dispose();
  }

  void _prevMonth() {
    setState(() {
      if (_month == 1) {
        _month = 12;
        _year -= 1;
      } else {
        _month -= 1;
      }
      _currentItems = []; // Limpar para forçar reload
      _future = _fetch();
    });
  }

  void _nextMonth() {
    setState(() {
      if (_month == 12) {
        _month = 1;
        _year += 1;
      } else {
        _month += 1;
      }
      _currentItems = []; // Limpar para forçar reload
      _future = _fetch();
    });
  }

  Future<List<_TxItem>> _fetch() async {
    final q = _queryController.text.trim();
    final type = _typeFilter == 'all' ? null : _typeFilter;

    final params = <String, String>{
      'user_id': widget.userId.toString(),
      'year': _year.toString(),
      'month': _month.toString(),
      if (widget.workspaceId != null) 'workspace_id': widget.workspaceId.toString(),
    };
    if (type != null) params['type'] = type;
    if (q.isNotEmpty) params['q'] = q;

    final uri = Uri.parse('$apiBaseUrl/gerenciamento-financeiro/api/transactions').replace(queryParameters: params);

    final resp = await http.get(uri, headers: {'Content-Type': 'application/json'});
    final data = jsonDecode(resp.body) as Map<String, dynamic>;

    if (resp.statusCode != 200 || data['success'] != true) {
      throw Exception(data['message']?.toString() ?? 'Falha ao carregar transações.');
    }

    final raw = (data['transactions'] as List<dynamic>? ?? const <dynamic>[]);
    final items = <_TxItem>[];
    for (final e in raw) {
      if (e is! Map) continue;
      final rawId = e['id'];
      int id = 0;
      if (rawId is num) {
        id = rawId.toInt();
      } else if (rawId is String) {
        id = int.tryParse(rawId) ?? 0;
      }
      if (id <= 0) continue;
      final desc = e['description']?.toString() ?? '';
      final amount = (e['amount'] as num? ?? 0).toDouble();
      final rawType = e['type']?.toString().trim().toLowerCase();
      final typeStr = switch (rawType) {
        'expense' || 'despesa' || 'saida' => 'expense',
        'income' || 'receita' || 'entrada' => 'income',
        _ => (rawType == null || rawType.isEmpty) ? 'expense' : rawType,
      };
      final isRecurring = e['is_recurring'] == true;
      final isPaid = e['is_paid'] == true;
      final dateStr = e['date']?.toString();
      DateTime? date;
      if (dateStr != null && dateStr.isNotEmpty) {
        date = DateTime.tryParse(dateStr);
      }
      final cat = e['category'] is Map ? (e['category'] as Map) : null;
      final catName = cat?['name']?.toString();
      final catColor = _parseHexColor(cat?['color']?.toString());
      items.add(_TxItem(
        id: id,
        description: desc,
        amount: amount,
        type: typeStr,
        isRecurring: isRecurring,
        isPaid: isPaid,
        date: date,
        categoryName: catName,
        categoryColor: catColor,
      ));
    }

    return items;
  }

  Future<void> _editTransaction(int transactionId) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AddTransactionPage(
          userId: widget.userId,
          transactionId: transactionId,
          workspaceId: widget.workspaceId,
        ),
      ),
    );

    if (changed == true && mounted) {
      financeRefreshTick.value = financeRefreshTick.value + 1;
    }
  }

  void _viewAttachments(int transactionId, String description) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AttachmentsPage(
          userId: widget.userId,
          transactionId: transactionId,
          transactionDescription: description,
        ),
      ),
    );
  }

  Future<void> _setPaid(int transactionId, bool newStatus) async {
    if (transactionId <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erro: transação inválida'), backgroundColor: Colors.red),
      );
      return;
    }

    // Update otimista: atualizar UI imediatamente
    final itemIndex = _currentItems.indexWhere((item) => item.id == transactionId);
    if (itemIndex != -1) {
      setState(() {
        _currentItems[itemIndex] = _TxItem(
          id: _currentItems[itemIndex].id,
          description: _currentItems[itemIndex].description,
          amount: _currentItems[itemIndex].amount,
          type: _currentItems[itemIndex].type,
          date: _currentItems[itemIndex].date,
          categoryName: _currentItems[itemIndex].categoryName,
          categoryColor: _currentItems[itemIndex].categoryColor,
          isRecurring: _currentItems[itemIndex].isRecurring,
          isPaid: newStatus,
        );
      });
    }

    // Chamar backend em background
    try {
      bool isRouteMismatch(http.Response r) {
        final bodyLower = r.body.toLowerCase();
        return bodyLower.contains('<!doctype html>') ||
            bodyLower.contains('endpoint não encontrado') ||
            bodyLower.contains('endpoint nao encontrado');
      }

      Uri buildPutUri(String prefix) => Uri.parse(
        '$apiBaseUrl$prefix/api/transactions/$transactionId',
      );

      Future<http.Response> doPut(Uri uri) {
        return http
            .put(
              uri,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'user_id': widget.userId,
                'is_paid': newStatus,
                'action': 'set_paid',
              }),
            )
            .timeout(const Duration(seconds: 10));
      }

      var uri = buildPutUri('/gerenciamento-financeiro');
      var response = await doPut(uri);

      if ((response.statusCode == 404 || response.statusCode == 405) && isRouteMismatch(response)) {
        uri = buildPutUri('');
        response = await doPut(uri);
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200 && data['success'] == true) {
        // Notificar dashboard para atualizar totais
        financeRefreshTick.value = financeRefreshTick.value + 1;
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(newStatus ? 'Marcada como paga' : 'Marcada como não paga'),
              backgroundColor: const Color(0xFF00C9A7),
              duration: const Duration(seconds: 1),
            ),
          );
        }
      } else {
        throw Exception(data['message'] ?? 'Erro ao atualizar status');
      }
    } catch (e) {
      // Se falhou, reverter o update otimista
      if (itemIndex != -1 && mounted) {
        setState(() {
          _currentItems[itemIndex] = _TxItem(
            id: _currentItems[itemIndex].id,
            description: _currentItems[itemIndex].description,
            amount: _currentItems[itemIndex].amount,
            type: _currentItems[itemIndex].type,
            date: _currentItems[itemIndex].date,
            categoryName: _currentItems[itemIndex].categoryName,
            categoryColor: _currentItems[itemIndex].categoryColor,
            isRecurring: _currentItems[itemIndex].isRecurring,
            isPaid: !newStatus,
          );
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _deleteTransaction(int transactionId) async {
    String? scope;
    final tx = _currentItems.where((e) => e.id == transactionId).cast<_TxItem?>().firstWhere(
          (e) => e != null,
          orElse: () => null,
        );
    if (tx != null && tx.isRecurring) {
      scope = await showDialog<String>(
        context: context,
        builder: (context) {
          return AlertDialog(
            backgroundColor: const Color(0xFF0F2027),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(color: Colors.white.withOpacity(0.10)),
            ),
            title: const Text(
              'Excluir recorrência',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
            ),
            content: Text(
              'Essa transação é recorrente. Deseja excluir apenas esta ou todas?',
              style: TextStyle(color: Colors.white.withOpacity(0.75)),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop('single'),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF00C9A7),
                ),
                child: const Text('Só esta'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop('all'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFEF4444),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Todas'),
              ),
            ],
          );
        },
      );
      if (scope == null) return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Excluir transação'),
          content: const Text('Tem certeza que deseja excluir esta transação?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Excluir'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      http.Response resp;
      if (kIsWeb) {
        Uri buildRemoveUri(String prefix) => Uri.parse(
          '$apiBaseUrl$prefix/api/transactions/$transactionId/remove?user_id=${widget.userId}${scope != null ? '&scope=$scope' : ''}',
        );

        var uri = buildRemoveUri('/gerenciamento-financeiro');
        resp = await http.get(uri).timeout(const Duration(seconds: 10));

        if (resp.statusCode == 404 && resp.body.toLowerCase().contains('<!doctype html>')) {
          uri = buildRemoveUri('');
          resp = await http.get(uri).timeout(const Duration(seconds: 10));
        }
      } else {
        bool isRouteMismatch(http.Response r) {
          final bodyLower = r.body.toLowerCase();
          return bodyLower.contains('<!doctype html>') ||
              bodyLower.contains('endpoint não encontrado') ||
              bodyLower.contains('endpoint nao encontrado');
        }

        Uri buildDeleteUri(String prefix) => Uri.parse(
          '$apiBaseUrl$prefix/api/transactions/$transactionId?user_id=${widget.userId}${scope != null ? '&scope=$scope' : ''}',
        );
        Uri buildRemoveUri(String prefix) => Uri.parse(
          '$apiBaseUrl$prefix/api/transactions/$transactionId/remove?user_id=${widget.userId}${scope != null ? '&scope=$scope' : ''}',
        );

        var deleteUri = buildDeleteUri('/gerenciamento-financeiro');

        resp = await http
            .delete(
              deleteUri,
              headers: {'Content-Type': 'application/json'},
            )
            .timeout(const Duration(seconds: 10));

        if (resp.statusCode == 404 || resp.statusCode == 405) {
          final fallbackUri = buildRemoveUri('/gerenciamento-financeiro');
          resp = await http
              .get(
                fallbackUri,
                headers: {'Content-Type': 'application/json'},
              )
              .timeout(const Duration(seconds: 10));
        }

        if (resp.statusCode == 404 && isRouteMismatch(resp)) {
          deleteUri = buildDeleteUri('');
          resp = await http
              .delete(
                deleteUri,
                headers: {'Content-Type': 'application/json'},
              )
              .timeout(const Duration(seconds: 10));

          if (resp.statusCode == 404 || resp.statusCode == 405) {
            final fallbackUri = buildRemoveUri('');
            resp = await http
                .get(
                  fallbackUri,
                  headers: {'Content-Type': 'application/json'},
                )
                .timeout(const Duration(seconds: 10));
          }
        }
      }

      Map<String, dynamic> data;
      try {
        data = jsonDecode(resp.body) as Map<String, dynamic>;
      } catch (_) {
        final preview = resp.body.length > 180 ? resp.body.substring(0, 180) : resp.body;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Falha ao excluir (HTTP ${resp.statusCode}): $preview')),
          );
        }
        return;
      }

      if (resp.statusCode == 200 && data['success'] == true) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Transação excluída com sucesso!'),
            backgroundColor: Color(0xFFEF4444),
          ),
        );
        setState(() {
          _currentItems = <_TxItem>[];
          _future = _fetch();
        });
        financeRefreshTick.value = financeRefreshTick.value + 1;
        return;
      }

      final msg = data['message']?.toString() ?? 'Erro ao excluir transação.';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Falha ao excluir: ${e.toString()}')),
        );
      }
    }
  }

  void _applyFilters() {
    setState(() {
      _currentItems = []; // Limpar para forçar reload
      _future = _fetch();
    });
  }

  @override
  Widget build(BuildContext context) {
    // Evitar requisições sem workspace_id enquanto o HomeShell ainda está resolvendo
    // o workspace ativo. Isso impede misturar dados entre workspaces.
    if (widget.workspaceId == null) {
      return Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF0F2027),
                Color(0xFF203A43),
                Color(0xFF2C5364),
              ],
            ),
          ),
          child: const Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00C9A7)),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transações', style: TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      extendBodyBehindAppBar: true,
      floatingActionButton: FloatingActionButton(
        heroTag: 'transactions_fab',
        onPressed: () async {
          final changed = await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (_) => AddTransactionPage(
                userId: widget.userId,
                workspaceId: widget.workspaceId,
              ),
            ),
          );
          if (changed == true && mounted) {
            setState(() {
              _currentItems = [];
              _future = _fetch();
            });
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
            colors: [
              Color(0xFF0F2027),
              Color(0xFF203A43),
              Color(0xFF2C5364),
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            child: Column(
              children: [
                _FiltersBar(
                  year: _year,
                  month: _month,
                  typeFilter: _typeFilter,
                  queryController: _queryController,
                  onPrevMonth: _prevMonth,
                  onNextMonth: _nextMonth,
                  onTypeChanged: (v) {
                    setState(() {
                      _typeFilter = v;
                      _future = _fetch();
                    });
                  },
                  onApply: _applyFilters,
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: FutureBuilder<List<_TxItem>>(
                    future: _future,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00C9A7)),
                          ),
                        );
                      }

                      if (snapshot.hasError) {
                        return Center(
                          child: Text(
                            snapshot.error.toString().replaceFirst('Exception: ', ''),
                            style: TextStyle(color: Colors.white.withOpacity(0.8)),
                            textAlign: TextAlign.center,
                          ),
                        );
                      }

                      final items = snapshot.data ?? <_TxItem>[];
                      
                      // Sincronizar _currentItems com items do snapshot quando completa
                      if (snapshot.connectionState == ConnectionState.done && items.isNotEmpty) {
                        // Só atualizar se _currentItems está vazio (primeiro load ou após mudança de mês)
                        if (_currentItems.isEmpty) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) {
                              setState(() {
                                _currentItems = List.from(items);
                              });
                            }
                          });
                        }
                      }
                      
                      // Renderizar _currentItems se disponível, senão items do snapshot
                      final displayItems = _currentItems.isNotEmpty ? _currentItems : items;
                      
                      if (displayItems.isEmpty) {
                        return Center(
                          child: Text(
                            'Nenhuma transação neste mês.',
                            style: TextStyle(color: Colors.white.withOpacity(0.75)),
                          ),
                        );
                      }

                      return ListView.separated(
                        itemCount: displayItems.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final item = displayItems[index];
                          return _TxRow(
                            item: item,
                            onEdit: () => _editTransaction(item.id),
                            onDelete: () => _deleteTransaction(item.id),
                            onViewAttachments: () => _viewAttachments(item.id, item.description),
                            onTogglePaid: (v) => _setPaid(item.id, v),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FiltersBar extends StatelessWidget {
  final int year;
  final int month;
  final String typeFilter;
  final TextEditingController queryController;
  final VoidCallback onPrevMonth;
  final VoidCallback onNextMonth;
  final ValueChanged<String> onTypeChanged;
  final VoidCallback onApply;

  const _FiltersBar({
    required this.year,
    required this.month,
    required this.typeFilter,
    required this.queryController,
    required this.onPrevMonth,
    required this.onNextMonth,
    required this.onTypeChanged,
    required this.onApply,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 420;

        final dropdown = DropdownButtonFormField<String>(
          value: typeFilter,
          items: const [
            DropdownMenuItem(value: 'all', child: Text('Tudo')),
            DropdownMenuItem(value: 'income', child: Text('Receitas')),
            DropdownMenuItem(value: 'expense', child: Text('Despesas')),
          ],
          onChanged: (v) {
            if (v == null) return;
            onTypeChanged(v);
          },
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white.withOpacity(0.06),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.10)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.10)),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          dropdownColor: const Color(0xFF203A43),
          style: const TextStyle(color: Colors.white),
        );

        final search = TextField(
          controller: queryController,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Buscar',
            hintStyle: TextStyle(color: Colors.white.withOpacity(0.45)),
            filled: true,
            fillColor: Colors.white.withOpacity(0.06),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.10)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.10)),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          onSubmitted: (_) => onApply(),
        );

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withOpacity(0.10)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: onPrevMonth,
                    icon: const Icon(Icons.chevron_left, color: Colors.white),
                  ),
                  Expanded(
                    child: Text(
                      '${month.toString().padLeft(2, '0')}/$year',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                    ),
                  ),
                  IconButton(
                    onPressed: onNextMonth,
                    icon: const Icon(Icons.chevron_right, color: Colors.white),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (compact) ...[
                dropdown,
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: search),
                    const SizedBox(width: 10),
                    IconButton(
                      onPressed: onApply,
                      icon: const Icon(Icons.search, color: Color(0xFF00C9A7)),
                    ),
                  ],
                ),
              ] else ...[
                Row(
                  children: [
                    Expanded(child: dropdown),
                    const SizedBox(width: 10),
                    Expanded(child: search),
                    const SizedBox(width: 10),
                    IconButton(
                      onPressed: onApply,
                      icon: const Icon(Icons.search, color: Color(0xFF00C9A7)),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _TxItem {
  final int id;
  final String description;
  final double amount;
  final String type;
  final bool isRecurring;
  final bool isPaid;
  final DateTime? date;
  final String? categoryName;
  final Color? categoryColor;

  _TxItem({
    required this.id,
    required this.description,
    required this.amount,
    required this.type,
    required this.isRecurring,
    required this.isPaid,
    required this.date,
    required this.categoryName,
    required this.categoryColor,
  });
}

class _TxRow extends StatelessWidget {
  final _TxItem item;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onViewAttachments;
  final ValueChanged<bool> onTogglePaid;

  const _TxRow({
    required this.item,
    required this.onEdit,
    required this.onDelete,
    required this.onViewAttachments,
    required this.onTogglePaid,
  });

  @override
  Widget build(BuildContext context) {
    final isIncome = item.type == 'income';
    final amountColor = isIncome ? const Color(0xFF10B981) : const Color(0xFFEF4444);
    final sign = isIncome ? '+' : '-';
    final dateLabel = item.date != null
        ? '${item.date!.day.toString().padLeft(2, '0')}/${item.date!.month.toString().padLeft(2, '0')}'
        : '';
    final catColor = item.categoryColor ?? Colors.white.withOpacity(0.25);
    final catName = item.categoryName ?? '';
    final isExpense = item.type == 'expense';

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 420;

        Widget wrapTile(Widget child) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.04),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: child,
            ),
          );
        }

        Widget buildPaidChip() {
          final paid = item.isPaid;
          final fg = paid ? const Color(0xFF10B981) : const Color(0xFFFBBF24);
          final bg = fg.withOpacity(0.16);
          return InkWell(
            onTap: () => onTogglePaid(!paid),
            borderRadius: BorderRadius.circular(999),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: fg.withOpacity(0.35)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(paid ? Icons.check_circle : Icons.schedule, color: fg, size: 14),
                  const SizedBox(width: 6),
                  Text(
                    paid ? 'Pago' : 'Pendente',
                    style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          );
        }

        Widget buildMenu() {
          return PopupMenuButton<int>(
            icon: Icon(Icons.more_vert, color: Colors.white.withOpacity(0.85), size: 18),
            color: const Color(0xFF203A43),
            onSelected: (v) {
              if (v == 0) onViewAttachments();
              if (v == 1) onEdit();
              if (v == 2) onDelete();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 0, child: Text('Comprovantes', style: TextStyle(color: Colors.white))),
              PopupMenuItem(value: 1, child: Text('Editar', style: TextStyle(color: Colors.white))),
              PopupMenuItem(value: 2, child: Text('Excluir', style: TextStyle(color: Colors.white))),
            ],
          );
        }

        if (compact) {
          return wrapTile(
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              leading: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: catColor.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: catColor.withOpacity(0.35)),
                ),
                child: Icon(
                  isIncome ? Icons.arrow_downward : Icons.arrow_upward,
                  color: catColor,
                  size: 18,
                ),
              ),
              title: Text(
                item.description,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                [
                  if (catName.isNotEmpty) catName,
                  if (dateLabel.isNotEmpty) dateLabel,
                ].join(' • '),
                style: TextStyle(color: Colors.white.withOpacity(0.62), fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$sign R\$ ${item.amount.toStringAsFixed(2)}',
                    style: TextStyle(color: amountColor, fontWeight: FontWeight.w900, fontSize: 14),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isExpense) buildPaidChip(),
                      if (isExpense) const SizedBox(width: 6),
                      buildMenu(),
                    ],
                  ),
                ],
              ),
            ),
          );
        }

        return wrapTile(
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            leading: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: catColor.withOpacity(0.18),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: catColor.withOpacity(0.35)),
              ),
              child: Icon(
                isIncome ? Icons.arrow_downward : Icons.arrow_upward,
                color: catColor,
                size: 18,
              ),
            ),
            title: Text(
              item.description,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              [
                if (catName.isNotEmpty) catName,
                if (dateLabel.isNotEmpty) dateLabel,
              ].join(' • '),
              style: TextStyle(color: Colors.white.withOpacity(0.62), fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isExpense) ...[
                  Transform.scale(
                    scale: 0.80,
                    child: Switch(
                      value: item.isPaid,
                      onChanged: onTogglePaid,
                      activeColor: const Color(0xFF00C9A7),
                      activeTrackColor: const Color(0xFF00C9A7).withOpacity(0.3),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '$sign R\$ ${item.amount.toStringAsFixed(2)}',
                      style: TextStyle(color: amountColor, fontWeight: FontWeight.w900, fontSize: 14),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (isExpense) ...[
                      const SizedBox(height: 2),
                      Text(
                        item.isPaid ? 'Pago' : 'Pendente',
                        style: TextStyle(
                          color: item.isPaid ? const Color(0xFF10B981) : const Color(0xFFFBBF24),
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(width: 6),
                IconButton(
                  onPressed: onViewAttachments,
                  icon: Icon(Icons.attach_file, color: Colors.white.withOpacity(0.8), size: 16),
                  tooltip: 'Comprovantes',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
                IconButton(
                  onPressed: onEdit,
                  icon: Icon(Icons.edit, color: Colors.white.withOpacity(0.8), size: 16),
                  tooltip: 'Editar',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
                IconButton(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline, color: Color(0xFFEF4444), size: 16),
                  tooltip: 'Excluir',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

Color? _parseHexColor(String? hex) {
  if (hex == null) return null;
  var cleaned = hex.replaceAll('#', '').trim();
  if (cleaned.length == 6) cleaned = 'FF$cleaned';
  if (cleaned.length != 8) return null;
  final value = int.tryParse(cleaned, radix: 16);
  if (value == null) return null;
  return Color(value);
}
