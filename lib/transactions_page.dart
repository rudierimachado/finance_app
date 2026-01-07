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

class _TransactionsPageState extends State<TransactionsPage> with TickerProviderStateMixin {
  late int _year;
  late int _month;
  String _typeFilter = 'all';
  String _statusFilter = 'all';
  String _categoryFilter = 'all';
  final _queryController = TextEditingController();

  bool _filtersExpanded = false;
  late AnimationController _animationController;
  late AnimationController _staggerController;
  late Animation<double> _fadeAnimation;

  late final VoidCallback _refreshListener;

  late Future<_TransactionsData> _future;
  List<_TxItem> _currentItems = <_TxItem>[];
  List<String> _availableCategories = [];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _year = now.year;
    _month = now.month;
    _future = _fetch();

    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _staggerController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );

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
    _animationController.dispose();
    _staggerController.dispose();
    financeRefreshTick.removeListener(_refreshListener);
    _queryController.dispose();
    super.dispose();
  }

  void _toggleFilters() {
    setState(() {
      _filtersExpanded = !_filtersExpanded;
      if (_filtersExpanded) {
        _animationController.forward();
      } else {
        _animationController.reverse();
      }
    });
  }

  void _prevMonth() {
    setState(() {
      if (_month == 1) {
        _month = 12;
        _year -= 1;
      } else {
        _month -= 1;
      }
      _currentItems = [];
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
      _currentItems = [];
      _future = _fetch();
    });
  }

  void _applyFilters() {
    setState(() {
      _future = _fetch();
    });
  }

  void _clearFilters() {
    setState(() {
      _typeFilter = 'all';
      _statusFilter = 'all';
      _categoryFilter = 'all';
      _queryController.clear();
      _future = _fetch();
    });
  }

  Future<_TransactionsData> _fetch() async {
    final q = _queryController.text.trim();
    final type = _typeFilter == 'all' ? '' : _typeFilter;

    final params = <String, String>{
      'user_id': widget.userId.toString(),
      'year': _year.toString(),
      'month': _month.toString(),
      if (widget.workspaceId != null) 'workspace_id': widget.workspaceId.toString(),
      if (type.isNotEmpty) 'type': type,
      if (q.isNotEmpty) 'q': q,
    };

    final uri = Uri.parse('$apiBaseUrl/gerenciamento-financeiro/api/transactions')
        .replace(queryParameters: params);

    final response = await http.get(
      uri,
      headers: {'Content-Type': 'application/json'},
    );

    if (response.statusCode != 200) {
      throw Exception('Erro ao carregar transações: ${response.statusCode}');
    }

    final data = jsonDecode(response.body);
    if (data['success'] != true) {
      throw Exception(data['message'] ?? 'Erro desconhecido');
    }

    final rawItems = (data['transactions'] as List<dynamic>? ?? []);
    final items = <_TxItem>[];
    final categories = <String>{};

    for (final e in rawItems) {
      if (e is! Map) continue;

      final id = (e['id'] as num?)?.toInt() ?? 0;
      final desc = e['description']?.toString() ?? '';
      final amount = (e['amount'] as num?)?.toDouble() ?? 0.0;
      final rawType = e['type']?.toString() ?? 'expense';
      final typeStr = rawType == 'income' ? 'income' : 'expense';
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
      
      if (catName != null && catName.isNotEmpty) {
        categories.add(catName);
      }

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

    final double totalIncome = items.where((t) => t.type == 'income').fold(0.0, (sum, t) => sum + t.amount);
    final double totalExpense = items.where((t) => t.type == 'expense').fold(0.0, (sum, t) => sum + t.amount);
    final double paidIncome = items.where((t) => t.type == 'income' && t.isPaid).fold(0.0, (sum, t) => sum + t.amount);
    final double paidExpense = items.where((t) => t.type == 'expense' && t.isPaid).fold(0.0, (sum, t) => sum + t.amount);

    return _TransactionsData(
      transactions: items,
      categories: categories.toList()..sort(),
      totalIncome: totalIncome,
      totalExpense: totalExpense,
      paidIncome: paidIncome,
      paidExpense: paidExpense,
      prevBalance: (data['prev_balance'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Color? _parseHexColor(String? hexString) {
    if (hexString == null || hexString.isEmpty) return null;
    
    try {
      String hex = hexString.replaceAll('#', '');
      if (hex.length == 6) {
        hex = 'FF$hex';
      }
      return Color(int.parse(hex, radix: 16));
    } catch (e) {
      return null;
    }
  }

  List<_TxItem> _applyLocalFilters(List<_TxItem> items) {
    var filtered = List<_TxItem>.from(items);

    if (_statusFilter == 'paid') {
      filtered = filtered.where((item) => item.isPaid).toList();
    } else if (_statusFilter == 'pending') {
      filtered = filtered.where((item) => !item.isPaid).toList();
    }

    if (_categoryFilter != 'all') {
      filtered = filtered.where((item) => item.categoryName == _categoryFilter).toList();
    }

    return filtered;
  }

  void _editTransaction(int transactionId) async {
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

    try {
      bool isRouteMismatch(http.Response r) {
        final bodyLower = r.body.toLowerCase();
        return bodyLower.contains('<!doctype html>') ||
            bodyLower.contains('endpoint não encontrado') ||
            bodyLower.contains('endpoint nao encontrado');
      }

      Uri buildTxUri(String prefix) => Uri.parse(
        '$apiBaseUrl$prefix/api/transactions/$transactionId?user_id=${widget.userId}',
      );

      final payload = {
        'user_id': widget.userId,
        'is_paid': newStatus,
        'action': 'set_paid',
      };

      var uri = buildTxUri('/gerenciamento-financeiro');
      var response = await http.put(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );

      if ((response.statusCode == 404 || response.statusCode == 405) && isRouteMismatch(response)) {
        uri = buildTxUri('');
        response = await http.put(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        );
      }

      if (response.statusCode != 200) {
        throw Exception('Erro HTTP ${response.statusCode}');
      }

      final responseData = jsonDecode(response.body);
      if (responseData['success'] != true) {
        throw Exception(responseData['message'] ?? 'Erro desconhecido');
      }

      financeRefreshTick.value = financeRefreshTick.value + 1;
    } catch (e) {
      if (!mounted) return;

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
            isPaid: !newStatus,
          );
        });
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao alterar status: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.workspaceId == null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF8F9FA),
        body: const Center(
          child: CircularProgressIndicator(
            color: Color(0xFF6366F1),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: SafeArea(
        child: Column(
          children: [
            // Header Compacto
            _CompactHeader(
              year: _year,
              month: _month,
              onPrevMonth: _prevMonth,
              onNextMonth: _nextMonth,
              onToggleFilters: _toggleFilters,
              filtersExpanded: _filtersExpanded,
              hasFilters: _typeFilter != 'all' || _statusFilter != 'all' || 
                         _categoryFilter != 'all' || _queryController.text.isNotEmpty,
            ),

            // Filtros
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              height: _filtersExpanded ? null : 0,
              child: _filtersExpanded 
                  ? FadeTransition(
                      opacity: _fadeAnimation,
                      child: _CompactFiltersSection(
                        typeFilter: _typeFilter,
                        statusFilter: _statusFilter,
                        categoryFilter: _categoryFilter,
                        queryController: _queryController,
                        availableCategories: _availableCategories,
                        onTypeChanged: (value) => setState(() => _typeFilter = value),
                        onStatusChanged: (value) => setState(() => _statusFilter = value),
                        onCategoryChanged: (value) => setState(() => _categoryFilter = value),
                        onApply: _applyFilters,
                        onClear: _clearFilters,
                      ),
                    )
                  : const SizedBox.shrink(),
            ),

            // Conteúdo principal
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: FutureBuilder<_TransactionsData>(
                  future: _future,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const _CleanLoader();
                    }
                    
                    if (snapshot.hasError) {
                      return _ErrorWidget(
                        message: 'Erro ao carregar transações',
                        onRetry: () => setState(() => _future = _fetch()),
                      );
                    }

                    final data = snapshot.data!;
                    _currentItems = data.transactions;
                    _availableCategories = data.categories;

                    final filteredItems = _applyLocalFilters(_currentItems);

                    _staggerController.forward();

                    return Column(
                      children: [
                        // Barra horizontal compacta com nomes corretos
                        _CompactSummaryBar(data: data),
                        const SizedBox(height: 16),

                        // TODA A TELA para as transações
                        Expanded(
                          child: filteredItems.isEmpty
                              ? _CleanEmptyState(
                                  hasFilters: _typeFilter != 'all' || 
                                             _statusFilter != 'all' || 
                                             _categoryFilter != 'all' || 
                                             _queryController.text.isNotEmpty,
                                  onClearFilters: _clearFilters,
                                )
                              : _FocusedTransactionsList(
                                  items: filteredItems,
                                  onEdit: _editTransaction,
                                  onViewAttachments: _viewAttachments,
                                  onTogglePaid: _setPaid,
                                  controller: _staggerController,
                                ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Header compacto
class _CompactHeader extends StatelessWidget {
  final int year;
  final int month;
  final VoidCallback onPrevMonth;
  final VoidCallback onNextMonth;
  final VoidCallback onToggleFilters;
  final bool filtersExpanded;
  final bool hasFilters;

  const _CompactHeader({
    required this.year,
    required this.month,
    required this.onPrevMonth,
    required this.onNextMonth,
    required this.onToggleFilters,
    required this.filtersExpanded,
    required this.hasFilters,
  });

  @override
  Widget build(BuildContext context) {
    final monthNames = [
      '', 'Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho',
      'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro'
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _CompactMonthButton(
                  icon: Icons.chevron_left,
                  onPressed: onPrevMonth,
                ),
                const SizedBox(width: 12),
                Text(
                  '${monthNames[month]} $year',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 12),
                _CompactMonthButton(
                  icon: Icons.chevron_right,
                  onPressed: onNextMonth,
                ),
              ],
            ),
          ),
          const Spacer(),
          _CompactFilterButton(
            onPressed: onToggleFilters,
            isExpanded: filtersExpanded,
            hasFilters: hasFilters,
          ),
        ],
      ),
    );
  }
}

class _CompactMonthButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;

  const _CompactMonthButton({
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.2),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(
          icon,
          color: Colors.white,
          size: 16,
        ),
      ),
    );
  }
}

class _CompactFilterButton extends StatelessWidget {
  final VoidCallback onPressed;
  final bool isExpanded;
  final bool hasFilters;

  const _CompactFilterButton({
    required this.onPressed,
    required this.isExpanded,
    required this.hasFilters,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: hasFilters ? const Color(0xFF6366F1) : const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(10),
          boxShadow: hasFilters ? [
            BoxShadow(
              color: const Color(0xFF6366F1).withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ] : null,
        ),
        child: Stack(
          children: [
            Center(
              child: AnimatedRotation(
                turns: isExpanded ? 0.5 : 0,
                duration: const Duration(milliseconds: 300),
                child: Icon(
                  isExpanded ? Icons.close : Icons.tune,
                  color: hasFilters ? Colors.white : const Color(0xFF6B7280),
                  size: 18,
                ),
              ),
            ),
            if (hasFilters && !isExpanded)
              Positioned(
                right: 2,
                top: 2,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Color(0xFFEF4444),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// Barra horizontal compacta com os nomes ORIGINAIS corretos
class _CompactSummaryBar extends StatelessWidget {
  final _TransactionsData data;

  const _CompactSummaryBar({required this.data});

  @override
  Widget build(BuildContext context) {
    final pendingExpense = data.totalExpense - data.paidExpense;
    final monthBalance = data.totalIncome - data.totalExpense;
    final monthBalanceColor = monthBalance >= 0 ? const Color(0xFF10B981) : const Color(0xFFEF4444);
    final totalBalance = data.prevBalance + monthBalance;
    final totalBalanceColor = totalBalance >= 0 ? const Color(0xFF00C9A7) : const Color(0xFFEF4444);
    
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Saldo Total - DESTAQUE principal
          Expanded(
            flex: 2,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Saldo Total',
                  style: TextStyle(
                    color: const Color(0xFF6B7280),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  'R\$ ${totalBalance.toStringAsFixed(2)}',
                  style: TextStyle(
                    color: totalBalanceColor,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          
          Container(
            width: 1,
            height: 30,
            color: const Color(0xFFE5E7EB),
          ),
          
          // A Pagar
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  'A Pagar',
                  style: TextStyle(
                    color: const Color(0xFF6B7280),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  'R\$ ${pendingExpense.toStringAsFixed(0)}',
                  style: const TextStyle(
                    color: Color(0xFFEF4444),
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          
          Container(
            width: 1,
            height: 30,
            color: const Color(0xFFE5E7EB),
          ),
          
          // Já Pago
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  'Já Pago',
                  style: TextStyle(
                    color: const Color(0xFF6B7280),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  'R\$ ${data.paidExpense.toStringAsFixed(0)}',
                  style: const TextStyle(
                    color: Colors.orange,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          
          Container(
            width: 1,
            height: 30,
            color: const Color(0xFFE5E7EB),
          ),
          
          // Recebido
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  'Recebido',
                  style: TextStyle(
                    color: const Color(0xFF6B7280),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  'R\$ ${data.paidIncome.toStringAsFixed(0)}',
                  style: const TextStyle(
                    color: Color(0xFF10B981),
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          
          Container(
            width: 1,
            height: 30,
            color: const Color(0xFFE5E7EB),
          ),
          
          // Saldo do Mês
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  'Saldo Mês',
                  style: TextStyle(
                    color: const Color(0xFF6B7280),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  'R\$ ${monthBalance.toStringAsFixed(0)}',
                  style: TextStyle(
                    color: monthBalanceColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Lista de transações focada
class _FocusedTransactionsList extends StatelessWidget {
  final List<_TxItem> items;
  final void Function(int) onEdit;
  final void Function(int, String) onViewAttachments;
  final void Function(int, bool) onTogglePaid;
  final AnimationController controller;

  const _FocusedTransactionsList({
    required this.items,
    required this.onEdit,
    required this.onViewAttachments,
    required this.onTogglePaid,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        return _FocusedTransactionCard(
          item: items[index],
          onEdit: () => onEdit(items[index].id),
          onViewAttachments: () => onViewAttachments(items[index].id, items[index].description),
          onTogglePaid: (value) => onTogglePaid(items[index].id, value),
        );
      },
    );
  }
}

// Card de transação otimizado
class _FocusedTransactionCard extends StatefulWidget {
  final _TxItem item;
  final VoidCallback onEdit;
  final VoidCallback onViewAttachments;
  final ValueChanged<bool> onTogglePaid;

  const _FocusedTransactionCard({
    required this.item,
    required this.onEdit,
    required this.onViewAttachments,
    required this.onTogglePaid,
  });

  @override
  State<_FocusedTransactionCard> createState() => _FocusedTransactionCardState();
}

class _FocusedTransactionCardState extends State<_FocusedTransactionCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isIncome = widget.item.type == 'income';
    final amountColor = isIncome ? const Color(0xFF10B981) : const Color(0xFFEF4444);
    final bgColor = isIncome ? const Color(0xFF10B981) : const Color(0xFFEF4444);
    final icon = isIncome ? Icons.trending_up : Icons.trending_down;
    final sign = isIncome ? '+' : '-';
    
    final dateLabel = widget.item.date != null
        ? '${widget.item.date!.day.toString().padLeft(2, '0')}/${widget.item.date!.month.toString().padLeft(2, '0')}/${widget.item.date!.year}'
        : 'Data não definida';

    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) => _controller.reverse(),
      onTapCancel: () => _controller.reverse(),
      onTap: widget.onEdit,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Transform.scale(
            scale: 1 - (_controller.value * 0.02),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: widget.item.isPaid 
                      ? const Color(0xFF10B981).withOpacity(0.3)
                      : const Color(0xFFF59E0B).withOpacity(0.3),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Linha principal - descrição e valor
                  Row(
                    children: [
                      // Ícone grande e colorido
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [bgColor, bgColor.withOpacity(0.8)],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: bgColor.withOpacity(0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Icon(
                          icon,
                          color: Colors.white,
                          size: 26,
                        ),
                      ),
                      
                      const SizedBox(width: 16),
                      
                      // Descrição e categoria
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.item.description,
                              style: const TextStyle(
                                color: Color(0xFF1F2937),
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.2,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            if (widget.item.categoryName != null)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: widget.item.categoryColor?.withOpacity(0.15) ?? 
                                         const Color(0xFF6366F1).withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  widget.item.categoryName!,
                                  style: TextStyle(
                                    color: widget.item.categoryColor ?? const Color(0xFF6366F1),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      
                      // Valor GRANDE
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '$sign R\$ ${widget.item.amount.toStringAsFixed(2)}',
                            style: TextStyle(
                              color: amountColor,
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: widget.item.isPaid 
                                    ? [const Color(0xFF10B981), const Color(0xFF059669)]
                                    : [const Color(0xFFF59E0B), const Color(0xFFD97706)],
                              ),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              widget.item.isPaid ? 'PAGO' : 'PENDENTE',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Linha inferior - data e ações
                  Row(
                    children: [
                      // Data e informações extras
                      Expanded(
                        child: Row(
                          children: [
                            Icon(
                              Icons.calendar_month,
                              size: 16,
                              color: const Color(0xFF6B7280),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              dateLabel,
                              style: const TextStyle(
                                color: Color(0xFF6B7280),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (widget.item.isRecurring) ...[
                              const SizedBox(width: 12),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF8B5CF6).withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'RECORRENTE',
                                  style: TextStyle(
                                    color: Color(0xFF8B5CF6),
                                    fontSize: 8,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      
                      // Botões de ação maiores
                      Row(
                        children: [
                          _FocusedActionButton(
                            icon: Icons.edit_outlined,
                            color: const Color(0xFF6366F1),
                            onPressed: widget.onEdit,
                          ),
                          const SizedBox(width: 8),
                          _FocusedActionButton(
                            icon: Icons.attach_file_outlined,
                            color: const Color(0xFF6B7280),
                            onPressed: widget.onViewAttachments,
                          ),
                          if (!isIncome) ...[
                            const SizedBox(width: 12),
                            _FocusedToggleButton(
                              value: widget.item.isPaid,
                              onChanged: widget.onTogglePaid,
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// Botões de ação
class _FocusedActionButton extends StatefulWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  const _FocusedActionButton({
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  @override
  State<_FocusedActionButton> createState() => _FocusedActionButtonState();
}

class _FocusedActionButtonState extends State<_FocusedActionButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) => _controller.reverse(),
      onTapCancel: () => _controller.reverse(),
      onTap: widget.onPressed,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Transform.scale(
            scale: 1 - (_controller.value * 0.1),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: widget.color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: widget.color.withOpacity(0.3),
                ),
              ),
              child: Icon(
                widget.icon,
                color: widget.color,
                size: 18,
              ),
            ),
          );
        },
      ),
    );
  }
}

// Toggle button
class _FocusedToggleButton extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _FocusedToggleButton({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Container(
        width: 44,
        height: 24,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: value 
                ? [const Color(0xFF10B981), const Color(0xFF059669)]
                : [const Color(0xFFE5E7EB), const Color(0xFFD1D5DB)],
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: (value ? const Color(0xFF10B981) : Colors.black)
                  .withOpacity(0.2),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 200),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 20,
            height: 20,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 4,
                  offset: Offset(0, 1),
                ),
              ],
            ),
            child: value 
                ? const Icon(
                    Icons.check,
                    size: 12,
                    color: Color(0xFF10B981),
                  )
                : null,
          ),
        ),
      ),
    );
  }
}

// Seção de filtros
class _CompactFiltersSection extends StatelessWidget {
  final String typeFilter;
  final String statusFilter;
  final String categoryFilter;
  final TextEditingController queryController;
  final List<String> availableCategories;
  final ValueChanged<String> onTypeChanged;
  final ValueChanged<String> onStatusChanged;
  final ValueChanged<String> onCategoryChanged;
  final VoidCallback onApply;
  final VoidCallback onClear;

  const _CompactFiltersSection({
    required this.typeFilter,
    required this.statusFilter,
    required this.categoryFilter,
    required this.queryController,
    required this.availableCategories,
    required this.onTypeChanged,
    required this.onStatusChanged,
    required this.onCategoryChanged,
    required this.onApply,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Campo de busca
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: TextField(
              controller: queryController,
              decoration: const InputDecoration(
                hintText: 'Buscar transação...',
                prefixIcon: Icon(Icons.search, color: Color(0xFF6366F1)),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          
          const SizedBox(height: 12),
          
          // Filtros
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _CompactFilterChip(
                label: typeFilter == 'all' ? 'Tipo' : (typeFilter == 'income' ? 'Receitas' : 'Despesas'),
                isActive: typeFilter != 'all',
                onTap: () => _showFilterDialog(context, 'Tipo', typeFilter, [
                  ('all', 'Todos'),
                  ('income', 'Receitas'),
                  ('expense', 'Despesas'),
                ], onTypeChanged),
              ),
              _CompactFilterChip(
                label: statusFilter == 'all' ? 'Status' : (statusFilter == 'paid' ? 'Pagos' : 'Pendentes'),
                isActive: statusFilter != 'all',
                onTap: () => _showFilterDialog(context, 'Status', statusFilter, [
                  ('all', 'Todos'),
                  ('paid', 'Pagos'),
                  ('pending', 'Pendentes'),
                ], onStatusChanged),
              ),
              if (availableCategories.isNotEmpty)
                _CompactFilterChip(
                  label: categoryFilter == 'all' ? 'Categoria' : categoryFilter,
                  isActive: categoryFilter != 'all',
                  onTap: () => _showFilterDialog(context, 'Categoria', categoryFilter, [
                    ('all', 'Todas'),
                    ...availableCategories.map((cat) => (cat, cat)),
                  ], onCategoryChanged),
                ),
            ],
          ),
          
          const SizedBox(height: 12),
          
          // Botões
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onApply,
                  icon: const Icon(Icons.search, size: 16),
                  label: const Text('Aplicar'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6366F1),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: onClear,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF3F4F6),
                  foregroundColor: const Color(0xFF6B7280),
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text('Limpar'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showFilterDialog(
    BuildContext context,
    String title,
    String currentValue,
    List<(String, String)> options,
    ValueChanged<String> onChanged,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Filtrar por $title',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              ...options.map((option) {
                final isSelected = option.$1 == currentValue;
                return ListTile(
                  title: Text(option.$2),
                  leading: isSelected 
                      ? const Icon(Icons.check_circle, color: Color(0xFF6366F1))
                      : const Icon(Icons.radio_button_unchecked, color: Color(0xFFD1D5DB)),
                  onTap: () {
                    onChanged(option.$1);
                    Navigator.pop(context);
                  },
                );
              }).toList(),
            ],
          ),
        );
      },
    );
  }
}

class _CompactFilterChip extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _CompactFilterChip({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          gradient: isActive
              ? const LinearGradient(
                  colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                )
              : null,
          color: isActive ? null : const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? Colors.white : const Color(0xFF6B7280),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

// Componentes auxiliares
class _CleanLoader extends StatelessWidget {
  const _CleanLoader();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: CircularProgressIndicator(
        color: Color(0xFF6366F1),
      ),
    );
  }
}

class _CleanEmptyState extends StatelessWidget {
  final bool hasFilters;
  final VoidCallback onClearFilters;

  const _CleanEmptyState({
    required this.hasFilters,
    required this.onClearFilters,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            hasFilters ? Icons.search_off : Icons.receipt_long,
            size: 64,
            color: const Color(0xFF6366F1).withOpacity(0.5),
          ),
          const SizedBox(height: 16),
          Text(
            hasFilters 
                ? 'Nenhuma transação encontrada'
                : 'Nenhuma transação neste mês',
            style: const TextStyle(
              color: Color(0xFF374151),
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (hasFilters) ...[
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: onClearFilters,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                foregroundColor: Colors.white,
              ),
              child: const Text('Limpar Filtros'),
            ),
          ],
        ],
      ),
    );
  }
}

class _ErrorWidget extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorWidget({
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 64, color: Color(0xFFEF4444)),
          const SizedBox(height: 16),
          Text(message, style: const TextStyle(fontSize: 16)),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: onRetry,
            child: const Text('Tentar Novamente'),
          ),
        ],
      ),
    );
  }
}

// Classes de dados
class _TransactionsData {
  final List<_TxItem> transactions;
  final List<String> categories;
  final double totalIncome;
  final double totalExpense;
  final double paidIncome;
  final double paidExpense;
  final double prevBalance;

  const _TransactionsData({
    required this.transactions,
    required this.categories,
    required this.totalIncome,
    required this.totalExpense,
    required this.paidIncome,
    required this.paidExpense,
    required this.prevBalance,
  });
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