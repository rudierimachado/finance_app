import 'dart:convert';
import 'dart:ui';

import 'package:intl/intl.dart';
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
  late AnimationController _listAnimationController;

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
    
    _listAnimationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
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
    _listAnimationController.dispose();
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

      final curInst = (e['current_installment'] as num?)?.toInt();
      final totInst = (e['total_installments'] as num?)?.toInt();

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
        currentInstallment: curInst,
        totalInstallments: totInst,
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

  Future<void> _deleteTransaction(int transactionId, bool isRecurring) async {
    String? scope;
    if (isRecurring) {
      scope = await showDialog<String>(
        context: context,
        builder: (context) => _buildDeleteDialog(isRecurring: true),
      );
      if (scope == null) return;
    } else {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => _buildDeleteDialog(isRecurring: false),
      );
      if (confirmed != true) return;
    }

    try {
      Uri buildUri(String prefix) => Uri.parse(
        '$apiBaseUrl$prefix/api/transactions/$transactionId?user_id=${widget.userId}${scope != null ? '&scope=$scope' : ''}',
      );

      var uri = buildUri('/gerenciamento-financeiro');
      var resp = await http.delete(uri).timeout(const Duration(seconds: 10));

      if (resp.statusCode == 404) {
        uri = buildUri('');
        resp = await http.delete(uri).timeout(const Duration(seconds: 10));
      }

      final data = jsonDecode(resp.body);
      if (resp.statusCode == 200 && data['success'] == true) {
        if (!mounted) return;
        _showSnackBar('Transação excluída com sucesso!', isError: false);
        financeRefreshTick.value = financeRefreshTick.value + 1;
      } else {
        throw Exception(data['message'] ?? 'Erro ao excluir');
      }
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Falha ao excluir: $e', isError: true);
    }
  }

  Future<void> _setPaid(int transactionId, bool newStatus) async {
    if (transactionId <= 0) {
      if (!mounted) return;
      _showSnackBar('Erro: transação inválida', isError: true);
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

      _showSnackBar('Erro ao alterar status: $e', isError: true);
    }
  }

  Widget _buildDeleteDialog({required bool isRecurring}) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E2E),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 30,
              offset: const Offset(0, 15),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFF4757).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.delete_forever_rounded,
                color: Color(0xFFFF4757),
                size: 48,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              isRecurring ? 'Excluir Recorrência' : 'Excluir Transação',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              isRecurring
                  ? 'Essa transação é recorrente. O que você deseja excluir?'
                  : 'Tem certeza que deseja excluir esta transação?',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 24),
            if (isRecurring) ...[
              _DialogButton(
                label: 'Só esta',
                icon: Icons.event_rounded,
                color: const Color(0xFF00D9FF),
                onPressed: () => Navigator.of(context).pop('single'),
              ),
              const SizedBox(height: 12),
              _DialogButton(
                label: 'Esta e futuras',
                icon: Icons.event_repeat_rounded,
                color: const Color(0xFFFFB800),
                onPressed: () => Navigator.of(context).pop('future'),
              ),
              const SizedBox(height: 12),
              _DialogButton(
                label: 'Todas',
                icon: Icons.delete_sweep_rounded,
                color: const Color(0xFFFF4757),
                onPressed: () => Navigator.of(context).pop('all'),
              ),
            ] else ...[
              Row(
                children: [
                  Expanded(
                    child: _DialogButton(
                      label: 'Cancelar',
                      icon: Icons.close_rounded,
                      color: Colors.white.withOpacity(0.3),
                      onPressed: () => Navigator.of(context).pop(false),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _DialogButton(
                      label: 'Excluir',
                      icon: Icons.delete_rounded,
                      color: const Color(0xFFFF4757),
                      onPressed: () => Navigator.of(context).pop(true),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showSnackBar(String message, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
              color: Colors.white,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        backgroundColor: isError ? const Color(0xFFFF4757) : const Color(0xFF00E676),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.workspaceId == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF0F2027),
        body: Center(child: CircularProgressIndicator(color: Color(0xFF00C9A7))),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0F2027),
      body: SafeArea(
        child: Column(
          children: [
            // Header Ultra Clean
            _UltraCleanHeader(
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
            if (_filtersExpanded)
              _UltraFiltersPanel(
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
                animation: _animationController,
              ),

            // Conteúdo
            Expanded(
              child: FutureBuilder<_TransactionsData>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const _UltraLoader();
                  }
                  
                  if (snapshot.hasError) {
                    return _UltraError(
                      message: 'Erro ao carregar transações',
                      onRetry: () => setState(() => _future = _fetch()),
                    );
                  }

                  final data = snapshot.data!;
                  _currentItems = data.transactions;
                  _availableCategories = data.categories;

                  final filteredItems = _applyLocalFilters(_currentItems);

                  _listAnimationController.forward(from: 0);

                  return Column(
                    children: [
                      // Resumo Financeiro Inline
                      _UltraFinancialSummary(data: data),
                      
                      // Lista de Transações
                      Expanded(
                        child: filteredItems.isEmpty
                            ? _UltraEmptyState(
                                hasFilters: _typeFilter != 'all' || 
                                           _statusFilter != 'all' || 
                                           _categoryFilter != 'all' || 
                                           _queryController.text.isNotEmpty,
                                onClearFilters: _clearFilters,
                              )
                            : _UltraTransactionsList(
                                items: filteredItems,
                                onEdit: _editTransaction,
                                onDelete: _deleteTransaction,
                                onTogglePaid: _setPaid,
                                animation: _listAnimationController,
                              ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== HEADER ULTRA CLEAN ====================
class _UltraCleanHeader extends StatelessWidget {
  final int year;
  final int month;
  final VoidCallback onPrevMonth;
  final VoidCallback onNextMonth;
  final VoidCallback onToggleFilters;
  final bool filtersExpanded;
  final bool hasFilters;

  const _UltraCleanHeader({
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
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Row(
        children: [
          // Navegação de mês minimalista
          _NavButton(
            icon: Icons.chevron_left_rounded,
            onPressed: onPrevMonth,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  monthNames[month].toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                  ),
                ),
                Text(
                  year.toString(),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          _NavButton(
            icon: Icons.chevron_right_rounded,
            onPressed: onNextMonth,
          ),
          const SizedBox(width: 12),
          // Botão de filtros
          _FilterButton(
            onPressed: onToggleFilters,
            isActive: filtersExpanded,
            hasFilters: hasFilters,
          ),
        ],
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;

  const _NavButton({
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.white.withOpacity(0.1),
            ),
          ),
          child: Icon(icon, color: Colors.white, size: 24),
        ),
      ),
    );
  }
}

class _FilterButton extends StatelessWidget {
  final VoidCallback onPressed;
  final bool isActive;
  final bool hasFilters;

  const _FilterButton({
    required this.onPressed,
    required this.isActive,
    required this.hasFilters,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: hasFilters 
                ? const Color(0xFF00C9A7).withOpacity(0.2)
                : Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: hasFilters 
                  ? const Color(0xFF00C9A7)
                  : Colors.white.withOpacity(0.1),
            ),
          ),
          child: Stack(
            children: [
              Center(
                child: AnimatedRotation(
                  turns: isActive ? 0.125 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    isActive ? Icons.close_rounded : Icons.tune_rounded,
                    color: hasFilters ? const Color(0xFF00C9A7) : Colors.white,
                    size: 20,
                  ),
                ),
              ),
              if (hasFilters && !isActive)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Color(0xFFFF4757),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ==================== PAINEL DE FILTROS ====================
class _UltraFiltersPanel extends StatelessWidget {
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
  final AnimationController animation;

  const _UltraFiltersPanel({
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
    required this.animation,
  });

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, -0.1),
          end: Offset.zero,
        ).animate(CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        )),
        child: Container(
          margin: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E2E),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.white.withOpacity(0.1),
            ),
          ),
          child: Column(
            children: [
              // Campo de busca
              TextField(
                controller: queryController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Buscar transação...',
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                  prefixIcon: Icon(Icons.search_rounded, color: Colors.white.withOpacity(0.5)),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.05),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
              ),
              const SizedBox(height: 16),
              // Chips de filtro
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _FilterChip(
                    label: _getFilterLabel('Tipo', typeFilter, {'all': 'Todos', 'income': 'Receitas', 'expense': 'Despesas'}),
                    isActive: typeFilter != 'all',
                    onTap: () => _showFilterSheet(
                      context,
                      'Tipo',
                      typeFilter,
                      [
                        ('all', 'Todos', Icons.all_inclusive_rounded),
                        ('income', 'Receitas', Icons.arrow_downward_rounded),
                        ('expense', 'Despesas', Icons.arrow_upward_rounded),
                      ],
                      onTypeChanged,
                    ),
                  ),
                  _FilterChip(
                    label: _getFilterLabel('Status', statusFilter, {'all': 'Todos', 'paid': 'Pagos', 'pending': 'Pendentes'}),
                    isActive: statusFilter != 'all',
                    onTap: () => _showFilterSheet(
                      context,
                      'Status',
                      statusFilter,
                      [
                        ('all', 'Todos', Icons.all_inclusive_rounded),
                        ('paid', 'Pagos', Icons.check_circle_rounded),
                        ('pending', 'Pendentes', Icons.schedule_rounded),
                      ],
                      onStatusChanged,
                    ),
                  ),
                  if (availableCategories.isNotEmpty)
                    _FilterChip(
                      label: categoryFilter == 'all' ? 'Categoria' : categoryFilter,
                      isActive: categoryFilter != 'all',
                      onTap: () => _showFilterSheet(
                        context,
                        'Categoria',
                        categoryFilter,
                        [
                          ('all', 'Todas', Icons.all_inclusive_rounded),
                          ...availableCategories.map((cat) => (cat, cat, Icons.label_rounded)),
                        ],
                        onCategoryChanged,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              // Botões
              Row(
                children: [
                  Expanded(
                    child: _ActionButton(
                      label: 'Aplicar',
                      icon: Icons.check_rounded,
                      color: const Color(0xFF00C9A7),
                      onPressed: onApply,
                    ),
                  ),
                  const SizedBox(width: 12),
                  _ActionButton(
                    label: 'Limpar',
                    icon: Icons.clear_all_rounded,
                    color: Colors.white.withOpacity(0.1),
                    textColor: Colors.white.withOpacity(0.5),
                    onPressed: onClear,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getFilterLabel(String prefix, String value, Map<String, String> labels) {
    return value == 'all' ? prefix : (labels[value] ?? prefix);
  }

  void _showFilterSheet(
    BuildContext context,
    String title,
    String currentValue,
    List<(String, String, IconData)> options,
    ValueChanged<String> onChanged,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF0F2027),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 20),
              ...options.map((option) {
                final isSelected = option.$1 == currentValue;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        onChanged(option.$1);
                        Navigator.pop(context);
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isSelected 
                              ? const Color(0xFF00C9A7).withOpacity(0.2)
                              : Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected 
                                ? const Color(0xFF00C9A7)
                                : Colors.transparent,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(option.$3, color: isSelected ? const Color(0xFF00C9A7) : Colors.white.withOpacity(0.5)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                option.$2,
                                style: TextStyle(
                                  color: isSelected ? const Color(0xFF00C9A7) : Colors.white,
                                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                                ),
                              ),
                            ),
                            if (isSelected)
                              const Icon(Icons.check_circle_rounded, color: Color(0xFF00C9A7)),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ],
          ),
        );
      },
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: isActive 
                ? const Color(0xFF00C9A7).withOpacity(0.2)
                : Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isActive 
                  ? const Color(0xFF00C9A7)
                  : Colors.white.withOpacity(0.1),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isActive ? const Color(0xFF00C9A7) : Colors.white.withOpacity(0.7),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

// ==================== RESUMO FINANCEIRO ====================
class _UltraFinancialSummary extends StatelessWidget {
  final _TransactionsData data;

  const _UltraFinancialSummary({required this.data});

  @override
  Widget build(BuildContext context) {
    // Cálculo do Saldo Total:
    // Saldo Anterior (Acumulado de meses passados) + (Receitas do mês - Despesas Pagas do mês)
    final totalBalance = data.prevBalance + (data.totalIncome - data.paidExpense);
    final pendingExpense = data.totalExpense - data.paidExpense;

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: totalBalance >= 0
              ? [const Color(0xFF00C9A7), const Color(0xFF008B7D)]
              : [const Color(0xFFFF4757), const Color(0xFFE63946)],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: (totalBalance >= 0 ? const Color(0xFF00C9A7) : const Color(0xFFFF4757)).withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Saldo Total',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.8),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'R\$ ${totalBalance.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -1,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  totalBalance >= 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            height: 1,
            color: Colors.white.withOpacity(0.2),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _SummaryMetric(
                  label: 'Receitas',
                  value: data.totalIncome,
                  icon: Icons.arrow_downward_rounded,
                  color: const Color(0xFF00E676),
                ),
              ),
              Container(width: 1, height: 40, color: Colors.white.withOpacity(0.2)),
              Expanded(
                child: _SummaryMetric(
                  label: 'Despesas Pagas',
                  value: data.paidExpense,
                  icon: Icons.arrow_upward_rounded,
                  color: const Color(0xFFFFB800),
                ),
              ),
              Container(width: 1, height: 40, color: Colors.white.withOpacity(0.2)),
              Expanded(
                child: _SummaryMetric(
                  label: 'A Pagar',
                  value: pendingExpense,
                  icon: Icons.schedule_rounded,
                  color: const Color(0xFFFF4757),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  final String label;
  final double value;
  final IconData icon;
  final Color color;

  const _SummaryMetric({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: Colors.white.withOpacity(0.8), size: 20),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.8),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'R\$ ${value.toStringAsFixed(0)}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

// ==================== LISTA DE TRANSAÇÕES ====================
class _UltraTransactionsList extends StatelessWidget {
  final List<_TxItem> items;
  final void Function(int) onEdit;
  final void Function(int, bool) onDelete;
  final void Function(int, bool) onTogglePaid;
  final AnimationController animation;

  const _UltraTransactionsList({
    required this.items,
    required this.onEdit,
    required this.onDelete,
    required this.onTogglePaid,
    required this.animation,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      physics: const BouncingScrollPhysics(),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        return _UltraTransactionCard(
          item: items[index],
          index: index,
          onEdit: () => onEdit(items[index].id),
          onDelete: () => onDelete(items[index].id, items[index].isRecurring),
          onTogglePaid: (value) => onTogglePaid(items[index].id, value),
          animation: animation,
        );
      },
    );
  }
}

// ==================== CARD DE TRANSAÇÃO ====================
class _UltraTransactionCard extends StatefulWidget {
  final _TxItem item;
  final int index;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<bool> onTogglePaid;
  final AnimationController animation;

  const _UltraTransactionCard({
    required this.item,
    required this.index,
    required this.onEdit,
    required this.onDelete,
    required this.onTogglePaid,
    required this.animation,
  });

  @override
  State<_UltraTransactionCard> createState() => _UltraTransactionCardState();
}

class _UltraTransactionCardState extends State<_UltraTransactionCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _pressController;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _pressController = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _pressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isIncome = widget.item.type == 'income';
    final accentColor = isIncome ? const Color(0xFF00E676) : const Color(0xFFFF4757);
    final dateLabel = widget.item.date != null 
        ? DateFormat('dd/MM/yyyy').format(widget.item.date!)
        : 'Sem data';

    // Animação de entrada escalonada
    final delay = (widget.index * 0.05).clamp(0.0, 0.5);
    final slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: widget.animation,
      curve: Interval(delay, 1.0, curve: Curves.easeOutCubic),
    ));

    final fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: widget.animation,
      curve: Interval(delay, 1.0, curve: Curves.easeOut),
    ));

    return FadeTransition(
      opacity: fadeAnimation,
      child: SlideTransition(
        position: slideAnimation,
        child: GestureDetector(
          onTapDown: (_) {
            setState(() => _isPressed = true);
            _pressController.forward();
          },
          onTapUp: (_) {
            setState(() => _isPressed = false);
            _pressController.reverse();
            widget.onEdit();
          },
          onTapCancel: () {
            setState(() => _isPressed = false);
            _pressController.reverse();
          },
          child: AnimatedScale(
            scale: _isPressed ? 0.97 : 1.0,
            duration: const Duration(milliseconds: 100),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E2E),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: widget.item.isPaid 
                      ? Colors.white.withOpacity(0.05)
                      : accentColor.withOpacity(0.2),
                ),
                boxShadow: [
                  if (!widget.item.isPaid)
                    BoxShadow(
                      color: accentColor.withOpacity(0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // Ícone
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: accentColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          isIncome ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                          color: accentColor,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.item.description,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                if (widget.item.categoryName != null) ...[
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: accentColor.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      widget.item.categoryName!,
                                      style: TextStyle(
                                        color: accentColor,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                ],
                                Text(
                                  dateLabel,
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.4),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      // Valor
                      Text(
                        '${isIncome ? '+' : '-'} R\$ ${widget.item.amount.toStringAsFixed(2)}',
                        style: TextStyle(
                          color: accentColor,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      // Status com Toggle Button
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: widget.item.isPaid 
                                ? const Color(0xFF00E676).withOpacity(0.1)
                                : const Color(0xFFFFB800).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                widget.item.isPaid ? Icons.check_circle_rounded : Icons.schedule_rounded,
                                color: widget.item.isPaid ? const Color(0xFF00E676) : const Color(0xFFFFB800),
                                size: 16,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  widget.item.isPaid ? 'PAGO' : 'PENDENTE',
                                  style: TextStyle(
                                    color: widget.item.isPaid ? const Color(0xFF00E676) : const Color(0xFFFFB800),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              Transform.scale(
                                scale: 0.8,
                                child: Switch(
                                  value: widget.item.isPaid,
                                  onChanged: widget.onTogglePaid,
                                  activeColor: const Color(0xFF00E676),
                                  activeTrackColor: const Color(0xFF00E676).withOpacity(0.3),
                                  inactiveThumbColor: const Color(0xFFFFB800),
                                  inactiveTrackColor: const Color(0xFFFFB800).withOpacity(0.3),
                                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Botão editar
                      _QuickActionButton(
                        icon: Icons.edit_rounded,
                        color: const Color(0xFF00C9A7),
                        onPressed: widget.onEdit,
                      ),
                      const SizedBox(width: 8),
                      // Botão excluir
                      _QuickActionButton(
                        icon: Icons.delete_rounded,
                        color: const Color(0xFFFF4757),
                        onPressed: widget.onDelete,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  const _QuickActionButton({
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
      ),
    );
  }
}

// ==================== COMPONENTES AUXILIARES ====================
class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final Color? textColor;
  final VoidCallback onPressed;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    this.textColor,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: textColor ?? Colors.white, size: 18),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: textColor ?? Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DialogButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  const _DialogButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 12),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UltraLoader extends StatelessWidget {
  const _UltraLoader();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: CircularProgressIndicator(
        color: Color(0xFF00C9A7),
        strokeWidth: 3,
      ),
    );
  }
}

class _UltraEmptyState extends StatelessWidget {
  final bool hasFilters;
  final VoidCallback onClearFilters;

  const _UltraEmptyState({
    required this.hasFilters,
    required this.onClearFilters,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF00C9A7).withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              hasFilters ? Icons.search_off_rounded : Icons.receipt_long_rounded,
              size: 64,
              color: const Color(0xFF00C9A7),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            hasFilters ? 'Nenhuma transação encontrada' : 'Nenhuma transação',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            hasFilters ? 'Tente ajustar os filtros' : 'Adicione sua primeira transação',
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 14,
            ),
          ),
          if (hasFilters) ...[
            const SizedBox(height: 24),
            _ActionButton(
              label: 'Limpar Filtros',
              icon: Icons.clear_all_rounded,
              color: const Color(0xFF00C9A7),
              onPressed: onClearFilters,
            ),
          ],
        ],
      ),
    );
  }
}

class _UltraError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _UltraError({
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFFFF4757).withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.error_outline_rounded,
              size: 64,
              color: Color(0xFFFF4757),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            message,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 24),
          _ActionButton(
            label: 'Tentar Novamente',
            icon: Icons.refresh_rounded,
            color: const Color(0xFFFF4757),
            onPressed: onRetry,
          ),
        ],
      ),
    );
  }
}

// ==================== CLASSES DE DADOS ====================
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
  final int? currentInstallment;
  final int? totalInstallments;

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
    this.currentInstallment,
    this.totalInstallments,
  });
}