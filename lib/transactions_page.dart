import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'add_transaction.dart';
import 'attachments_page.dart';
import 'config.dart';

class TransactionsPage extends StatefulWidget {
  final int userId;

  const TransactionsPage({
    super.key,
    required this.userId,
  });

  @override
  State<TransactionsPage> createState() => _TransactionsPageState();
}

class _TransactionsPageState extends State<TransactionsPage> {
  late int _year;
  late int _month;
  String _typeFilter = 'all';
  final _queryController = TextEditingController();

  late Future<List<_TxItem>> _future;
  List<_TxItem> _currentItems = <_TxItem>[];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _year = now.year;
    _month = now.month;
    _future = _fetch();
  }

  @override
  void dispose() {
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
      final id = (e['id'] as num?)?.toInt() ?? 0;
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
        ),
      ),
    );

    if (changed == true && mounted) {
      setState(() {
        _future = _fetch();
      });
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
      final uri = Uri.parse(
        '$apiBaseUrl/gerenciamento-financeiro/api/transactions/$transactionId',
      );

      final response = await http
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
          _future = _fetch();
        });
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transações', style: TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      extendBodyBehindAppBar: true,
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final changed = await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (_) => AddTransactionPage(userId: widget.userId),
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
                        separatorBuilder: (_, __) => Divider(height: 1, color: Colors.white.withOpacity(0.08)),
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
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
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
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
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
                ),
              ),
              const SizedBox(width: 10),
              IconButton(
                onPressed: onApply,
                icon: const Icon(Icons.search, color: Color(0xFF00C9A7)),
              ),
            ],
          ),
        ],
      ),
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

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        [
          if (catName.isNotEmpty) catName,
          if (dateLabel.isNotEmpty) dateLabel,
        ].join(' • '),
        style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: SizedBox(
        width: isExpense ? 240 : 180,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (isExpense) ...[
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Transform.scale(
                    scale: 0.75,
                    child: Switch(
                      value: item.isPaid,
                      onChanged: onTogglePaid,
                      activeColor: const Color(0xFF00C9A7),
                      activeTrackColor: const Color(0xFF00C9A7).withOpacity(0.3),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 4),
            ],
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$sign R\$ ${item.amount.toStringAsFixed(2)}',
                    style: TextStyle(color: amountColor, fontWeight: FontWeight.w800, fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (isExpense) ...[
                    const SizedBox(height: 2),
                    Text(
                      item.isPaid ? 'Pago' : 'Pendente',
                      style: TextStyle(
                        color: item.isPaid ? const Color(0xFF10B981) : const Color(0xFFFBBF24),
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 4),
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
