import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'add_transaction.dart';
import 'transactions_page.dart';

const String apiBaseUrl = kDebugMode
    ? (String.fromEnvironment('API_BASE_URL', defaultValue: 'http://localhost:5000'))
    : (String.fromEnvironment('API_BASE_URL', defaultValue: 'https://nexusrdr.com.br'));

class DashboardPage extends StatefulWidget {
  final int userId;
  final String email;

  const DashboardPage({
    super.key,
    required this.userId,
    required this.email,
  });

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  late Future<_DashboardData> _future;

  double? _currentBalance;
  double? _currentIncomePaid;
  double? _currentExpensePaid;

  void _syncLocalTotalsFromServer(_DashboardData data) {
    _currentIncomePaid = data.monthIncomePaid;
    _currentExpensePaid = data.monthExpensePaid;
    _currentBalance = data.balance;
  }

  void _applyOptimisticPaidChange(_TxItem tx, bool isPaid) {
    final incomePaid = _currentIncomePaid ?? 0;
    final expensePaid = _currentExpensePaid ?? 0;

    var nextIncomePaid = incomePaid;
    var nextExpensePaid = expensePaid;

    if (tx.type == 'income') {
      nextIncomePaid = isPaid ? (incomePaid + tx.amount) : (incomePaid - tx.amount);
    } else if (tx.type == 'expense') {
      nextExpensePaid = isPaid ? (expensePaid + tx.amount) : (expensePaid - tx.amount);
    }

    setState(() {
      _currentIncomePaid = nextIncomePaid < 0 ? 0 : nextIncomePaid;
      _currentExpensePaid = nextExpensePaid < 0 ? 0 : nextExpensePaid;
      _currentBalance = (_currentIncomePaid ?? 0) - (_currentExpensePaid ?? 0);
    });
  }

