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

  double? _currentBalance;
  double? _currentBalanceAccumulated;
  double? _currentIncomePaid;
  double? _currentExpensePaid;
  double? _currentExpensePending;
  double? _openingBalance;

  // Cache de dados por mês/ano para evitar refetch
  final Map<String, _DashboardData> _dataCache = {};

  void _resetLocalTotals() {
    _currentBalance = null;
    _currentBalanceAccumulated = null;
    _currentIncomePaid = null;
    _currentExpensePaid = null;
    _currentExpensePending = null;
    _openingBalance = null;
  }

  void _prevMonth() {
    setState(() {
      if (_month == 1) {
        _month = 12;
        _year -= 1;
      } else {
        _month -= 1;
      }
      _resetLocalTotals();
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
      _resetLocalTotals();
      _future = _fetchDashboard();
    });
  }

  // Limpa cache quando adiciona/edita transação
  void _clearCache() {
    _dataCache.clear();
  }

  @override
  void didUpdateWidget(covariant DashboardPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workspaceId != widget.workspaceId) {
      _clearCache();
      _resetLocalTotals();
      _future = _fetchDashboardFor(_year, _month);
    }
  }

  void _syncLocalTotalsFromServer(_DashboardData data) {
    _currentIncomePaid = data.monthIncomePaid;
    _currentExpensePaid = data.monthExpensePaid;
    _currentBalance = data.balance;
    _currentBalanceAccumulated = data.balanceAccumulated;
    _currentExpensePending = data.monthExpensePending;
    _openingBalance = data.openingBalance;
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
      _currentBalanceAccumulated = (_openingBalance ?? 0) + (_currentBalance ?? 0);
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
    _future = widget.workspaceId == null
        ? Future.value(
            _DashboardData(
              balance: 0,
              balanceAccumulated: 0,
              openingBalance: 0,
              monthIncome: 0,
              monthExpense: 0,
              monthExpensePending: 0,
              monthIncomePaid: 0,
              monthExpensePaid: 0,
              month: _month,
              year: _year,
              expenseByCategory: const <_CategorySlice>[],
              latestTransactions: const <_TxItem>[],
            ),
          )
        : _fetchDashboard();

    _refreshListener = () {
      if (widget.workspaceId == null) {
        return;
      }
      final cacheKey = '$_year-$_month-${widget.workspaceId ?? 0}';
      _dataCache.remove(cacheKey);
      if (mounted) {
        setState(() {
          _resetLocalTotals();
          _future = _fetchDashboardFor(_year, _month);
        });
      }
    };
    financeRefreshTick.addListener(_refreshListener);
  }

  @override
  void dispose() {
    financeRefreshTick.removeListener(_refreshListener);
    super.dispose();
  }

  Future<_DashboardData> _fetchDashboard() async {
    return _fetchDashboardFor(_year, _month);
  }

  Future<_DashboardData> _fetchDashboardFor(int year, int month) async {
    // Verifica cache primeiro
    final cacheKey = '$year-$month-${widget.workspaceId ?? 0}';
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
      final balance = (data['balance'] as num? ?? 0).toDouble();
      final balanceAccumulated = (data['balance_accumulated'] as num? ?? balance).toDouble();
      final openingBalance = (data['opening_balance'] as num? ?? 0).toDouble();
      final monthIncome = (data['month_income'] as num? ?? 0).toDouble();
      final monthExpense = (data['month_expense'] as num? ?? 0).toDouble();
      final monthExpensePending = (data['month_expense_pending'] as num? ?? 0).toDouble();
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

      final dashData = _DashboardData(
        balance: balance,
        balanceAccumulated: balanceAccumulated,
        openingBalance: openingBalance,
        monthIncome: monthIncome,
        monthExpense: monthExpense,
        monthExpensePending: monthExpensePending,
        monthIncomePaid: monthIncomePaid,
        monthExpensePaid: monthExpensePaid,
        month: month,
        year: year,
        expenseByCategory: categories,
        latestTransactions: _parseLatestTransactions(data['latest_transactions']),
        timeSeries: _parseTimeSeries(data['time_series']),
        goals: _parseGoals(data['goals']),
        comparisons: _parseComparisons(data['comparisons']),
      );

      // Armazena no cache
      _dataCache[cacheKey] = dashData;
      return dashData;
    }

    throw Exception(data['message']?.toString() ?? 'Falha ao carregar dashboard.');
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
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () {
                        setState(() {
                          _clearCache();
                          _resetLocalTotals();
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
                      final effectiveMonthBalance = _currentBalance ?? data.balance;
                      final effectiveAccumulated = _currentBalanceAccumulated ?? data.balanceAccumulated;
                      return SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _BalanceCard(title: 'Saldo acumulado', balance: effectiveAccumulated),
                            const SizedBox(height: 12),
                            _MonthBalanceCard(balance: effectiveMonthBalance),
                            const SizedBox(height: 18),
                            _MonthSummaryCard(
                              monthIncome: data.monthIncome,
                              monthExpense: data.monthExpense,
                              monthExpensePending: data.monthExpensePending,
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
                            if ((data.timeSeries?.daily ?? const <_TimePoint>[]).isNotEmpty) ...[
                              const SizedBox(height: 18),
                              const _LineChartCard(
                                title: 'Evolução do saldo (dia a dia)',
                              ),
                              const SizedBox(height: 10),
                              _LineChart(
                                points: data.timeSeries!.daily
                                    .map((p) => _LinePoint(x: p.date.millisecondsSinceEpoch.toDouble(), y: p.balance))
                                    .toList(growable: false),
                                strokeColor: const Color(0xFF00C9A7),
                                fillColor: const Color(0xFF00C9A7),
                              ),
                            ],
                            if ((data.timeSeries?.monthly ?? const <_MonthPoint>[]).isNotEmpty) ...[
                              const SizedBox(height: 18),
                              const _LineChartCard(
                                title: 'Evolução do saldo (12 meses)',
                              ),
                              const SizedBox(height: 10),
                              _LineChart(
                                points: data.timeSeries!.monthly
                                    .map((p) => _LinePoint(x: (p.year * 12 + p.month).toDouble(), y: p.balance))
                                    .toList(growable: false),
                                strokeColor: const Color(0xFF00B4D8),
                                fillColor: const Color(0xFF00B4D8),
                              ),
                            ],
                            if (data.goals != null) ...[
                              const SizedBox(height: 18),
                              _GoalsCard(goals: data.goals!),
                            ],
                            if (data.comparisons != null) ...[
                              const SizedBox(height: 18),
                              _ComparisonsCard(comparisons: data.comparisons!),
                            ],
                            const SizedBox(height: 18),
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

class _PreviousMonthComparisonCard extends StatefulWidget {
  final int userId;
  final int? workspaceId;
  final int currentYear;
  final int currentMonth;
  final _DashboardData current;

  const _PreviousMonthComparisonCard({
    super.key,
    required this.userId,
    this.workspaceId,
    required this.currentYear,
    required this.currentMonth,
    required this.current,
  });

  @override
  State<_PreviousMonthComparisonCard> createState() => _PreviousMonthComparisonCardState();
}

class _PreviousMonthComparisonCardState extends State<_PreviousMonthComparisonCard> {
  Future<_DashboardData>? _previousFuture;
  bool _isExpanded = false;

  void _loadPreviousMonth() {
    var y = widget.currentYear;
    var m = widget.currentMonth - 1;
    if (m <= 0) {
      m = 12;
      y = y - 1;
    }

    setState(() {
      _isExpanded = true;
      _previousFuture = _fetchDashboardFor(widget.userId, y, m);
    });
  }

  Future<_DashboardData> _fetchDashboardFor(int userId, int year, int month) async {
    final params = <String, String>{
      'user_id': userId.toString(),
      'year': year.toString(),
      'month': month.toString(),
      if (widget.workspaceId != null) 'workspace_id': widget.workspaceId.toString(),
    };

    final uri = Uri.parse('$apiBaseUrl/gerenciamento-financeiro/api/dashboard')
        .replace(queryParameters: params);

    final response = await http.get(
      uri,
      headers: {'Content-Type': 'application/json'},
    );

    final Map<String, dynamic> data = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode == 200 && (data['success'] == true)) {
      final balance = (data['balance'] as num? ?? 0).toDouble();
      final balanceAccumulated = (data['balance_accumulated'] as num? ?? balance).toDouble();
      final openingBalance = (data['opening_balance'] as num? ?? 0).toDouble();
      final monthIncome = (data['month_income'] as num? ?? 0).toDouble();
      final monthExpense = (data['month_expense'] as num? ?? 0).toDouble();
      final monthExpensePending = (data['month_expense_pending'] as num? ?? 0).toDouble();
      final monthIncomePaid = (data['month_income_paid'] as num? ?? 0).toDouble();
      final monthExpensePaid = (data['month_expense_paid'] as num? ?? 0).toDouble();
      final month = (data['month'] as num? ?? 0).toInt();
      final year = (data['year'] as num? ?? 0).toInt();

      return _DashboardData(
        balance: balance,
        balanceAccumulated: balanceAccumulated,
        openingBalance: openingBalance,
        monthIncome: monthIncome,
        monthExpense: monthExpense,
        monthExpensePending: monthExpensePending,
        monthIncomePaid: monthIncomePaid,
        monthExpensePaid: monthExpensePaid,
        month: month,
        year: year,
        expenseByCategory: [],
        latestTransactions: [],
      );
    }

    throw Exception(data['message']?.toString() ?? 'Falha ao carregar mês anterior.');
  }

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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Comparação com mês anterior',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (!_isExpanded)
                TextButton.icon(
                  onPressed: _loadPreviousMonth,
                  icon: const Icon(Icons.analytics_outlined, size: 18),
                  label: const Text('Ver'),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF00C9A7),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  ),
                ),
            ],
          ),
          if (_isExpanded) ...[
            const SizedBox(height: 10),
            if (_previousFuture == null)
              Text(
                'Clique em "Ver" para carregar.',
                style: TextStyle(color: Colors.white.withOpacity(0.7)),
              )
            else
              FutureBuilder<_DashboardData>(
                future: _previousFuture,
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const LinearProgressIndicator(
                      color: Color(0xFF00C9A7),
                      backgroundColor: Colors.transparent,
                    );
                  }

                  if (snap.hasError) {
                    return Text(
                      'Não foi possível carregar o mês anterior.',
                      style: TextStyle(color: Colors.white.withOpacity(0.7)),
                    );
                  }

                  final prev = snap.data;
                  if (prev == null) {
                    return Text(
                      'Sem dados do mês anterior.',
                      style: TextStyle(color: Colors.white.withOpacity(0.7)),
                    );
                  }

                  final deltaBalance = widget.current.balance - prev.balance;
                  final deltaIncomePaid = widget.current.monthIncomePaid - prev.monthIncomePaid;
                  final deltaExpensePaid = widget.current.monthExpensePaid - prev.monthExpensePaid;

                  return Column(
                    children: [
                      _ComparisonRow(
                        label: 'Saldo',
                        value: widget.current.balance,
                        delta: deltaBalance,
                        positiveColor: const Color(0xFF10B981),
                        negativeColor: const Color(0xFFEF4444),
                      ),
                      const SizedBox(height: 8),
                      _ComparisonRow(
                        label: 'Receitas pagas',
                        value: widget.current.monthIncomePaid,
                        delta: deltaIncomePaid,
                        positiveColor: const Color(0xFF10B981),
                        negativeColor: const Color(0xFFEF4444),
                      ),
                      const SizedBox(height: 8),
                      _ComparisonRow(
                        label: 'Despesas pagas',
                        value: widget.current.monthExpensePaid,
                        delta: deltaExpensePaid,
                        positiveColor: const Color(0xFFEF4444),
                        negativeColor: const Color(0xFF10B981),
                      ),
                    ],
                  );
                },
              ),
          ],
        ],
      ),
    );
  }
}

