import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'config.dart';

class PlanningPage extends StatefulWidget {
  final int userId;
  final int? workspaceId;

  const PlanningPage({
    super.key,
    required this.userId,
    this.workspaceId,
  });

  @override
  State<PlanningPage> createState() => _PlanningPageState();
}

class _PlanningPageState extends State<PlanningPage> {
  late Future<_PlanningData> _future;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  @override
  void didUpdateWidget(covariant PlanningPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workspaceId != widget.workspaceId) {
      setState(() {
        _future = _fetch();
      });
    }
  }

  Future<_PlanningData> _fetch() async {
    final ws = widget.workspaceId;
    if (ws == null) {
      return const _PlanningData(budgets: <_BudgetItem>[], pots: <_PotItem>[]);
    }

    final now = DateTime.now();

    final budgetsUri = Uri.parse('$apiBaseUrl/gerenciamento-financeiro/api/budgets').replace(
      queryParameters: {
        'user_id': widget.userId.toString(),
        'workspace_id': ws.toString(),
        'period': 'monthly',
        'year': now.year.toString(),
        'month': now.month.toString(),
      },
    );

    final potsUri = Uri.parse('$apiBaseUrl/gerenciamento-financeiro/api/savings-pots').replace(
      queryParameters: {
        'user_id': widget.userId.toString(),
        'workspace_id': ws.toString(),
      },
    );

    final budgetsResp = await http.get(budgetsUri, headers: {'Content-Type': 'application/json'});
    final potsResp = await http.get(potsUri, headers: {'Content-Type': 'application/json'});

    final budgetsJson = jsonDecode(budgetsResp.body) as Map<String, dynamic>;
    final potsJson = jsonDecode(potsResp.body) as Map<String, dynamic>;

    if (budgetsResp.statusCode != 200 || budgetsJson['success'] != true) {
      throw Exception(budgetsJson['message']?.toString() ?? 'Falha ao carregar orçamentos');
    }
    if (potsResp.statusCode != 200 || potsJson['success'] != true) {
      throw Exception(potsJson['message']?.toString() ?? 'Falha ao carregar cofrinhos/metas');
    }

    final budgetsRaw = (budgetsJson['budgets'] as List<dynamic>? ?? const <dynamic>[]);
    final budgets = <_BudgetItem>[];
    for (final e in budgetsRaw) {
      if (e is! Map) continue;
      budgets.add(_BudgetItem.fromJson(e.cast<String, dynamic>()));
    }

    final potsRaw = (potsJson['pots'] as List<dynamic>? ?? const <dynamic>[]);
    final pots = <_PotItem>[];
    for (final e in potsRaw) {
      if (e is! Map) continue;
      pots.add(_PotItem.fromJson(e.cast<String, dynamic>()));
    }

    return _PlanningData(budgets: budgets, pots: pots);
  }

  Future<void> _openCreateBudget() async {
    final ws = widget.workspaceId;
    if (ws == null) return;

    final created = await showDialog<bool>(
      context: context,
      builder: (_) => _CreateBudgetDialog(userId: widget.userId, workspaceId: ws),
    );

    if (created == true && mounted) {
      setState(() {
        _future = _fetch();
      });
    }
  }

  Future<void> _openEditBudget(_BudgetItem budget) async {
    final ws = widget.workspaceId;
    if (ws == null) return;

    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _EditBudgetDialog(
        userId: widget.userId,
        workspaceId: ws,
        budget: budget,
      ),
    );

    if (changed == true && mounted) {
      setState(() {
        _future = _fetch();
      });
      financeRefreshTick.value = financeRefreshTick.value + 1;
    }
  }

  Future<void> _confirmDeleteBudget(_BudgetItem budget) async {
    final ws = widget.workspaceId;
    if (ws == null) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0F2027),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: Colors.white.withOpacity(0.10)),
        ),
        title: const Text('Excluir orçamento', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
        content: Text(
          'Deseja excluir o orçamento desta categoria?',
          style: TextStyle(color: Colors.white.withOpacity(0.80)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444), foregroundColor: Colors.white),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (ok != true || !mounted) return;

    final uri = Uri.parse('$apiBaseUrl/gerenciamento-financeiro/api/budgets/${budget.id}').replace(
      queryParameters: {
        'user_id': widget.userId.toString(),
        'workspace_id': ws.toString(),
      },
    );

    try {
      final resp = await http.delete(uri, headers: {'Content-Type': 'application/json'});
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (resp.statusCode == 200 && data['success'] == true) {
        if (!mounted) return;
        setState(() {
          _future = _fetch();
        });
        financeRefreshTick.value = financeRefreshTick.value + 1;
        return;
      }

      final msg = data['message']?.toString() ?? 'Erro ao excluir orçamento';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    }
  }

  Future<void> _openContribute(_PotItem pot) async {
    final ws = widget.workspaceId;
    if (ws == null) return;

    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _ContributeDialog(
        userId: widget.userId,
        workspaceId: ws,
        pot: pot,
      ),
    );

    if (changed == true && mounted) {
      setState(() {
        _future = _fetch();
      });
      financeRefreshTick.value = financeRefreshTick.value + 1;
    }
  }

  Future<void> _confirmDeletePot(_PotItem pot) async {
    final ws = widget.workspaceId;
    if (ws == null) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0F2027),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: Colors.white.withOpacity(0.10)),
        ),
        title: const Text('Excluir', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
        content: Text(
          'Deseja excluir "${pot.name}"?',
          style: TextStyle(color: Colors.white.withOpacity(0.80)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444), foregroundColor: Colors.white),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (ok != true || !mounted) return;

    final uri = Uri.parse('$apiBaseUrl/gerenciamento-financeiro/api/savings-pots/${pot.id}').replace(
      queryParameters: {
        'user_id': widget.userId.toString(),
        'workspace_id': ws.toString(),
      },
    );

    try {
      final resp = await http.delete(uri, headers: {'Content-Type': 'application/json'});
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (resp.statusCode == 200 && data['success'] == true) {
        if (!mounted) return;
        setState(() {
          _future = _fetch();
        });
        financeRefreshTick.value = financeRefreshTick.value + 1;
        return;
      }

      final msg = data['message']?.toString() ?? 'Erro ao excluir';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    }
  }

  Future<void> _openCreatePot({required String kind}) async {
    final ws = widget.workspaceId;
    if (ws == null) return;

    final created = await showDialog<bool>(
      context: context,
      builder: (_) => _CreatePotDialog(userId: widget.userId, workspaceId: ws, kind: kind),
    );

    if (created == true && mounted) {
      setState(() {
        _future = _fetch();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
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
        title: const Text('Planejamento & Metas', style: TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: () {
              setState(() {
                _future = _fetch();
              });
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
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
          child: FutureBuilder<_PlanningData>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00C9A7)),
                  ),
                );
              }
              if (snap.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Text(
                      snap.error.toString().replaceFirst('Exception: ', ''),
                      style: TextStyle(color: Colors.white.withOpacity(0.85)),
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }

              final data = snap.data ?? const _PlanningData(budgets: <_BudgetItem>[], pots: <_PotItem>[]);

              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SectionHeader(
                      title: 'Orçamentos por categoria (mês)',
                      subtitle: 'Alertas: perto do limite (80%) e acima do limite (100%)',
                      actionLabel: 'Novo',
                      onAction: _openCreateBudget,
                    ),
                    const SizedBox(height: 10),
                    if (data.budgets.isEmpty)
                      _EmptyCard(message: 'Nenhum orçamento configurado para este mês.')
                    else
                      Column(
                        children: data.budgets
                            .map(
                              (b) => _BudgetCard(
                                item: b,
                                onEdit: () => _openEditBudget(b),
                                onDelete: () => _confirmDeleteBudget(b),
                              ),
                            )
                            .toList(growable: false),
                      ),
                    const SizedBox(height: 18),
                    _SectionHeader(
                      title: 'Cofrinhos e metas',
                      subtitle: 'Acompanhe o progresso e ganhe níveis conforme aporta.',
                      actionLabel: 'Novo cofrinho',
                      onAction: () => _openCreatePot(kind: 'pot'),
                    ),
                    const SizedBox(height: 10),
                    if (data.pots.where((p) => p.kind == 'pot').isEmpty)
                      _EmptyCard(message: 'Nenhum cofrinho criado ainda.')
                    else
                      Column(
                        children: data.pots
                            .where((p) => p.kind == 'pot')
                            .map(
                              (p) => _PotCard(
                                item: p,
                                onContribute: () => _openContribute(p),
                                onDelete: () => _confirmDeletePot(p),
                              ),
                            )
                            .toList(growable: false),
                      ),
                    const SizedBox(height: 18),
                    _SectionHeader(
                      title: 'Planejador de grandes compras',
                      subtitle: 'Crie uma compra e vá aportando até atingir a meta.',
                      actionLabel: 'Nova compra',
                      onAction: () => _openCreatePot(kind: 'purchase'),
                    ),
                    const SizedBox(height: 10),
                    if (data.pots.where((p) => p.kind == 'purchase').isEmpty)
                      _EmptyCard(message: 'Nenhuma compra planejada ainda.')
                    else
                      Column(
                        children: data.pots
                            .where((p) => p.kind == 'purchase')
                            .map(
                              (p) => _PotCard(
                                item: p,
                                onContribute: () => _openContribute(p),
                                onDelete: () => _confirmDeletePot(p),
                              ),
                            )
                            .toList(growable: false),
                      ),
                    const SizedBox(height: 18),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _PlanningData {
  final List<_BudgetItem> budgets;
  final List<_PotItem> pots;

  const _PlanningData({required this.budgets, required this.pots});
}

class _BudgetItem {
  final int id;
  final int categoryId;
  final String? categoryName;
  final String? categoryColor;
  final double limit;
  final double spent;
  final double percentUsed;
  final String alert;

  const _BudgetItem({
    required this.id,
    required this.categoryId,
    required this.categoryName,
    required this.categoryColor,
    required this.limit,
    required this.spent,
    required this.percentUsed,
    required this.alert,
  });

  factory _BudgetItem.fromJson(Map<String, dynamic> json) {
    final cat = json['category'] is Map ? (json['category'] as Map).cast<String, dynamic>() : null;
    return _BudgetItem(
      id: (json['id'] as num?)?.toInt() ?? 0,
      categoryId: (json['category_id'] as num?)?.toInt() ?? 0,
      categoryName: cat?['name']?.toString(),
      categoryColor: cat?['color']?.toString(),
      limit: (json['limit_amount'] as num? ?? 0).toDouble(),
      spent: (json['spent_amount'] as num? ?? 0).toDouble(),
      percentUsed: (json['percent_used'] as num? ?? 0).toDouble(),
      alert: json['alert']?.toString() ?? 'ok',
    );
  }
}

class _PotItem {
  final int id;
  final String name;
  final String kind;
  final double target;
  final double saved;
  final double progress;
  final String? dueDate;
  final int? daysLeft;
  final double? recommendedMonthly;
  final int level;
  final int xp;

  const _PotItem({
    required this.id,
    required this.name,
    required this.kind,
    required this.target,
    required this.saved,
    required this.progress,
    required this.dueDate,
    required this.daysLeft,
    required this.recommendedMonthly,
    required this.level,
    required this.xp,
  });

  factory _PotItem.fromJson(Map<String, dynamic> json) {
    final gam = json['gamification'] is Map ? (json['gamification'] as Map).cast<String, dynamic>() : null;
    return _PotItem(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: json['name']?.toString() ?? '',
      kind: json['kind']?.toString() ?? 'pot',
      target: (json['target_amount'] as num? ?? 0).toDouble(),
      saved: (json['saved_amount'] as num? ?? 0).toDouble(),
      progress: (json['progress'] as num? ?? 0).toDouble(),
      dueDate: json['due_date']?.toString(),
      daysLeft: (json['days_left'] as num?)?.toInt(),
      recommendedMonthly: (json['recommended_monthly'] as num?)?.toDouble(),
      level: (gam?['level'] as num?)?.toInt() ?? 1,
      xp: (gam?['xp'] as num?)?.toInt() ?? 0,
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onAction;

  const _SectionHeader({
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(color: Colors.white.withOpacity(0.65), fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        ElevatedButton(
          onPressed: onAction,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF00C9A7),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: Text(actionLabel),
        ),
      ],
    );
  }
}

class _EmptyCard extends StatelessWidget {
  final String message;

  const _EmptyCard({required this.message});

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
      child: Text(message, style: TextStyle(color: Colors.white.withOpacity(0.8))),
    );
  }
}

class _BudgetCard extends StatelessWidget {
  final _BudgetItem item;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _BudgetCard({required this.item, this.onEdit, this.onDelete});

  Color _alertColor(String a) {
    if (a == 'over_limit') return const Color(0xFFEF4444);
    if (a == 'near_limit') return const Color(0xFFF59E0B);
    return const Color(0xFF10B981);
  }

  @override
  Widget build(BuildContext context) {
    final pct = item.limit <= 0 ? 0.0 : (item.spent / item.limit).clamp(0.0, 2.0).toDouble();
    final color = _alertColor(item.alert);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
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
                  item.categoryName ?? 'Categoria',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                ),
              ),
              PopupMenuButton<String>(
                enabled: (onEdit != null || onDelete != null),
                color: const Color(0xFF0F2027),
                icon: Icon(Icons.more_vert, color: Colors.white.withOpacity(0.85)),
                onSelected: (v) {
                  if (v == 'edit') onEdit?.call();
                  if (v == 'delete') onDelete?.call();
                },
                itemBuilder: (_) => [
                  if (onEdit != null)
                    const PopupMenuItem<String>(
                      value: 'edit',
                      child: Text('Editar limite', style: TextStyle(color: Colors.white)),
                    ),
                  if (onDelete != null)
                    const PopupMenuItem<String>(
                      value: 'delete',
                      child: Text('Excluir', style: TextStyle(color: Colors.white)),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              'R\$ ${item.spent.toStringAsFixed(2)} / R\$ ${item.limit.toStringAsFixed(2)}',
              style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: pct > 1 ? 1.0 : pct,
              minHeight: 10,
              backgroundColor: Colors.white.withOpacity(0.10),
              valueColor: AlwaysStoppedAnimation<Color>(color.withOpacity(0.90)),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            item.alert == 'over_limit'
                ? 'Acima do limite'
                : item.alert == 'near_limit'
                    ? 'Próximo do limite'
                    : 'Dentro do limite',
            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _PotCard extends StatelessWidget {
  final _PotItem item;
  final VoidCallback? onContribute;
  final VoidCallback? onDelete;

  const _PotCard({required this.item, this.onContribute, this.onDelete});

  @override
  Widget build(BuildContext context) {
    final pct = item.target <= 0 ? 0.0 : (item.saved / item.target).clamp(0.0, 1.0).toDouble();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
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
                  item.name,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                ),
              ),
              PopupMenuButton<String>(
                enabled: (onContribute != null || onDelete != null),
                color: const Color(0xFF0F2027),
                icon: Icon(Icons.more_vert, color: Colors.white.withOpacity(0.85)),
                onSelected: (v) {
                  if (v == 'contribute') onContribute?.call();
                  if (v == 'delete') onDelete?.call();
                },
                itemBuilder: (_) => [
                  if (onContribute != null)
                    const PopupMenuItem<String>(
                      value: 'contribute',
                      child: Text('Aportar', style: TextStyle(color: Colors.white)),
                    ),
                  if (onDelete != null)
                    const PopupMenuItem<String>(
                      value: 'delete',
                      child: Text('Excluir', style: TextStyle(color: Colors.white)),
                    ),
                ],
              ),
              Text(
                'Nível ${item.level}',
                style: const TextStyle(color: Color(0xFF00C9A7), fontWeight: FontWeight.w800, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'R\$ ${item.saved.toStringAsFixed(2)} / R\$ ${item.target.toStringAsFixed(2)}',
            style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 12, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 10,
              backgroundColor: Colors.white.withOpacity(0.10),
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF00B4D8)),
            ),
          ),
          if (item.recommendedMonthly != null) ...[
            const SizedBox(height: 8),
            Text(
              'Sugestão: R\$ ${item.recommendedMonthly!.toStringAsFixed(2)}/mês',
              style: TextStyle(color: Colors.white.withOpacity(0.65), fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

class _CreateBudgetDialog extends StatefulWidget {
  final int userId;
  final int workspaceId;

  const _CreateBudgetDialog({
    required this.userId,
    required this.workspaceId,
  });

  @override
  State<_CreateBudgetDialog> createState() => _CreateBudgetDialogState();
}

class _CreateBudgetDialogState extends State<_CreateBudgetDialog> {
  final _formKey = GlobalKey<FormState>();
  final _categoryTextController = TextEditingController();
  final _limitController = TextEditingController();

  bool _saving = false;

  @override
  void dispose() {
    _categoryTextController.dispose();
    _limitController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final categoryText = _categoryTextController.text.trim();
    if (categoryText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Informe a categoria')));
      return;
    }

    setState(() {
      _saving = true;
    });

    final now = DateTime.now();
    final uri = Uri.parse('$apiBaseUrl/gerenciamento-financeiro/api/budgets');

    try {
      final resp = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': widget.userId,
          'workspace_id': widget.workspaceId,
          'category_text': categoryText,
          'limit_amount': double.parse(_limitController.text.trim().replaceAll(',', '.')),
          'period': 'monthly',
          'year': now.year,
          'month': now.month,
        }),
      );

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (resp.statusCode == 200 || resp.statusCode == 201) {
        if (data['success'] == true) {
          if (!mounted) return;
          Navigator.of(context).pop(true);
          return;
        }
      }

      final msg = data['message']?.toString() ?? 'Erro ao salvar orçamento';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF0F2027),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: Colors.white.withOpacity(0.10))),
      title: const Text('Novo orçamento', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _categoryTextController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Categoria',
                labelStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white.withOpacity(0.15))),
                focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF00C9A7))),
              ),
              validator: (v) {
                final s = (v ?? '').trim();
                if (s.isEmpty) return 'Informe a categoria';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _limitController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Limite (R\$)',
                labelStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white.withOpacity(0.15))),
                focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF00C9A7))),
              ),
              validator: (v) {
                final s = (v ?? '').trim().replaceAll(',', '.');
                if (s.isEmpty) return 'Informe o limite';
                final n = double.tryParse(s);
                if (n == null || n <= 0) return 'Valor inválido';
                return null;
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _submit,
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00C9A7), foregroundColor: Colors.white),
          child: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Salvar'),
        ),
      ],
    );
  }
}

