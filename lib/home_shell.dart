import 'package:flutter/material.dart';

import 'add_transaction.dart';
import 'config.dart';
import 'dashboard.dart';
import 'transactions_page.dart';

class HomeShell extends StatefulWidget {
  final int userId;

  const HomeShell({
    super.key,
    required this.userId,
  });

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          DashboardPage(userId: widget.userId),
          TransactionsPage(userId: widget.userId),
          _SettingsPlaceholderPage(userId: widget.userId),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0F2027),
          border: Border(
            top: BorderSide(color: Colors.white.withOpacity(0.08)),
          ),
        ),
        child: BottomNavigationBar(
          currentIndex: _index,
          onTap: (i) => setState(() => _index = i),
          backgroundColor: const Color(0xFF0F2027),
          selectedItemColor: const Color(0xFF00C9A7),
          unselectedItemColor: Colors.white.withOpacity(0.65),
          type: BottomNavigationBarType.fixed,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.dashboard_outlined),
              activeIcon: Icon(Icons.dashboard),
              label: 'Dashboard',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.list_alt_outlined),
              activeIcon: Icon(Icons.list_alt),
              label: 'Transações',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.settings_outlined),
              activeIcon: Icon(Icons.settings),
              label: 'Ajustes',
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsPlaceholderPage extends StatelessWidget {
  final int userId;
  
  const _SettingsPlaceholderPage({required this.userId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final changed = await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (_) => AddTransactionPage(userId: userId),
            ),
          );
          if (changed == true) {
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
            colors: [Color(0xFF0F2027), Color(0xFF203A43), Color(0xFF2C5364)],
          ),
        ),
        child: const SafeArea(
          child: Center(
            child: Text(
              'Ajustes',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
