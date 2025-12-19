import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'add_transaction.dart';

const String apiBaseUrl = kDebugMode
    ? (String.fromEnvironment('API_BASE_URL', defaultValue: 'http://localhost:5000'))
    : (String.fromEnvironment('API_BASE_URL', defaultValue: 'https://nexusrdr.com.br'));

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
  List<_TxItem> _lastLoadedItems = <_TxItem>[];

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
      final typeStr = e['type']?.toString() ?? 'expense';
      final isRecurring = e['is_recurring'] == true;
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
        date: date,
        categoryName: catName,
        categoryColor: catColor,
      ));
    }

    _lastLoadedItems = items;
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

  Future<void> _deleteTransaction(int transactionId) async {
    String? scope;
    final tx = _lastLoadedItems.where((e) => e.id == transactionId).cast<_TxItem?>().firstWhere(
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
        print('[DELETE_TX] Tentando: $uri');
        resp = await http.get(uri).timeout(const Duration(seconds: 10));
        print('[DELETE_TX] Status: ${resp.statusCode}, Body preview: ${resp.body.substring(0, resp.body.length > 100 ? 100 : resp.body.length)}');

        if (resp.statusCode == 404 && resp.body.toLowerCase().contains('<!doctype html>')) {
          uri = buildRemoveUri('');
          print('[DELETE_TX] Fallback sem prefixo: $uri');
          resp = await http.get(uri).timeout(const Duration(seconds: 10));
          print('[DELETE_TX] Status: ${resp.statusCode}, Body preview: ${resp.body.substring(0, resp.body.length > 100 ? 100 : resp.body.length)}');
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

        print('[DELETE_TX][MOBILE] DELETE: $deleteUri');

        resp = await http
            .delete(
              deleteUri,
              headers: {'Content-Type': 'application/json'},
            )
            .timeout(const Duration(seconds: 10));

        print(
          '[DELETE_TX][MOBILE] Status: ${resp.statusCode}, Body preview: ${resp.body.substring(0, resp.body.length > 180 ? 180 : resp.body.length)}',
        );

        if (resp.statusCode == 404 || resp.statusCode == 405) {
          final fallbackUri = buildRemoveUri('/gerenciamento-financeiro');

          print('[DELETE_TX][MOBILE] Fallback GET remove: $fallbackUri');
          resp = await http
              .get(
                fallbackUri,
                headers: {'Content-Type': 'application/json'},
              )
              .timeout(const Duration(seconds: 10));

          print(
            '[DELETE_TX][MOBILE] Status: ${resp.statusCode}, Body preview: ${resp.body.substring(0, resp.body.length > 180 ? 180 : resp.body.length)}',
          );
        }

        if (resp.statusCode == 404 && isRouteMismatch(resp)) {
          deleteUri = buildDeleteUri('');

          print('[DELETE_TX][MOBILE] Fallback sem prefixo (DELETE): $deleteUri');
          resp = await http
              .delete(
                deleteUri,
                headers: {'Content-Type': 'application/json'},
              )
              .timeout(const Duration(seconds: 10));

          print(
            '[DELETE_TX][MOBILE] Status: ${resp.statusCode}, Body preview: ${resp.body.substring(0, resp.body.length > 180 ? 180 : resp.body.length)}',
          );

          if (resp.statusCode == 404 || resp.statusCode == 405) {
            final fallbackUri = buildRemoveUri('');

            print('[DELETE_TX][MOBILE] Fallback sem prefixo (GET remove): $fallbackUri');
            resp = await http
                .get(
                  fallbackUri,
                  headers: {'Content-Type': 'application/json'},
                )
                .timeout(const Duration(seconds: 10));

            print(
              '[DELETE_TX][MOBILE] Status: ${resp.statusCode}, Body preview: ${resp.body.substring(0, resp.body.length > 180 ? 180 : resp.body.length)}',
            );
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
                      if (items.isEmpty) {
                        return Center(
                          child: Text(
                            'Nenhuma transação neste mês.',
                            style: TextStyle(color: Colors.white.withOpacity(0.75)),
                          ),
                        );
                      }

                      return ListView.separated(
                        itemCount: items.length,
                        separatorBuilder: (_, __) => Divider(height: 1, color: Colors.white.withOpacity(0.08)),
                        itemBuilder: (context, index) {
                          final item = items[index];
                          return _TxRow(
                            item: item,
                            onEdit: () => _editTransaction(item.id),
                            onDelete: () => _deleteTransaction(item.id),
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
  final DateTime? date;
  final String? categoryName;
  final Color? categoryColor;

  _TxItem({
    required this.id,
    required this.description,
    required this.amount,
    required this.type,
    required this.isRecurring,
    required this.date,
    required this.categoryName,
    required this.categoryColor,
  });
}

class _TxRow extends StatelessWidget {
  final _TxItem item;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _TxRow({
    required this.item,
    required this.onEdit,
    required this.onDelete,
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
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$sign R\$ ${item.amount.toStringAsFixed(2)}',
            style: TextStyle(color: amountColor, fontWeight: FontWeight.w800),
          ),
          const SizedBox(width: 10),
          IconButton(
            onPressed: onEdit,
            icon: Icon(Icons.edit, color: Colors.white.withOpacity(0.8), size: 18),
          ),
          IconButton(
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline, color: Color(0xFFEF4444), size: 18),
          ),
        ],
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