class _EditBudgetDialog extends StatefulWidget {
  final int userId;
  final int workspaceId;
  final _BudgetItem budget;

  const _EditBudgetDialog({
    required this.userId,
    required this.workspaceId,
    required this.budget,
  });

  @override
  State<_EditBudgetDialog> createState() => _EditBudgetDialogState();
}

class _EditBudgetDialogState extends State<_EditBudgetDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _limitController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _limitController = TextEditingController(text: widget.budget.limit.toStringAsFixed(2));
  }

  @override
  void dispose() {
    _limitController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _saving = true;
    });

    final now = DateTime.now();
    final uri = Uri.parse('$apiBaseUrl/gerenciamento-financeiro/api/budgets');
    try {
      final resp = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': widget.userId,
          'workspace_id': widget.workspaceId,
          'category_id': widget.budget.categoryId,
          'limit_amount': double.parse(_limitController.text.trim().replaceAll(',', '.')),
          'period': 'monthly',
          'year': now.year,
          'month': now.month,
        }),
      );

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if ((resp.statusCode == 200 || resp.statusCode == 201) && data['success'] == true) {
        if (!mounted) return;
        Navigator.of(context).pop(true);
        return;
      }

      final msg = data['message']?.toString() ?? 'Erro ao salvar orçamento';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF0F2027),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: Colors.white.withOpacity(0.10))),
      title: const Text('Editar orçamento', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.budget.categoryName ?? 'Categoria',
              style: TextStyle(color: Colors.white.withOpacity(0.9), fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _limitController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Novo limite (R\$)',
                labelStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white.withOpacity(0.15))),
                focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF00C9A7))),
              ),
              validator: (v) {
                final s = (v ?? '').trim().replaceAll(',', '.');
                if (s.isEmpty) return 'Informe o limite';
                final n = double.tryParse(s);
                if (n == null || n <= 0) return 'Valor inválido';
                return null;
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _submit,
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00C9A7), foregroundColor: Colors.white),
          child: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Salvar'),
        ),
      ],
    );
  }
}