class _ComparisonRow extends StatelessWidget {
  final String label;
  final double value;
  final double delta;
  final Color positiveColor;
  final Color negativeColor;

  const _ComparisonRow({
    required this.label,
    required this.value,
    required this.delta,
    required this.positiveColor,
    required this.negativeColor,
  });

  @override
  Widget build(BuildContext context) {
    final isPositive = delta >= 0;
    final deltaColor = isPositive ? positiveColor : negativeColor;
    final deltaSign = isPositive ? '+' : '-';
    final deltaAbs = delta.abs();

    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(color: Colors.white.withOpacity(0.75), fontWeight: FontWeight.w600),
          ),
        ),
        Text(
          'R\$ ${value.toStringAsFixed(2)}',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: deltaColor.withOpacity(0.15),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: deltaColor.withOpacity(0.35)),
          ),
          child: Text(
            '$deltaSign R\$ ${deltaAbs.toStringAsFixed(2)}',
            style: TextStyle(color: deltaColor, fontSize: 12, fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }
}

class _DashboardData {
  final double balance;
  final double balanceAccumulated;
  final double openingBalance;
  final double monthIncome;
  final double monthExpense;
  final double monthExpensePending;
  final double monthIncomePaid;
  final double monthExpensePaid;
  final int month;
  final int year;
  final List<_CategorySlice> expenseByCategory;
  final List<_TxItem> latestTransactions;
  final _TimeSeries? timeSeries;
  final _GoalsData? goals;
  final _ComparisonsData? comparisons;