  late int _year;
  late int _month;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _year = now.year;
    _month = now.month;
    _future = _fetchDashboard();
  }

  Future<_DashboardData> _fetchDashboard() async {
    final uri = Uri.parse(
      '$apiBaseUrl/gerenciamento-financeiro/api/dashboard?user_id=${widget.userId}&year=$_year&month=$_month',
    );

    final response = await http.get(
      uri,
      headers: {
        'Content-Type': 'application/json',
      },
    );

    final Map<String, dynamic> data = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode == 200 && (data['success'] == true)) {
      final balance = (data['balance'] as num).toDouble();
      final monthIncome = (data['month_income'] as num? ?? 0).toDouble();
      final monthExpense = (data['month_expense'] as num? ?? 0).toDouble();
      final monthIncomePaid = (data['month_income_paid'] as num? ?? 0).toDouble();
      final monthExpensePaid = (data['month_expense_paid'] as num? ?? 0).toDouble();
      final month = (data['month'] as num? ?? 0).toInt();
      final year = (data['year'] as num? ?? 0).toInt();

      final rawList = (data['expense_by_category'] as List<dynamic>? ?? const <dynamic>[]);
      final categories = <_CategorySlice>[];
      for (final item in rawList) {
        if (item is! Map) continue;
        final name = (item['name']?.toString() ?? 'Categoria');
        final amount = (item['amount'] as num? ?? 0).toDouble();
        final colorStr = item['color']?.toString();
        categories.add(_CategorySlice(
          name: name,
          amount: amount,
          color: _parseHexColor(colorStr) ?? _fallbackColorFor(name),
        ));
      }

      return _DashboardData(
        balance: balance,
        monthIncome: monthIncome,
        monthExpense: monthExpense,
        monthIncomePaid: monthIncomePaid,
        monthExpensePaid: monthExpensePaid,
        month: month,
        year: year,
        expenseByCategory: categories,
        latestTransactions: _parseLatestTransactions(data['latest_transactions']),
      );
    }

    throw Exception(data['message']?.toString() ?? 'Falha ao carregar dashboard.');
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
          if (changed == true && mounted) {
            setState(() {
              _future = _fetchDashboard();
            });
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
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF00C9A7), Color(0xFF00B4D8)],
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.savings_outlined, color: Colors.white),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Dashboard',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            widget.email,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.75),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () {
                        setState(() {
                          _currentBalance = null;
                          _currentIncomePaid = null;
                          _currentExpensePaid = null;
                          _future = _fetchDashboard();
                        });
                      },
                      icon: const Icon(Icons.refresh, color: Colors.white),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                Expanded(
                  child: FutureBuilder<_DashboardData>(
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
                        return _ErrorState(
                          message: snapshot.error.toString().replaceFirst('Exception: ', ''),
                          onRetry: () {
                            setState(() {
                              _future = _fetchDashboard();
                            });
                          },
                        );
                      }

                      final data = snapshot.data!;
                      if (_currentBalance == null) {
                        _syncLocalTotalsFromServer(data);
                      }
                      final effectiveBalance = _currentBalance ?? data.balance;
                      return SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _BalanceCard(balance: effectiveBalance),
                            const SizedBox(height: 18),
                            _MonthSummaryCard(
                              monthIncome: data.monthIncome,
                              monthExpense: data.monthExpense,
                              month: data.month,
                              year: data.year,
                              onPrevMonth: _prevMonth,
                              onNextMonth: _nextMonth,
                            ),
                            const SizedBox(height: 18),
                            Text(
                              'Gastos por categoria (mês)',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.9),
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 10),
                            _PieSection(slices: data.expenseByCategory),
                            const SizedBox(height: 18),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Últimas transações (mês)',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.9),
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () async {
                                    final changed = await Navigator.of(context).push<bool>(
                                      MaterialPageRoute(
                                        builder: (_) => TransactionsPage(userId: widget.userId),
                                      ),
                                    );
                                    if (changed == true && mounted) {
                                      setState(() {
                                        _future = _fetchDashboard();
                                      });
                                    }
                                  },
                                  style: TextButton.styleFrom(
                                    foregroundColor: const Color(0xFF00C9A7),
                                  ),
                                  child: const Text('Ver todas'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            _LatestTransactionsSection(
                              items: data.latestTransactions,
                              onEdit: (txId) async {
                                print('[DASHBOARD] Editar transação ID: $txId');
                                if (txId <= 0) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('ID inválido para edição.')),
                                  );
                                  return;
                                }

                                final changed = await Navigator.of(context).push<bool>(
                                  MaterialPageRoute(
                                    builder: (_) => AddTransactionPage(
                                      userId: widget.userId,
                                      transactionId: txId,
                                    ),
                                  ),
                                );

                                if (changed == true && mounted) {
                                  setState(() {
                                    _future = _fetchDashboard();
                                  });
                                }
                              },
                              onDelete: (tx) async {
                                final txId = tx.id;
                                if (txId <= 0) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('ID inválido para exclusão.')),
                                  );
                                  return;
                                }
                                await _deleteTransaction(tx);
                              },
                              onTogglePaid: (tx, isPaid) {
                                // Atualização otimista: muda saldo instantaneamente
                                _applyOptimisticPaidChange(tx, isPaid);
                                _setTransactionPaid(tx, isPaid);
                              },
                            ),
                            const SizedBox(height: 10),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.06),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: Colors.white.withOpacity(0.10)),
                              ),
                              child: Text(
                                'Aqui entraremos com receitas, despesas, categorias e gráficos.',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.75),
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
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

  Future<void> _deleteTransaction(_TxItem tx) async {
    final txId = tx.id;

    String? scope;
    if (tx.isRecurring) {
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
          '$apiBaseUrl$prefix/api/transactions/$txId/remove?user_id=${widget.userId}${scope != null ? '&scope=$scope' : ''}',
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
          '$apiBaseUrl$prefix/api/transactions/$txId?user_id=${widget.userId}${scope != null ? '&scope=$scope' : ''}',
        );
        Uri buildRemoveUri(String prefix) => Uri.parse(
          '$apiBaseUrl$prefix/api/transactions/$txId/remove?user_id=${widget.userId}${scope != null ? '&scope=$scope' : ''}',
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
          _future = _fetchDashboard();
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

  Future<void> _setTransactionPaid(_TxItem tx, bool isPaid) async {
    // Atualização otimista: atualiza item localmente e recarrega saldo do card
    try {
      final uri = Uri.parse(
        '$apiBaseUrl/gerenciamento-financeiro/api/transactions/${tx.id}?user_id=${widget.userId}',
      );

      final resp = await http
          .put(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(<String, dynamic>{
              'user_id': widget.userId,
              'action': 'set_paid',
              'is_paid': isPaid,
            }),
          )
          .timeout(const Duration(seconds: 10));

      final Map<String, dynamic> data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (resp.statusCode == 200 && data['success'] == true) {
        // Sucesso: não recarrega o dashboard (UI já atualizou otimisticamente)
        return;
      }

      // Falha: reverter UI e mostrar erro
      final msg = data['message']?.toString() ?? 'Falha ao atualizar pagamento.';
      if (mounted) {
        setState(() {
          _future = _fetchDashboard(); // Recarrega para reverter
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      // Erro de conexão: reverter UI
      if (mounted) {
        setState(() {
          _future = _fetchDashboard(); // Recarrega para reverter
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Falha ao atualizar: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

class _DashboardData {
  final double balance;
  final double monthIncome;
  final double monthExpense;
  final double monthIncomePaid;
  final double monthExpensePaid;
  final int month;
  final int year;
  final List<_CategorySlice> expenseByCategory;
  final List<_TxItem> latestTransactions;

  _DashboardData({
    required this.balance,
    required this.monthIncome,
    required this.monthExpense,
    required this.monthIncomePaid,
    required this.monthExpensePaid,
    required this.month,
    required this.year,
    required this.expenseByCategory,
    required this.latestTransactions,
  });
}

List<_TxItem> _parseLatestTransactions(dynamic raw) {
  if (raw is! List) return <_TxItem>[];
  final items = <_TxItem>[];
  for (final e in raw) {
    if (e is! Map) continue;
    final id = (e['id'] as num?)?.toInt() ?? 0;
    final desc = e['description']?.toString() ?? '';
    final amount = (e['amount'] as num? ?? 0).toDouble();
    final type = e['type']?.toString() ?? 'expense';
    final isPaid = e['is_paid'] == true;
    final dateStr = e['date']?.toString();
    DateTime? date;
    if (dateStr != null && dateStr.isNotEmpty) {
      date = DateTime.tryParse(dateStr);
    }
    final cat = e['category'] is Map ? (e['category'] as Map) : null;
    final catName = cat?['name']?.toString();
    final catColor = _parseHexColor(cat?['color']?.toString());
    final isRecurring = e['is_recurring'] == true;
    items.add(_TxItem(
      id: id,
      description: desc,
      amount: amount,
      type: type,
      isPaid: isPaid,
      isRecurring: isRecurring,
      date: date,
      categoryName: catName,
      categoryColor: catColor,
    ));
  }
  return items;
}

class _TxItem {
  final int id;
  final String description;
  final double amount;
  final String type;
  final bool isPaid;
  final bool isRecurring;
  final DateTime? date;
  final String? categoryName;
  final Color? categoryColor;

  _TxItem({
    required this.id,
    required this.description,
    required this.amount,
    required this.type,
    required this.isPaid,
    required this.isRecurring,
    required this.date,
    required this.categoryName,
    required this.categoryColor,
  });
}

extension on _DashboardPageState {
  void _prevMonth() {
    setState(() {
      if (_month == 1) {
        _month = 12;
        _year -= 1;
      } else {
        _month -= 1;
      }
      _currentBalance = null;
      _currentIncomePaid = null;
      _currentExpensePaid = null;
      _future = _fetchDashboard();
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
      _currentBalance = null;
      _currentIncomePaid = null;
      _currentExpensePaid = null;
      _future = _fetchDashboard();
    });
  }
}

class _CategorySlice {
  final String name;
  final double amount;
  final Color color;

  _CategorySlice({
    required this.name,
    required this.amount,
    required this.color,
  });
}

Color? _parseHexColor(String? hex) {
  if (hex == null) return null;
  var value = hex.trim();
  if (value.isEmpty) return null;
  if (value.startsWith('#')) value = value.substring(1);
  if (value.length == 6) value = 'FF$value';
  if (value.length != 8) return null;
  final intColor = int.tryParse(value, radix: 16);
  if (intColor == null) return null;
  return Color(intColor);
}

Color _fallbackColorFor(String key) {
  const palette = <Color>[
    Color(0xFF00C9A7),
    Color(0xFF00B4D8),
    Color(0xFF3B82F6),
    Color(0xFFF59E0B),
    Color(0xFFEF4444),
    Color(0xFFA855F7),
    Color(0xFF10B981),
    Color(0xFF64748B),
  ];
  final hash = key.codeUnits.fold<int>(0, (p, c) => p + c);
  return palette[hash % palette.length];
}

class _MonthSummaryCard extends StatelessWidget {
  final double monthIncome;
  final double monthExpense;
  final int month;
  final int year;
  final VoidCallback onPrevMonth;
  final VoidCallback onNextMonth;

  const _MonthSummaryCard({
    required this.monthIncome,
    required this.monthExpense,
    required this.month,
    required this.year,
    required this.onPrevMonth,
    required this.onNextMonth,
  });

  @override
  Widget build(BuildContext context) {
    final monthLabel = (month >= 1 && month <= 12) ? '$month/$year' : 'Mês atual';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Receitas vs Gastos do mês',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                onPressed: onPrevMonth,
                icon: Icon(Icons.chevron_left, color: Colors.white.withOpacity(0.85)),
                constraints: const BoxConstraints.tightFor(width: 36, height: 36),
                padding: EdgeInsets.zero,
              ),
              Text(
                monthLabel,
                style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12),
              ),
              IconButton(
                onPressed: onNextMonth,
                icon: Icon(Icons.chevron_right, color: Colors.white.withOpacity(0.85)),
                constraints: const BoxConstraints.tightFor(width: 36, height: 36),
                padding: EdgeInsets.zero,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _MiniStatCard(
                  label: 'Receitas',
                  value: monthIncome,
                  color: const Color(0xFF10B981),
                  icon: Icons.arrow_upward,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MiniStatCard(
                  label: 'Gastos',
                  value: monthExpense,
                  color: const Color(0xFFEF4444),
                  icon: Icons.arrow_downward,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniStatCard extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  final IconData icon;

  const _MiniStatCard({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withOpacity(0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 12)),
                const SizedBox(height: 4),
                Text(
                  'R\$ ${value.toStringAsFixed(2)}',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PieSection extends StatelessWidget {
  final List<_CategorySlice> slices;

  const _PieSection({required this.slices});

  @override
  Widget build(BuildContext context) {
    final total = slices.fold<double>(0, (p, s) => p + s.amount);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
      ),
      child: Column(
        children: [
          if (slices.isEmpty || total <= 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Sem gastos neste mês.',
                style: TextStyle(color: Colors.white.withOpacity(0.75)),
              ),
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 170,
                  height: 170,
                  child: CustomPaint(
                    painter: _PieChartPainter(slices: slices),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Total',
                            style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 12),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'R\$ ${total.toStringAsFixed(2)}',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: slices.take(8).map((s) {
                      final pct = total <= 0 ? 0 : (s.amount / total) * 100;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: s.color,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                s.name,
                                style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 12),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${pct.toStringAsFixed(0)}%',
                              style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _PieChartPainter extends CustomPainter {
  final List<_CategorySlice> slices;

  _PieChartPainter({required this.slices});

  @override
  void paint(Canvas canvas, Size size) {
    final total = slices.fold<double>(0, (p, s) => p + s.amount);
    if (total <= 0) return;

    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;
    final holeRadius = radius * 0.62;

    var start = -math.pi / 2;
    for (final s in slices) {
      if (s.amount <= 0) continue;
      final sweep = (s.amount / total) * 2 * math.pi;
      final paint = Paint()
        ..style = PaintingStyle.fill
        ..color = s.color;
      canvas.drawArc(rect, start, sweep, true, paint);
      start += sweep;
    }

    final holePaint = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color(0xFF0F2027);

    canvas.drawCircle(center, holeRadius, holePaint);

    final ringBorder = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white.withOpacity(0.10);

    canvas.drawCircle(center, holeRadius, ringBorder);
  }

  @override
  bool shouldRepaint(covariant _PieChartPainter oldDelegate) {
    return oldDelegate.slices != slices;
  }
}

class _BalanceCard extends StatelessWidget {
  final double balance;

  const _BalanceCard({required this.balance});

  @override
  Widget build(BuildContext context) {
    final formatted = 'R\$ ${balance.toStringAsFixed(2)}';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF00C9A7), Color(0xFF00B4D8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00C9A7).withOpacity(0.35),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Saldo total atual',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            formatted,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 34,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _LatestTransactionsSection extends StatelessWidget {
  final List<_TxItem> items;
  final void Function(int transactionId) onEdit;
  final void Function(_TxItem transaction) onDelete;
  final void Function(_TxItem transaction, bool isPaid) onTogglePaid;

  _LatestTransactionsSection({
    required this.items,
    required this.onEdit,
    required this.onDelete,
    required this.onTogglePaid,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withOpacity(0.10)),
        ),
        child: Text(
          'Nenhuma transação neste mês.',
          style: TextStyle(color: Colors.white.withOpacity(0.75)),
        ),
      );
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
      ),
      child: Column(
        children: [
          for (int i = 0; i < items.length; i++) ...[
            _TxRow(item: items[i], onEdit: onEdit, onDelete: onDelete, onTogglePaid: onTogglePaid),
            if (i != items.length - 1)
              Divider(height: 1, color: Colors.white.withOpacity(0.08)),
          ],
        ],
      ),
    );
  }
}

class _TxRow extends StatefulWidget {
  final _TxItem item;
  final void Function(int transactionId) onEdit;
  final void Function(_TxItem transaction) onDelete;
  final void Function(_TxItem transaction, bool isPaid) onTogglePaid;

  _TxRow({
    required this.item,
    required this.onEdit,
    required this.onDelete,
    required this.onTogglePaid,
  });

  @override
  State<_TxRow> createState() => _TxRowState();
}

class _TxRowState extends State<_TxRow> {
  late bool _localIsPaid;

  @override
  void initState() {
    super.initState();
    _localIsPaid = widget.item.isPaid;
  }

  @override
  void didUpdateWidget(_TxRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Atualiza estado local se o item mudou (ex: após reload do backend)
    if (oldWidget.item.id != widget.item.id || oldWidget.item.isPaid != widget.item.isPaid) {
      _localIsPaid = widget.item.isPaid;
    }
  }

  void _handleToggle(bool newValue) {
    setState(() {
      _localIsPaid = newValue; // Atualização otimista imediata
    });
    widget.onTogglePaid(widget.item, newValue); // Chama backend em background
  }

  @override
  Widget build(BuildContext context) {
    final isIncome = widget.item.type == 'income';
    final amountColor = isIncome ? const Color(0xFF10B981) : const Color(0xFFEF4444);
    final sign = isIncome ? '+' : '-';
    final dateLabel = widget.item.date != null
        ? '${widget.item.date!.day.toString().padLeft(2, '0')}/${widget.item.date!.month.toString().padLeft(2, '0')}'
        : '';
    final catColor = widget.item.categoryColor ?? Colors.white.withOpacity(0.25);
    final catName = widget.item.categoryName ?? '';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
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
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.item.description,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        [
                          if (catName.isNotEmpty) catName,
                          if (dateLabel.isNotEmpty) dateLabel,
                        ].join(' • '),
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.6),
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (widget.item.type == 'expense' && _localIsPaid) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: const Color(0xFF10B981).withOpacity(0.5),
                            width: 1,
                          ),
                        ),
                        child: Text(
                          'Paga',
                          style: TextStyle(
                            color: const Color(0xFF10B981),
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '$sign R\$ ${widget.item.amount.toStringAsFixed(2)}',
            style: TextStyle(
              color: amountColor,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 10),
          if (widget.item.type == 'expense')
            Transform.scale(
              scale: 0.85,
              child: Switch(
                value: _localIsPaid,
                onChanged: _handleToggle,
                activeColor: const Color(0xFF10B981),
                activeTrackColor: const Color(0xFF10B981).withOpacity(0.5),
                inactiveThumbColor: Colors.white.withOpacity(0.9),
                inactiveTrackColor: Colors.white.withOpacity(0.15),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          IconButton(
            onPressed: () => widget.onEdit(widget.item.id),
            icon: const Icon(Icons.edit, color: Colors.white),
          ),
          IconButton(
            onPressed: () => widget.onDelete(widget.item),
            icon: const Icon(Icons.delete, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withOpacity(0.10)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Color(0xFFFF5722), size: 28),
            const SizedBox(height: 10),
            Text(
              message,
              style: TextStyle(color: Colors.white.withOpacity(0.85)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            ElevatedButton(
              onPressed: onRetry,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00C9A7),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }
}