class _ContributeDialog extends StatefulWidget {
  final int userId;
  final int workspaceId;
  final _PotItem pot;

  const _ContributeDialog({
    required this.userId,
    required this.workspaceId,
    required this.pot,
  });

  @override
  State<_ContributeDialog> createState() => _ContributeDialogState();
}

class _ContributeDialogState extends State<_ContributeDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _saving = true;
    });

    final uri = Uri.parse('$apiBaseUrl/gerenciamento-financeiro/api/savings-pots/${widget.pot.id}/contributions');
    try {
      final resp = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': widget.userId,
          'workspace_id': widget.workspaceId,
          'amount': double.parse(_amountController.text.trim().replaceAll(',', '.')),
        }),
      );

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if ((resp.statusCode == 200 || resp.statusCode == 201) && data['success'] == true) {
        if (!mounted) return;
        Navigator.of(context).pop(true);
        return;
      }

      final msg = data['message']?.toString() ?? 'Erro ao aportar';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF0F2027),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: Colors.white.withOpacity(0.10))),
      title: const Text('Aportar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.pot.name,
              style: TextStyle(color: Colors.white.withOpacity(0.9), fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Valor (R\$)',
                labelStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white.withOpacity(0.15))),
                focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF00C9A7))),
              ),
              validator: (v) {
                final s = (v ?? '').trim().replaceAll(',', '.');
                if (s.isEmpty) return 'Informe o valor';
                final n = double.tryParse(s);
                if (n == null || n <= 0) return 'Valor inválido';
                return null;
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _submit,
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00C9A7), foregroundColor: Colors.white),
          child: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Confirmar'),
        ),
      ],
    );
  }
}