  _DashboardData({
    required this.balance,
    required this.balanceAccumulated,
    required this.openingBalance,
    required this.monthIncome,
    required this.monthExpense,
    required this.monthExpensePending,
    required this.monthIncomePaid,
    required this.monthExpensePaid,
    required this.month,
    required this.year,
    required this.expenseByCategory,
    required this.latestTransactions,
    this.timeSeries,
    this.goals,
    this.comparisons,
  });
}

class _TimeSeries {
  final List<_TimePoint> daily;
  final List<_MonthPoint> monthly;

  const _TimeSeries({
    required this.daily,
    required this.monthly,
  });
}

class _TimePoint {
  final DateTime date;
  final double incomePaid;
  final double expensePaid;
  final double balance;

  const _TimePoint({
    required this.date,
    required this.incomePaid,
    required this.expensePaid,
    required this.balance,
  });
}

class _MonthPoint {
  final int year;
  final int month;
  final double incomePaid;
  final double expensePaid;
  final double balance;

  const _MonthPoint({
    required this.year,
    required this.month,
    required this.incomePaid,
    required this.expensePaid,
    required this.balance,
  });
}

class _GoalsData {
  final double incomeGoal;
  final double incomeActual;
  final double expenseGoal;
  final double expenseActual;

  const _GoalsData({
    required this.incomeGoal,
    required this.incomeActual,
    required this.expenseGoal,
    required this.expenseActual,
  });
}

