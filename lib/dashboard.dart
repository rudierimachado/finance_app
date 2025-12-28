import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'attachments_page.dart';
import 'config.dart';

class DashboardPage extends StatefulWidget {
  final int userId;
  final int? workspaceId;

  const DashboardPage({
    super.key,
    required this.userId,
    this.workspaceId,
  });

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  late Future<_DashboardData> _future;
  late final VoidCallback _refreshListener;

  // Data atual
  late int _month;
  late int _year;

  // Cache de dados por mês/ano
  final Map<String, _DashboardData> _dataCache = {};

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = now.month;
    _year = now.year;
    _future = _fetchDashboard();
    
    _refreshListener = () {
      setState(() {
        _clearCache();
        _future = _fetchDashboard();
      });
    };
    // Ouvir refresh global (ex: após salvar/editar transação)
    financeRefreshTick.addListener(_refreshListener);
  }

  @override
  void dispose() {
    financeRefreshTick.removeListener(_refreshListener);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant DashboardPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workspaceId != widget.workspaceId) {
      _clearCache();
      _future = _fetchDashboard();
    }
  }

  void _clearCache() {
    _dataCache.clear();
  }

  void _prevMonth() {
    setState(() {
      if (_month == 1) {
        _month = 12;
        _year -= 1;
      } else {
        _month -= 1;
      }
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
      _future = _fetchDashboard();
    });
  }

  Future<_DashboardData> _fetchDashboard() {
    return _fetchDashboardFor(_year, _month);
  }

  Future<_DashboardData> _fetchDashboardFor(int year, int month) async {
    final cacheKey = '${widget.workspaceId ?? 0}_${year}_$month';
    if (_dataCache.containsKey(cacheKey)) {
      return _dataCache[cacheKey]!;
    }

    final params = <String, String>{
      'user_id': widget.userId.toString(),
      'year': year.toString(),
      'month': month.toString(),
      if (widget.workspaceId != null) 'workspace_id': widget.workspaceId.toString(),
    };

    final uri = Uri.parse('$apiBaseUrl/gerenciamento-financeiro/api/dashboard')
        .replace(queryParameters: params);

    final response = await http.get(
      uri,
      headers: {
        'Content-Type': 'application/json',
      },
    );

    final Map<String, dynamic> data = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode == 200 && (data['success'] == true)) {
      final monthIncomePaid = (data['month_income_paid'] as num? ?? 0).toDouble();
      final monthExpensePaid = (data['month_expense_paid'] as num? ?? 0).toDouble();
      final monthExpensePending = (data['month_expense_pending'] as num? ?? 0).toDouble();
      final monthIncome = (data['month_income'] as num? ?? 0).toDouble();
      final monthExpense = (data['month_expense'] as num? ?? 0).toDouble();
      final creditCardExpense = (data['credit_card_expense_month'] as num? ?? 0).toDouble();

      final creditCardTopName = data['credit_card_top_name']?.toString();
      final creditCardTopAmount = (data['credit_card_top_amount'] as num? ?? 0).toDouble();
      final pendingBillsCount = (data['pending_bills_count'] as num? ?? 0).toInt();
      final overdueBillsCount = (data['overdue_bills_count'] as num? ?? 0).toInt();
      
      // Saldos vindos do backend (ajuste: disponível = saldo acumulado)
      final openingBalance = (data['opening_balance'] as num? ?? 0).toDouble();
      final availableBalance = (data['available_balance'] as num? ?? 0).toDouble();
      final dinheiroEmCaixa = availableBalance; // saldo acumulado: anterior + mês pago
      final contasAPagar = monthExpensePending;
      final situacaoFinal = dinheiroEmCaixa - contasAPagar;

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

      final dashData = _DashboardData(
        dinheiroEmCaixa: dinheiroEmCaixa,
        contasAPagar: contasAPagar,
        situacaoFinal: situacaoFinal,
        monthIncomePaid: monthIncomePaid,
        monthExpensePaid: monthExpensePaid,
        monthIncome: monthIncome,
        monthExpense: monthExpense,
        monthExpensePending: monthExpensePending,
        creditCardExpense: creditCardExpense,
        creditCardTopName: creditCardTopName,
        creditCardTopAmount: creditCardTopAmount,
        pendingBillsCount: pendingBillsCount,
        overdueBillsCount: overdueBillsCount,
        month: _month,
        year: _year,
        expenseByCategory: categories,
        latestTransactions: _parseLatestTransactions(data['latest_transactions']),
      );

      // Armazena no cache
      _dataCache[cacheKey] = dashData;
      return dashData;
    }

    throw Exception(data['message']?.toString() ?? 'Falha ao carregar dashboard.');
  }

  List<_TxItem> _parseLatestTransactions(dynamic txData) {
    if (txData is! List) return [];
    
    final transactions = <_TxItem>[];
    for (final item in txData) {
      if (item is! Map) continue;
      
      final id = (item['id'] as num?)?.toInt() ?? 0;
      final description = item['description']?.toString() ?? '';
      final amount = (item['amount'] as num?)?.toDouble() ?? 0.0;
      final type = item['type']?.toString() ?? '';
      final isPaid = (item['is_paid'] as bool?) ?? false;
      final dateStr = item['transaction_date']?.toString() ?? '';
      
      DateTime? date;
      try {
        date = DateTime.parse(dateStr);
      } catch (e) {
        continue;
      }
      
      transactions.add(_TxItem(
        id: id,
        description: description,
        amount: amount,
        type: type,
        isPaid: isPaid,
        date: date,
      ));
    }
    
    return transactions;
  }

  Color _parseHexColor(String? hexString) {
    if (hexString == null || hexString.isEmpty) {
      return Colors.blue;
    }
    
    try {
      String hex = hexString.replaceAll('#', '');
      if (hex.length == 6) {
        hex = 'FF$hex';
      }
      return Color(int.parse(hex, radix: 16));
    } catch (e) {
      return Colors.blue;
    }
  }

  Color _fallbackColorFor(String name) {
    final colors = [
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.red,
      Colors.teal,
      Colors.amber,
      Colors.indigo,
    ];
    return colors[name.hashCode % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    // Aguardar workspace_id estar definido para evitar mistura de dados
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
                // Header
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
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () {
                        setState(() {
                          _clearCache();
                          _future = _fetchDashboard();
                        });
                      },
                      icon: const Icon(
                        Icons.refresh,
                        color: Color(0xFF00C9A7),
                        size: 22,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Navegação do mês
                _MonthNavigator(
                  month: _month,
                  year: _year,
                  onPrevMonth: _prevMonth,
                  onNextMonth: _nextMonth,
                ),
                const SizedBox(height: 20),

                // Conteúdo principal
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
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Erro ao carregar dados',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.8),
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 10),
                              ElevatedButton(
                                onPressed: () {
                                  setState(() {
                                    _future = _fetchDashboard();
                                  });
                                },
                                child: const Text('Tentar novamente'),
                              ),
                            ],
                          ),
                        );
                      }

                      final data = snapshot.data!;
                      return SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Cards principais em grid 2x2
                            Row(
                              children: [
                                Expanded(
                                  child: _DinheiroEmCaixaCard(valor: data.dinheiroEmCaixa),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _ContasAPagarCard(
                                    valor: data.contasAPagar,
                                    quantidadeContas: data.pendingBillsCount,
                                    contasVencidas: data.overdueBillsCount,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),

                            // Card situação final (maior destaque)
                            _SituacaoFinalCard(valor: data.situacaoFinal),
                            const SizedBox(height: 12),

                            // Resumo do mês
                            _ResumoMesCard(
                              receitas: data.monthIncome,
                              gastos: data.monthExpense,
                              pendentes: data.monthExpensePending,
                              receitasPagas: data.monthIncomePaid,
                              gastosPagos: data.monthExpensePaid,
                            ),
                            const SizedBox(height: 12),

                            // Cards secundários
                            Row(
                              children: [
                                Expanded(
                                  child: _CartaoCard(
                                    valor: data.creditCardExpense,
                                    topCardName: data.creditCardTopName,
                                    topCardAmount: data.creditCardTopAmount,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _ProximasContasCard(
                                    pendingCount: data.pendingBillsCount,
                                    overdueCount: data.overdueBillsCount,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),

                            // Gastos por categoria
                            Text(
                              'Gastos por categoria',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.9),
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 10),
                            _PieSection(slices: data.expenseByCategory),
                            const SizedBox(height: 18),

                            // Últimas transações
                            _UltimasTransacoesSection(transactions: data.latestTransactions),
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
}

// 💰 Card Dinheiro em Caixa
class _DinheiroEmCaixaCard extends StatelessWidget {
  final double valor;

  const _DinheiroEmCaixaCard({required this.valor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF10B981).withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.account_balance_wallet,
                  color: Color(0xFF10B981),
                  size: 18,
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'DINHEIRO DISPONÍVEL',
                  style: TextStyle(
                    color: Color(0xFF10B981),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'R\$ ${valor.toStringAsFixed(2)}',
            style: const TextStyle(
              color: Color(0xFF10B981),
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Saldo atual que você tem',
            style: TextStyle(
              color: Colors.white.withOpacity(0.6),
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

// ⚠️ Card Contas a Pagar
class _ContasAPagarCard extends StatelessWidget {
  final double valor;
  final int quantidadeContas;
  final int contasVencidas;

  const _ContasAPagarCard({
    required this.valor,
    required this.quantidadeContas,
    required this.contasVencidas,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  contasVencidas > 0 ? Icons.warning : Icons.schedule,
                  color: const Color(0xFFEF4444),
                  size: 18,
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'CONTAS A PAGAR',
                  style: TextStyle(
                    color: Color(0xFFEF4444),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'R\$ ${valor.toStringAsFixed(2)}',
            style: const TextStyle(
              color: Color(0xFFEF4444),
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            contasVencidas > 0 
                ? '$quantidadeContas contas ($contasVencidas vencidas)'
                : '$quantidadeContas contas pendentes',
            style: TextStyle(
              color: Colors.white.withOpacity(0.6),
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

// 🔥 Card Situação Final (destaque)
class _SituacaoFinalCard extends StatelessWidget {
  final double valor;

  const _SituacaoFinalCard({required this.valor});

  @override
  Widget build(BuildContext context) {
    final isPositive = valor >= 0;
    final color = isPositive ? const Color(0xFF10B981) : const Color(0xFFEF4444);
    final icon = isPositive ? Icons.trending_up : Icons.trending_down;
    final label = isPositive ? 'VOCÊ TEM SOBRA' : 'VOCÊ ESTÁ NO VERMELHO';
    final description = isPositive 
        ? 'Parabéns! Você tem dinheiro sobrando'
        : 'Atenção! Falta dinheiro para as contas';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withOpacity(0.3), width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: color,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'R\$ ${valor.abs().toStringAsFixed(2)}',
            style: TextStyle(
              color: color,
              fontSize: 28,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

// 📊 Card Resumo do Mês
class _ResumoMesCard extends StatelessWidget {
  final double receitas;
  final double gastos;
  final double pendentes;
  final double receitasPagas;
  final double gastosPagos;

  const _ResumoMesCard({
    required this.receitas,
    required this.gastos,
    required this.pendentes,
    required this.receitasPagas,
    required this.gastosPagos,
  });

  @override
  Widget build(BuildContext context) {
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
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFF00B4D8).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.analytics,
                  color: Color(0xFF00B4D8),
                  size: 18,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'MOVIMENTO DO MÊS',
                style: TextStyle(
                  color: Color(0xFF00B4D8),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Receitas',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      'R\$ ${receitas.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: Color(0xFF10B981),
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'Pagas: R\$ ${receitasPagas.toStringAsFixed(2)}',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Gastos',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      'R\$ ${gastos.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: Color(0xFFEF4444),
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'Pagos: R\$ ${gastosPagos.toStringAsFixed(2)}',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Pendentes: R\$ ${pendentes.toStringAsFixed(2)}',
            style: TextStyle(
              color: Colors.orange.withOpacity(0.8),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// 💳 Card Cartão
class _CartaoCard extends StatelessWidget {
  final double valor;
  final String? topCardName;
  final double topCardAmount;

  const _CartaoCard({
    required this.valor,
    required this.topCardName,
    required this.topCardAmount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.orange.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.credit_card,
                  color: Colors.orange,
                  size: 18,
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'CARTÃO',
                  style: TextStyle(
                    color: Colors.orange,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'R\$ ${valor.toStringAsFixed(2)}',
            style: const TextStyle(
              color: Colors.orange,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            (topCardName != null && topCardName!.trim().isNotEmpty)
                ? 'Principal: ${topCardName!} (R\$ ${topCardAmount.toStringAsFixed(2)})'
                : 'Gastos no cartão este mês',
            style: TextStyle(
              color: Colors.white.withOpacity(0.6),
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

// 📅 Card Próximas Contas (placeholder)
class _ProximasContasCard extends StatelessWidget {
  final int pendingCount;
  final int overdueCount;

  const _ProximasContasCard({
    required this.pendingCount,
    required this.overdueCount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
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
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFF00C9A7).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.calendar_month,
                  color: Color(0xFF00C9A7),
                  size: 18,
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'PRÓXIMAS',
                  style: TextStyle(
                    color: Color(0xFF00C9A7),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '$pendingCount contas',
            style: const TextStyle(
              color: Color(0xFF00C9A7),
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            overdueCount > 0 ? '$overdueCount vencidas' : 'Nenhuma vencida',
            style: TextStyle(
              color: Colors.white.withOpacity(0.6),
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

// Navegador do mês
class _MonthNavigator extends StatelessWidget {
  final int month;
  final int year;
  final VoidCallback onPrevMonth;
  final VoidCallback onNextMonth;

  const _MonthNavigator({
    required this.month,
    required this.year,
    required this.onPrevMonth,
    required this.onNextMonth,
  });

  @override
  Widget build(BuildContext context) {
    final monthNames = [
      '', 'Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho',
      'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro'
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            onPressed: onPrevMonth,
            icon: const Icon(Icons.chevron_left, color: Colors.white),
          ),
          Text(
            '${monthNames[month]} $year',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          IconButton(
            onPressed: onNextMonth,
            icon: const Icon(Icons.chevron_right, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

// Classes de dados
class _DashboardData {
  final double dinheiroEmCaixa;
  final double contasAPagar;
  final double situacaoFinal;
  final double monthIncomePaid;
  final double monthExpensePaid;
  final double monthIncome;
  final double monthExpense;
  final double monthExpensePending;
  final double creditCardExpense;
  final String? creditCardTopName;
  final double creditCardTopAmount;
  final int pendingBillsCount;
  final int overdueBillsCount;
  final int month;
  final int year;
  final List<_CategorySlice> expenseByCategory;
  final List<_TxItem> latestTransactions;

  const _DashboardData({
    required this.dinheiroEmCaixa,
    required this.contasAPagar,
    required this.situacaoFinal,
    required this.monthIncomePaid,
    required this.monthExpensePaid,
    required this.monthIncome,
    required this.monthExpense,
    required this.monthExpensePending,
    required this.creditCardExpense,
    required this.creditCardTopName,
    required this.creditCardTopAmount,
    required this.pendingBillsCount,
    required this.overdueBillsCount,
    required this.month,
    required this.year,
    required this.expenseByCategory,
    required this.latestTransactions,
  });
}

class _CategorySlice {
  final String name;
  final double amount;
  final Color color;

  const _CategorySlice({
    required this.name,
    required this.amount,
    required this.color,
  });
}

class _TxItem {
  final int id;
  final String description;
  final double amount;
  final String type;
  final bool isPaid;
  final DateTime date;

  const _TxItem({
    required this.id,
    required this.description,
    required this.amount,
    required this.type,
    required this.isPaid,
    required this.date,
  });
}

// Seção de gráfico de pizza (mantém a existente)
class _PieSection extends StatelessWidget {
  final List<_CategorySlice> slices;

  const _PieSection({required this.slices});

  @override
  Widget build(BuildContext context) {
    if (slices.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Center(
          child: Text(
            'Nenhum gasto por categoria neste mês',
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 14,
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
      ),
      child: Column(
        children: [
          // Lista das categorias
          ...slices.map((slice) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: slice.color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    slice.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                    ),
                  ),
                ),
                Text(
                  'R\$ ${slice.amount.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          )).toList(),
        ],
      ),
    );
  }
}

// Seção de últimas transações
class _UltimasTransacoesSection extends StatelessWidget {
  final List<_TxItem> transactions;

  const _UltimasTransacoesSection({required this.transactions});

  @override
  Widget build(BuildContext context) {
    if (transactions.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Últimas transações',
          style: TextStyle(
            color: Colors.white.withOpacity(0.9),
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withOpacity(0.10)),
          ),
          child: ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: math.min(transactions.length, 5),
            itemBuilder: (context, index) {
              final tx = transactions[index];
              final isIncome = tx.type == 'income';
              final color = isIncome ? const Color(0xFF10B981) : const Color(0xFFEF4444);
              
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: color.withOpacity(0.2),
                  child: Icon(
                    isIncome ? Icons.arrow_downward : Icons.arrow_upward,
                    color: color,
                    size: 18,
                  ),
                ),
                title: Text(
                  tx.description,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  '${tx.date.day}/${tx.date.month}',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                  ),
                ),
                trailing: Text(
                  '${isIncome ? '+' : '-'}R\$ ${tx.amount.toStringAsFixed(2)}',
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}