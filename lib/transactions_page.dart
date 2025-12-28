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
  String _statusFilter = 'all'; // all, paid, pending
  String _categoryFilter = 'all';
  final _queryController = TextEditingController();

  bool _filtersExpanded = false;
  late AnimationController _animationController;
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

    return _TransactionsData(
      transactions: items,
      categories: categories.toList()..sort(),
      totalIncome: items.where((t) => t.type == 'income').fold(0.0, (sum, t) => sum + t.amount),
      totalExpense: items.where((t) => t.type == 'expense').fold(0.0, (sum, t) => sum + t.amount),
      paidIncome: items.where((t) => t.type == 'income' && t.isPaid).fold(0.0, (sum, t) => sum + t.amount),
      paidExpense: items.where((t) => t.type == 'expense' && t.isPaid).fold(0.0, (sum, t) => sum + t.amount),
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

    // Filtro por status de pagamento
    if (_statusFilter == 'paid') {
      filtered = filtered.where((item) => item.isPaid).toList();
    } else if (_statusFilter == 'pending') {
      filtered = filtered.where((item) => !item.isPaid).toList();
    }

    // Filtro por categoria
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
      final params = <String, String>{
        'user_id': widget.userId.toString(),
        if (widget.workspaceId != null) 'workspace_id': widget.workspaceId.toString(),
      };
      
      final uri = Uri.parse('$apiBaseUrl/gerenciamento-financeiro/api/transactions/$transactionId/set-paid')
          .replace(queryParameters: params);

      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'is_paid': newStatus}),
      );

      if (response.statusCode != 200) {
        throw Exception('Erro HTTP ${response.statusCode}');
      }

      final responseData = jsonDecode(response.body);
      if (responseData['success'] != true) {
        throw Exception(responseData['message'] ?? 'Erro desconhecido');
      }

      // Trigger refresh global para dashboard
      financeRefreshTick.value = financeRefreshTick.value + 1;

    } catch (e) {
      if (!mounted) return;
      // Reverter mudança otimista em caso de erro
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
            isPaid: !newStatus, // Reverter
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
    // Aguardar workspace_id estar definido
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
          child: Column(
            children: [
              // Header moderno
              _ModernHeader(
                year: _year,
                month: _month,
                onPrevMonth: _prevMonth,
                onNextMonth: _nextMonth,
                onToggleFilters: _toggleFilters,
                filtersExpanded: _filtersExpanded,
                hasFilters: _typeFilter != 'all' || _statusFilter != 'all' || 
                           _categoryFilter != 'all' || _queryController.text.isNotEmpty,
              ),

              // Filtros expansíveis com animação
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                height: _filtersExpanded ? null : 0,
                child: _filtersExpanded 
                    ? FadeTransition(
                        opacity: _fadeAnimation,
                        child: _ModernFiltersSection(
                          typeFilter: _typeFilter,
                          statusFilter: _statusFilter,
                          categoryFilter: _categoryFilter,
                          queryController: _queryController,
                          availableCategories: _availableCategories,
                          onTypeChanged: (value) {
                            setState(() {
                              _typeFilter = value;
                            });
                          },
                          onStatusChanged: (value) {
                            setState(() {
                              _statusFilter = value;
                            });
                          },
                          onCategoryChanged: (value) {
                            setState(() {
                              _categoryFilter = value;
                            });
                          },
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
                        return const Center(
                          child: CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00C9A7)),
                          ),
                        );
                      }
                      
                      if (snapshot.hasError) {
                        return Center(
                          child: _ErrorWidget(
                            message: 'Erro ao carregar transações',
                            onRetry: () {
                              setState(() {
                                _future = _fetch();
                              });
                            },
                          ),
                        );
                      }

                      final data = snapshot.data!;
                      _currentItems = data.transactions;
                      _availableCategories = data.categories;

                      // Aplicar filtros locais
                      final filteredItems = _applyLocalFilters(_currentItems);

                      return Column(
                        children: [
                          // Cards de resumo
                          _SummaryCards(data: data),
                          const SizedBox(height: 16),

                          // Lista de transações
                          Expanded(
                            child: filteredItems.isEmpty
                                ? _EmptyState(
                                    hasFilters: _typeFilter != 'all' || 
                                               _statusFilter != 'all' || 
                                               _categoryFilter != 'all' || 
                                               _queryController.text.isNotEmpty,
                                    onClearFilters: _clearFilters,
                                  )
                                : _ModernTransactionsList(
                                    items: filteredItems,
                                    onEdit: _editTransaction,
                                    onViewAttachments: _viewAttachments,
                                    onTogglePaid: _setPaid,
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
      ),
    );
  }
}

// Header moderno com navegação de mês
class _ModernHeader extends StatelessWidget {
  final int year;
  final int month;
  final VoidCallback onPrevMonth;
  final VoidCallback onNextMonth;
  final VoidCallback onToggleFilters;
  final bool filtersExpanded;
  final bool hasFilters;

  const _ModernHeader({
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
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Título e botão de filtros
          Row(
            children: [
              const Text(
                'Transações',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Stack(
                children: [
                  IconButton(
                    onPressed: onToggleFilters,
                    icon: AnimatedRotation(
                      turns: filtersExpanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 300),
                      child: Icon(
                        filtersExpanded ? Icons.filter_list_off : Icons.filter_list,
                        color: hasFilters ? const Color(0xFF00C9A7) : Colors.white70,
                      ),
                    ),
                  ),
                  if (hasFilters)
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Color(0xFF00C9A7),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // Navegação de mês
          Container(
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
          ),
        ],
      ),
    );
  }
}

// Seção de filtros moderna
class _ModernFiltersSection extends StatelessWidget {
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

  const _ModernFiltersSection({
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
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Busca
          TextField(
            controller: queryController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Buscar por descrição...',
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.6)),
              prefixIcon: const Icon(Icons.search, color: Color(0xFF00C9A7)),
              filled: true,
              fillColor: Colors.white.withOpacity(0.06),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Filtros em chips
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _FilterChip(
                label: 'Tipo',
                value: typeFilter,
                options: const [
                  ('all', 'Todos'),
                  ('income', 'Receitas'),
                  ('expense', 'Despesas'),
                ],
                onChanged: onTypeChanged,
              ),
              _FilterChip(
                label: 'Status',
                value: statusFilter,
                options: const [
                  ('all', 'Todos'),
                  ('paid', 'Pagos'),
                  ('pending', 'Pendentes'),
                ],
                onChanged: onStatusChanged,
              ),
              if (availableCategories.isNotEmpty)
                _FilterChip(
                  label: 'Categoria',
                  value: categoryFilter,
                  options: [
                    ('all', 'Todas'),
                    ...availableCategories.map((cat) => (cat, cat)),
                  ],
                  onChanged: onCategoryChanged,
                ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // Botões de ação
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onApply,
                  icon: const Icon(Icons.search),
                  label: const Text('Aplicar'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00C9A7),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: onClear,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white.withOpacity(0.1),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                ),
                child: const Text('Limpar'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// Chip de filtro personalizado
class _FilterChip extends StatelessWidget {
  final String label;
  final String value;
  final List<(String, String)> options;
  final ValueChanged<String> onChanged;

  const _FilterChip({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        showModalBottomSheet(
          context: context,
          backgroundColor: const Color(0xFF203A43),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          builder: (context) {
            return Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Filtrar por $label',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ...options.map((option) {
                    final isSelected = option.$1 == value;
                    return ListTile(
                      title: Text(
                        option.$2,
                        style: TextStyle(
                          color: isSelected ? const Color(0xFF00C9A7) : Colors.white,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                      leading: isSelected 
                          ? const Icon(Icons.check, color: Color(0xFF00C9A7))
                          : null,
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
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: value != 'all' 
              ? const Color(0xFF00C9A7).withOpacity(0.2)
              : Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: value != 'all' 
                ? const Color(0xFF00C9A7)
                : Colors.white.withOpacity(0.2),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$label: ${options.firstWhere((opt) => opt.$1 == value).$2}',
              style: TextStyle(
                color: value != 'all' ? const Color(0xFF00C9A7) : Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.arrow_drop_down,
              color: value != 'all' ? const Color(0xFF00C9A7) : Colors.white70,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
}

// Cards de resumo
class _SummaryCards extends StatelessWidget {
  final _TransactionsData data;

  const _SummaryCards({required this.data});

  @override
  Widget build(BuildContext context) {
    final balance = data.paidIncome - data.paidExpense;
    final balanceColor = balance >= 0 ? const Color(0xFF10B981) : const Color(0xFFEF4444);

    return Row(
      children: [
        Expanded(
          child: _SummaryCard(
            title: 'Receitas',
            total: data.totalIncome,
            paid: data.paidIncome,
            color: const Color(0xFF10B981),
            icon: Icons.trending_up,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _SummaryCard(
            title: 'Despesas',
            total: data.totalExpense,
            paid: data.paidExpense,
            color: const Color(0xFFEF4444),
            icon: Icons.trending_down,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: balanceColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: balanceColor.withOpacity(0.3)),
            ),
            child: Column(
              children: [
                Icon(
                  balance >= 0 ? Icons.account_balance_wallet : Icons.warning,
                  color: balanceColor,
                  size: 20,
                ),
                const SizedBox(height: 4),
                Text(
                  'Saldo',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 10,
                  ),
                ),
                Text(
                  'R\$ ${balance.toStringAsFixed(2)}',
                  style: TextStyle(
                    color: balanceColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String title;
  final double total;
  final double paid;
  final Color color;
  final IconData icon;

  const _SummaryCard({
    required this.title,
    required this.total,
    required this.paid,
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 4),
              Text(
                title,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.8),
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'R\$ ${total.toStringAsFixed(2)}',
            style: TextStyle(
              color: color,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            'Pago: R\$ ${paid.toStringAsFixed(2)}',
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 9,
            ),
          ),
        ],
      ),
    );
  }
}

// Lista moderna de transações
class _ModernTransactionsList extends StatelessWidget {
  final List<_TxItem> items;
  final void Function(int) onEdit;
  final void Function(int, String) onViewAttachments;
  final void Function(int, bool) onTogglePaid;

  const _ModernTransactionsList({
    required this.items,
    required this.onEdit,
    required this.onViewAttachments,
    required this.onTogglePaid,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = items[index];
        return _ModernTransactionCard(
          item: item,
          onEdit: () => onEdit(item.id),
          onViewAttachments: () => onViewAttachments(item.id, item.description),
          onTogglePaid: (value) => onTogglePaid(item.id, value),
        );
      },
    );
  }
}

// Card moderno de transação
class _ModernTransactionCard extends StatelessWidget {
  final _TxItem item;
  final VoidCallback onEdit;
  final VoidCallback onViewAttachments;
  final ValueChanged<bool> onTogglePaid;

  const _ModernTransactionCard({
    required this.item,
    required this.onEdit,
    required this.onViewAttachments,
    required this.onTogglePaid,
  });

  @override
  Widget build(BuildContext context) {
    final isIncome = item.type == 'income';
    final amountColor = isIncome ? const Color(0xFF10B981) : const Color(0xFFEF4444);
    final icon = isIncome ? Icons.arrow_downward : Icons.arrow_upward;
    final sign = isIncome ? '+' : '-';
    
    final dateLabel = item.date != null
        ? '${item.date!.day.toString().padLeft(2, '0')}/${item.date!.month.toString().padLeft(2, '0')}'
        : '';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
      ),
      child: Column(
        children: [
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: amountColor.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: amountColor, size: 20),
            ),
            title: Text(
              item.description,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (item.categoryName != null) ...[
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: item.categoryColor ?? Colors.grey,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        item.categoryName!,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.6),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
                if (dateLabel.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    dateLabel,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
            trailing: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$sign R\$ ${item.amount.toStringAsFixed(2)}',
                  style: TextStyle(
                    color: amountColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: item.isPaid 
                        ? const Color(0xFF10B981).withOpacity(0.2)
                        : Colors.orange.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    item.isPaid ? 'Pago' : 'Pendente',
                    style: TextStyle(
                      color: item.isPaid ? const Color(0xFF10B981) : Colors.orange,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            onTap: onEdit,
          ),
          
          // Ações
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                if (!isIncome) // Switch só para despesas
                  Expanded(
                    child: Row(
                      children: [
                        Switch(
                          value: item.isPaid,
                          onChanged: onTogglePaid,
                          activeColor: const Color(0xFF10B981),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          item.isPaid ? 'Pago' : 'Marcar como pago',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.7),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (isIncome) const Spacer(),
                
                // Botões de ação
                IconButton(
                  onPressed: onViewAttachments,
                  icon: const Icon(Icons.attach_file, size: 18),
                  color: Colors.white.withOpacity(0.6),
                  tooltip: 'Anexos',
                ),
                IconButton(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit, size: 18),
                  color: const Color(0xFF00C9A7),
                  tooltip: 'Editar',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Estado vazio
class _EmptyState extends StatelessWidget {
  final bool hasFilters;
  final VoidCallback onClearFilters;

  const _EmptyState({
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
            hasFilters ? Icons.filter_list_off : Icons.receipt_long,
            size: 64,
            color: Colors.white.withOpacity(0.3),
          ),
          const SizedBox(height: 16),
          Text(
            hasFilters 
                ? 'Nenhuma transação encontrada'
                : 'Nenhuma transação neste mês',
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (hasFilters) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: onClearFilters,
              child: const Text(
                'Limpar filtros',
                style: TextStyle(color: Color(0xFF00C9A7)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// Widget de erro
class _ErrorWidget extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorWidget({
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.error_outline,
          size: 64,
          color: Colors.red.withOpacity(0.7),
        ),
        const SizedBox(height: 16),
        Text(
          message,
          style: TextStyle(
            color: Colors.white.withOpacity(0.7),
            fontSize: 16,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: onRetry,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF00C9A7),
            foregroundColor: Colors.white,
          ),
          child: const Text('Tentar novamente'),
        ),
      ],
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

  const _TransactionsData({
    required this.transactions,
    required this.categories,
    required this.totalIncome,
    required this.totalExpense,
    required this.paidIncome,
    required this.paidExpense,
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