class _ComparisonsData {
  final _ComparisonPeriod monthCurrent;
  final _ComparisonPeriod monthPrevious;
  final _ComparisonPeriod yearCurrent;
  final _ComparisonPeriod yearPrevious;

  const _ComparisonsData({
    required this.monthCurrent,
    required this.monthPrevious,
    required this.yearCurrent,
    required this.yearPrevious,
  });
}

class _ComparisonPeriod {
  final int? year;
  final int? month;
  final double incomePaid;
  final double expensePaid;
  final double balance;

  const _ComparisonPeriod({
    required this.year,
    required this.month,
    required this.incomePaid,
    required this.expensePaid,
    required this.balance,
  });
}

_TimeSeries? _parseTimeSeries(dynamic raw) {
  if (raw is! Map) return null;
  final dailyRaw = raw['daily'];
  final monthlyRaw = raw['monthly'];

  final daily = <_TimePoint>[];
  if (dailyRaw is List) {
    for (final e in dailyRaw) {
      if (e is! Map) continue;
      final dateStr = e['date']?.toString();
      final dt = dateStr != null ? DateTime.tryParse(dateStr) : null;
      if (dt == null) continue;
      daily.add(_TimePoint(
        date: dt,
        incomePaid: (e['income_paid'] as num? ?? 0).toDouble(),
        expensePaid: (e['expense_paid'] as num? ?? 0).toDouble(),
        balance: (e['balance'] as num? ?? 0).toDouble(),
      ));
    }
  }

  final monthly = <_MonthPoint>[];
  if (monthlyRaw is List) {
    for (final e in monthlyRaw) {
      if (e is! Map) continue;
      final y = (e['year'] as num?)?.toInt();
      final m = (e['month'] as num?)?.toInt();
      if (y == null || m == null) continue;
      monthly.add(_MonthPoint(
        year: y,
        month: m,
        incomePaid: (e['income_paid'] as num? ?? 0).toDouble(),
        expensePaid: (e['expense_paid'] as num? ?? 0).toDouble(),
        balance: (e['balance'] as num? ?? 0).toDouble(),
      ));
    }
  }

  if (daily.isEmpty && monthly.isEmpty) return null;
  return _TimeSeries(daily: daily, monthly: monthly);
}