class _CreatePotDialog extends StatefulWidget {
  final int userId;
  final int workspaceId;
  final String kind;

  const _CreatePotDialog({
    required this.userId,
    required this.workspaceId,
    required this.kind,
  });

  @override
  State<_CreatePotDialog> createState() => _CreatePotDialogState();
}

class _CreatePotDialogState extends State<_CreatePotDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _targetController = TextEditingController();

  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _targetController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _saving = true;
    });

    final uri = Uri.parse('$apiBaseUrl/gerenciamento-financeiro/api/savings-pots');

    try {
      final resp = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': widget.userId,
          'workspace_id': widget.workspaceId,
          'name': _nameController.text.trim(),
          'kind': widget.kind,
          'target_amount': double.parse(_targetController.text.trim().replaceAll(',', '.')),
        }),
      );

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if ((resp.statusCode == 200 || resp.statusCode == 201) && data['success'] == true) {
        if (!mounted) return;
        Navigator.of(context).pop(true);
        return;
      }

      final msg = data['message']?.toString() ?? 'Erro ao criar';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF0F2027),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: Colors.white.withOpacity(0.10))),
      title: Text(widget.kind == 'purchase' ? 'Nova compra planejada' : 'Novo cofrinho', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _nameController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Nome',
                labelStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white.withOpacity(0.15))),
                focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF00C9A7))),
              ),
              validator: (v) {
                final s = (v ?? '').trim();
                if (s.isEmpty) return 'Informe o nome';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _targetController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Meta (R\$)',
                labelStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white.withOpacity(0.15))),
                focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF00C9A7))),
              ),
              validator: (v) {
                final s = (v ?? '').trim().replaceAll(',', '.');
                if (s.isEmpty) return 'Informe a meta';
                final n = double.tryParse(s);
                if (n == null || n <= 0) return 'Valor inválido';
                return null;
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _submit,
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00C9A7), foregroundColor: Colors.white),
          child: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Criar'),
        ),
      ],
    );
  }
}
