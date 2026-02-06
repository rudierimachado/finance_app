import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
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
  bool _isLoading = true;
  double _totalToPay = 0.0;  // Contas a pagar
  double _totalInCash = 0.0;  // Saldo em caixa

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    try {
      final workspaceParam = widget.workspaceId != null ? '&workspace_id=${widget.workspaceId}' : '';
      final response = await http.get(
        Uri.parse('${apiBaseUrl}/gerenciamento-financeiro/api/transactions?user_id=${widget.userId}$workspaceParam'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final transactions = data['transactions'] ?? [];
        print('Carregadas ${transactions.length} transações da API');
        
        // Calcular totais
        _calculateTotals(transactions);
        
        setState(() {
          _isLoading = false;
        });
      } else {
        print('Erro API: ${response.statusCode} - ${response.body}');
        // Carrega dados mockados se a API falhar
        _loadMockData();
      }
    } catch (e) {
      print('Erro ao carregar dados: $e');
      // Carrega dados mockados em caso de erro
      _loadMockData();
    }
  }

  void _loadMockData() {
    setState(() {
      _totalToPay = 705.80;  // Valor mockado de contas a pagar
      _totalInCash = 5000.0;  // Valor mockado em caixa
      _isLoading = false;
    });
    print('Carregados dados mockados');
  }

  void _calculateTotals(List transactions) {
    final now = DateTime.now();
    final currentMonth = now.month;
    final currentYear = now.year;
    
    // Calcular total a pagar (despesas não pagas do mês atual)
    double totalBills = 0.0;
    for (var t in transactions) {
      try {
        final date = DateTime.parse(t['date'].toString());
        final isCurrentMonth = date.month == currentMonth && date.year == currentYear;
        final isExpense = t['type'] == 'expense';
        final isNotPaid = t['paid'] != true;
        
        if (isCurrentMonth && isExpense && isNotPaid) {
          totalBills += double.tryParse(t['amount'].toString()) ?? 0.0;
        }
      } catch (e) {
        print('Erro ao processar transação: $e');
      }
    }
    
    _totalToPay = totalBills;
    _totalInCash = 5000.0; // Você pode ajustar isso conforme sua lógica
  }

  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F2027),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF00C9A7)))
          : RefreshIndicator(
              onRefresh: _loadDashboardData,
              color: const Color(0xFF00C9A7),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 20),
                    _buildSummaryCards(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [const Color(0xFF00C9A7), const Color(0xFF008B7D)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Dashboard Financeiro',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Mês de ${DateFormat('MMMM/yyyy', 'pt_BR').format(DateTime.now())}',
            style: const TextStyle(
              fontSize: 16,
              color: Colors.white70,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCards() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildSummaryCard(
                'A Pagar',
                'R\$ ${_totalToPay.toStringAsFixed(2)}',
                Icons.payment,
                Colors.red,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildSummaryCard(
                'Em Caixa',
                'R\$ ${_totalInCash.toStringAsFixed(2)}',
                Icons.account_balance_wallet,
                Colors.green,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildBalanceCard(),
      ],
    );
  }

  Widget _buildBalanceCard() {
    final remaining = _totalInCash - _totalToPay;
    final isPositive = remaining >= 0;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isPositive 
            ? Colors.green.withOpacity(0.1)
            : Colors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isPositive ? Colors.green : Colors.red,
          width: 2,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isPositive ? Icons.trending_up : Icons.warning,
            color: isPositive ? Colors.green : Colors.red,
            size: 24,
          ),
          const SizedBox(width: 12),
          Column(
            children: [
              Text(
                'Saldo Restante',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white.withOpacity(0.8),
                ),
              ),
              Text(
                'R\$ ${remaining.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: isPositive ? Colors.green : Colors.red,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2A33),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white.withOpacity(0.8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  
  
}