_GoalsData? _parseGoals(dynamic raw) {
  if (raw is! Map) return null;
  final incomeGoal = (raw['income_goal'] as num? ?? 0).toDouble();
  final incomeActual = (raw['income_actual'] as num? ?? 0).toDouble();
  final expenseGoal = (raw['expense_goal'] as num? ?? 0).toDouble();
  final expenseActual = (raw['expense_actual'] as num? ?? 0).toDouble();
  return _GoalsData(
    incomeGoal: incomeGoal,
    incomeActual: incomeActual,
    expenseGoal: expenseGoal,
    expenseActual: expenseActual,
  );
}

_ComparisonPeriod? _parseComparisonPeriod(dynamic raw) {
  if (raw is! Map) return null;
  return _ComparisonPeriod(
    year: (raw['year'] as num?)?.toInt(),
    month: (raw['month'] as num?)?.toInt(),
    incomePaid: (raw['income_paid'] as num? ?? 0).toDouble(),
    expensePaid: (raw['expense_paid'] as num? ?? 0).toDouble(),
    balance: (raw['balance'] as num? ?? 0).toDouble(),
  );
}

_ComparisonsData? _parseComparisons(dynamic raw) {
  if (raw is! Map) return null;
  final mc = _parseComparisonPeriod(raw['month_current']);
  final mp = _parseComparisonPeriod(raw['month_previous']);
  final yc = _parseComparisonPeriod(raw['year_current']);
  final yp = _parseComparisonPeriod(raw['year_previous']);
  if (mc == null || mp == null || yc == null || yp == null) return null;
  return _ComparisonsData(monthCurrent: mc, monthPrevious: mp, yearCurrent: yc, yearPrevious: yp);
}

class _LineChartCard extends StatelessWidget {
  final String title;

  const _LineChartCard({
    required this.title,
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
      child: Text(
        title,
        style: TextStyle(
          color: Colors.white.withOpacity(0.9),
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _LinePoint {
  final double x;
  final double y;

  const _LinePoint({required this.x, required this.y});
}

class _LineChart extends StatelessWidget {
  final List<_LinePoint> points;
  final Color strokeColor;
  final Color fillColor;

  const _LineChart({
    required this.points,
    required this.strokeColor,
    required this.fillColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 160,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
      ),
      child: CustomPaint(
        painter: _LineChartPainter(
          points: points,
          strokeColor: strokeColor,
          fillColor: fillColor,
          gridColor: Colors.white.withOpacity(0.10),
        ),
      ),
    );
  }
}

class _LineChartPainter extends CustomPainter {
  final List<_LinePoint> points;
  final Color strokeColor;
  final Color fillColor;
  final Color gridColor;

  _LineChartPainter({
    required this.points,
    required this.strokeColor,
    required this.fillColor,
    required this.gridColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;

    final minX = points.map((p) => p.x).reduce(math.min);
    final maxX = points.map((p) => p.x).reduce(math.max);
    final minY = points.map((p) => p.y).reduce(math.min);
    final maxY = points.map((p) => p.y).reduce(math.max);

    final dx = (maxX - minX).abs() < 1e-9 ? 1.0 : (maxX - minX);
    final dy = (maxY - minY).abs() < 1e-9 ? 1.0 : (maxY - minY);

    const padding = 6.0;
    final w = size.width - padding * 2;
    final h = size.height - padding * 2;

    void drawGrid() {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = gridColor;

      for (int i = 1; i <= 3; i++) {
        final y = padding + (h * i / 4);
        canvas.drawLine(Offset(padding, y), Offset(padding + w, y), paint);
      }
    }

    Offset toOffset(_LinePoint p) {
      final xNorm = (p.x - minX) / dx;
      final yNorm = (p.y - minY) / dy;
      final x = padding + xNorm * w;
      final y = padding + (1 - yNorm) * h;
      return Offset(x, y);
    }

    drawGrid();

    final path = Path();
    final first = toOffset(points.first);
    path.moveTo(first.dx, first.dy);
    for (int i = 1; i < points.length; i++) {
      final o = toOffset(points[i]);
      path.lineTo(o.dx, o.dy);
    }

    final fillPath = Path.from(path)
      ..lineTo(padding + w, padding + h)
      ..lineTo(padding, padding + h)
      ..close();

    final fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = fillColor.withOpacity(0.12);
    canvas.drawPath(fillPath, fillPaint);

    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = strokeColor;
    canvas.drawPath(path, linePaint);

    final dotPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = strokeColor;

    final step = math.max(1, (points.length / 12).floor()).toInt();
    for (int i = 0; i < points.length; i += step) {
      final o = toOffset(points[i]);
      canvas.drawCircle(o, 3.2, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.strokeColor != strokeColor ||
        oldDelegate.fillColor != fillColor ||
        oldDelegate.gridColor != gridColor;
  }
}

class _GoalsCard extends StatelessWidget {
  final _GoalsData goals;

  const _GoalsCard({required this.goals});

  double _pct(double actual, double goal) {
    if (goal <= 0) return 0;
    final v = actual / goal;
    if (v.isNaN || v.isInfinite) return 0;
    return v.clamp(0, 1).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final incomePct = _pct(goals.incomeActual, goals.incomeGoal);
    final expensePct = _pct(goals.expenseActual, goals.expenseGoal);

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
          Text(
            'Meta vs realizado (mês)',
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          _GoalRow(
            label: 'Receitas',
            goal: goals.incomeGoal,
            actual: goals.incomeActual,
            progress: incomePct,
            color: const Color(0xFF10B981),
          ),
          const SizedBox(height: 12),
          _GoalRow(
            label: 'Gastos',
            goal: goals.expenseGoal,
            actual: goals.expenseActual,
            progress: expensePct,
            color: const Color(0xFFEF4444),
            invert: true,
          ),
        ],
      ),
    );
  }
}

class _GoalRow extends StatelessWidget {
  final String label;
  final double goal;
  final double actual;
  final double progress;
  final Color color;
  final bool invert;

  const _GoalRow({
    required this.label,
    required this.goal,
    required this.actual,
    required this.progress,
    required this.color,
    this.invert = false,
  });

  @override
  Widget build(BuildContext context) {
    final pctLabel = (progress * 100).toStringAsFixed(0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(color: Colors.white.withOpacity(0.80), fontWeight: FontWeight.w600),
              ),
            ),
            Text(
              'R\$ ${actual.toStringAsFixed(2)} / R\$ ${goal.toStringAsFixed(2)}',
              style: TextStyle(color: Colors.white.withOpacity(0.85), fontWeight: FontWeight.w700, fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 10,
            backgroundColor: Colors.white.withOpacity(0.10),
            valueColor: AlwaysStoppedAnimation<Color>(color.withOpacity(0.85)),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          invert ? 'Quanto menor, melhor • $pctLabel%' : 'Quanto maior, melhor • $pctLabel%',
          style: TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 11),
        ),
      ],
    );
  }
}

class _ComparisonsCard extends StatelessWidget {
  final _ComparisonsData comparisons;

  const _ComparisonsCard({required this.comparisons});

  @override
  Widget build(BuildContext context) {
    final monthDelta = comparisons.monthCurrent.balance - comparisons.monthPrevious.balance;
    final yearDelta = comparisons.yearCurrent.balance - comparisons.yearPrevious.balance;

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
          Text(
            'Comparativos',
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          _CompareBlock(
            title: 'Mês atual vs mês anterior',
            currentLabel: 'Atual',
            previousLabel: (comparisons.monthPrevious.month != null && comparisons.monthPrevious.year != null)
                ? '${comparisons.monthPrevious.month}/${comparisons.monthPrevious.year}'
                : 'Anterior',
            current: comparisons.monthCurrent,
            previous: comparisons.monthPrevious,
            deltaBalance: monthDelta,
          ),
          const SizedBox(height: 14),
          _CompareBlock(
            title: 'Ano atual vs ano anterior',
            currentLabel: (comparisons.yearCurrent.year != null) ? '${comparisons.yearCurrent.year}' : 'Atual',
            previousLabel: (comparisons.yearPrevious.year != null) ? '${comparisons.yearPrevious.year}' : 'Anterior',
            current: comparisons.yearCurrent,
            previous: comparisons.yearPrevious,
            deltaBalance: yearDelta,
          ),
        ],
      ),
    );
  }
}

class _CompareBlock extends StatelessWidget {
  final String title;
  final String currentLabel;
  final String previousLabel;
  final _ComparisonPeriod current;
  final _ComparisonPeriod previous;
  final double deltaBalance;

  const _CompareBlock({
    required this.title,
    required this.currentLabel,
    required this.previousLabel,
    required this.current,
    required this.previous,
    required this.deltaBalance,
  });

  @override
  Widget build(BuildContext context) {
    final isPositive = deltaBalance >= 0;
    final deltaColor = isPositive ? const Color(0xFF10B981) : const Color(0xFFEF4444);
    final deltaSign = isPositive ? '+' : '-';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: deltaColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: deltaColor.withOpacity(0.35)),
                ),
                child: Text(
                  '$deltaSign R\$ ${deltaBalance.abs().toStringAsFixed(2)}',
                  style: TextStyle(color: deltaColor, fontSize: 12, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _CompareRow(label: 'Saldo ($currentLabel)', value: current.balance),
          const SizedBox(height: 6),
          _CompareRow(label: 'Saldo ($previousLabel)', value: previous.balance),
        ],
      ),
    );
  }
}

class _CompareRow extends StatelessWidget {
  final String label;
  final double value;

  const _CompareRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(color: Colors.white.withOpacity(0.75), fontWeight: FontWeight.w600),
          ),
        ),
        Text(
          'R\$ ${value.toStringAsFixed(2)}',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
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

class _InstallmentInfo {
  final int index;
  final int total;
  final String baseDescription;

  const _InstallmentInfo({
    required this.index,
    required this.total,
    required this.baseDescription,
  });
}

_InstallmentInfo? _parseInstallmentSuffix(String description) {
  final value = description.trim();
  final re = RegExp(r'\((\d+)\/(\d+)\)\s*$');
  final m = re.firstMatch(value);
  if (m == null) return null;
  final index = int.tryParse(m.group(1) ?? '');
  final total = int.tryParse(m.group(2) ?? '');
  if (index == null || total == null || index < 1 || total < 1) return null;
  final base = value.substring(0, m.start).trim();
  return _InstallmentInfo(index: index, total: total, baseDescription: base);
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
  final double monthExpensePending;
  final int month;
  final int year;
  final VoidCallback onPrevMonth;
  final VoidCallback onNextMonth;

  const _MonthSummaryCard({
    required this.monthIncome,
    required this.monthExpense,
    required this.monthExpensePending,
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
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _MiniStatCard(
                  label: 'Pendentes',
                  value: monthExpensePending,
                  color: const Color(0xFFFBBF24),
                  icon: Icons.schedule,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(child: SizedBox()),
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

  const _PieSection({super.key, required this.slices});

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
  final String title;
  final double balance;

  const _BalanceCard({super.key, required this.title, required this.balance});

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
          Text(
            title,
            style: const TextStyle(
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

class _MonthBalanceCard extends StatelessWidget {
  final double balance;

  const _MonthBalanceCard({required this.balance});

  @override
  Widget build(BuildContext context) {
    final formatted = 'R\$ ${balance.toStringAsFixed(2)}';
    final positive = balance >= 0;
    final color = positive ? const Color(0xFF10B981) : const Color(0xFFEF4444);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Saldo do mês (pagos)',
              style: TextStyle(
                color: Colors.white.withOpacity(0.8),
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            formatted,
            style: TextStyle(
              color: color,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _LatestTransactionsSection extends StatelessWidget {
  final List<_TxItem> items;
  final int userId;
  final void Function(int transactionId) onEdit;
  final void Function(_TxItem transaction) onDelete;
  final void Function(_TxItem transaction, bool isPaid) onTogglePaid;

  _LatestTransactionsSection({
    required this.items,
    required this.userId,
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
            _TxRow(item: items[i], userId: userId, onEdit: onEdit, onDelete: onDelete, onTogglePaid: onTogglePaid),
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
  final int userId;
  final void Function(int transactionId) onEdit;
  final void Function(_TxItem transaction) onDelete;
  final void Function(_TxItem transaction, bool isPaid) onTogglePaid;

  _TxRow({
    required this.item,
    required this.userId,
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
    final installment = _parseInstallmentSuffix(widget.item.description);
    final titleDesc = installment?.baseDescription ?? widget.item.description;
    final installmentLabel = installment != null
        ? (installment.index == installment.total
            ? 'Última parcela (${installment.index}/${installment.total})'
            : 'Parcela ${installment.index}/${installment.total}')
        : '';
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
                  titleDesc,
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
                          if (installmentLabel.isNotEmpty) installmentLabel,
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
          if (_localIsPaid)
            IconButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => AttachmentsPage(
                      userId: widget.userId,
                      transactionId: widget.item.id,
                      transactionDescription: titleDesc,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.attach_file, color: Color(0xFF00C9A7)),
              tooltip: ' comprovantes',
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
