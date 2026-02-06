import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'config.dart';

class AddTransactionPage extends StatefulWidget {
  final int userId;
  final int? transactionId;
  final int? workspaceId;

  const AddTransactionPage({
    super.key,
    required this.userId,
    this.transactionId,
    this.workspaceId,
  });

  @override
  State<AddTransactionPage> createState() => _AddTransactionPageState();
}

class _AddTransactionPageState extends State<AddTransactionPage> {
  final _formKey = GlobalKey<FormState>();

  String _type = 'expense';
  DateTime _date = DateTime.now();
  bool _loading = false;
  bool _isPaid = false;
  bool _suggestingCategory = false;
  bool _categoryGenerated = false;
  String _lastSuggestedDescription = '';
  bool _isRecurring = false;
  int _recurringDay = 1;
  bool _recurringUnlimited = true;
  int _recurringEndMonth = 1;
  int _recurringEndYear = 2025;
  int _recurringInstallments = 1;
  String _recurringInstallmentsStart = 'current_month';

  final _descriptionController = TextEditingController();
  final _amountController = TextEditingController();
  final _categoryController = TextEditingController();
  final _subcategoryController = TextEditingController();
  final _salaryFromController = TextEditingController();
  final _cardNameController = TextEditingController();

  final _amountFocusNode = FocusNode();

  String? _paymentMethod;
  int? _selectedCreditCardId;
  List<dynamic> _creditCards = [];
  bool _loadingCards = false;

  static const Set<String> _allowedPaymentMethods = {
    'dinheiro',
    'pix',
    'debito',
    'credito',
    'transferencia',
    'boleto',
  };

  String? _normalizePaymentMethod(dynamic raw) {
    if (raw == null) return null;
    final s = raw.toString().trim();
    if (s.isEmpty) return null;
    final lower = s.toLowerCase();
    if (lower == 'none' || lower == 'null') return null;
    if (!_allowedPaymentMethods.contains(s)) return null;
    return s;
  }
  
  Timer? _debounceTimer;

  bool get _isEditMode => widget.transactionId != null;

  // MANTENDO TODAS AS FUNÇÕES DE LÓGICA ORIGINAIS SEM ALTERAÇÃO
  @override
  void initState() {
    super.initState();

    final now = DateTime.now();
    _recurringEndMonth = now.month;
    _recurringEndYear = now.year;

    _descriptionController.addListener(_onDescriptionChanged);

    if (_isEditMode) {
      _loadTransactionForEdit();
    }
    _loadCreditCards();
    
    _amountFocusNode.addListener(() {
      if (_amountFocusNode.hasFocus) {
        final text = _descriptionController.text.trim();
        if (text.length >= 3 && !_suggestingCategory && !_categoryGenerated) {
          _suggestCategory(text);
        }
      }
    });
  }

  Future<void> _loadCreditCards() async {
    setState(() => _loadingCards = true);
    try {
      final workspaceIdParam = widget.workspaceId != null ? '&workspace_id=${widget.workspaceId}' : '';
      final uri = Uri.parse('$apiBaseUrl/gerenciamento-financeiro/api/credit-cards?user_id=${widget.userId}$workspaceIdParam');
      final resp = await http.get(uri).timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        if (data['success'] == true) {
          setState(() {
            _creditCards = data['cards'] ?? [];
          });
        }
      }
    } catch (e) {
      debugPrint('Erro ao carregar cartões: $e');
    } finally {
      setState(() => _loadingCards = false);
    }
  }

  Future<void> _deleteCreditCard(int cardId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0F2027),
        title: const Text('Excluir Cartão', style: TextStyle(color: Colors.white)),
        content: const Text('Deseja realmente excluir este cartão? Esta ação não pode ser desfeita.',
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _loadingCards = true);
    try {
      final uri = Uri.parse('$apiBaseUrl/gerenciamento-financeiro/api/credit-cards/$cardId?user_id=${widget.userId}');
              final resp = await http.delete(uri).timeout(const Duration(seconds: 10));
      final data = jsonDecode(resp.body);

      if (resp.statusCode == 200 && data['success'] == true) {
        if (_selectedCreditCardId == cardId) {
          _selectedCreditCardId = null;
        }
        await _loadCreditCards();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Cartão excluído com sucesso')),
          );
        }
      } else {
        throw Exception(data['message'] ?? 'Erro ao excluir cartão');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loadingCards = false);
      }
    }
  }

  Future<void> _loadTransactionForEdit() async {
    // ... código original mantido igual
    if (widget.transactionId == null) {
      return;
    }

    setState(() {
      _loading = true;
    });

    try {
      final uri = Uri.parse(
        '$apiBaseUrl/gerenciamento-financeiro/api/transactions/${widget.transactionId}?user_id=${widget.userId}',
      );

      final resp = await http.get(uri, headers: {'Content-Type': 'application/json'})
          .timeout(const Duration(seconds: 10));

      Map<String, dynamic> data;
      try {
        data = jsonDecode(resp.body) as Map<String, dynamic>;
      } catch (_) {
        throw Exception('Resposta inválida do servidor (status ${resp.statusCode}).');
      }

      if (resp.statusCode != 200 || data['success'] != true) {
        throw Exception(data['message']?.toString() ?? 'Falha ao carregar transação.');
      }

      final rawTx = data['transaction'];
      if (rawTx is! Map) {
        throw Exception('Resposta inválida do servidor (transaction ausente).');
      }
      final tx = rawTx as Map<String, dynamic>;

      if (!mounted) return;

      setState(() {
        _type = (tx['type']?.toString() ?? 'expense');
        _descriptionController.text = tx['description']?.toString() ?? '';
        _amountController.text = ((tx['amount'] as num?)?.toDouble() ?? 0).toStringAsFixed(2);

        final catText = tx['category_text']?.toString();
        _categoryController.text = (catText != null && catText.isNotEmpty) ? catText : '';
        _categoryGenerated = _categoryController.text.trim().isNotEmpty;
        _lastSuggestedDescription = _descriptionController.text.trim();

        final subText = tx['subcategory_text']?.toString();
        _subcategoryController.text = (subText != null && subText.isNotEmpty) ? subText : '';
        
        if (_paymentMethod == 'credito' && subText != null && subText.isNotEmpty) {
          _cardNameController.text = subText;
          _subcategoryController.clear();
        }

        _paymentMethod = _normalizePaymentMethod(tx['payment_method']);
        _selectedCreditCardId = tx['credit_card_id'];
        _isPaid = (tx['is_paid'] == true);

        final dateStr = tx['transaction_date']?.toString();
        if (dateStr != null && dateStr.isNotEmpty) {
          final parsed = DateTime.tryParse(dateStr);
          if (parsed != null) {
            _date = parsed;
          }
        }

        _isRecurring = (tx['is_recurring'] == true);
        final recDay = tx['recurring_day'];
        if (recDay is num) {
          _recurringDay = recDay.toInt();
        }
        _recurringUnlimited = (tx['recurring_unlimited'] == true);
        final recInst = tx['recurring_installments'];
        if (recInst is num) {
          _recurringInstallments = recInst.toInt();
        } else {
          _recurringInstallments = 1;
        }
        final recInstStart = (tx['recurring_installments_start']?.toString() ?? '').trim();
        if (recInstStart == 'due_date' || recInstStart == 'current_month') {
          _recurringInstallmentsStart = recInstStart;
        } else {
          _recurringInstallmentsStart = 'current_month';
        }
        final recEnd = tx['recurring_end_date']?.toString();
        if (recEnd != null && recEnd.isNotEmpty) {
          final parsedEnd = DateTime.tryParse(recEnd);
          if (parsedEnd != null) {
            _recurringEndMonth = parsedEnd.month;
            _recurringEndYear = parsedEnd.year;
          }
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _pickRecurringEndMonthYear() async {
    // ... código original mantido igual
    int selectedMonth = _recurringEndMonth;
    int selectedYear = _recurringEndYear;

    final now = DateTime.now();
    final years = List<int>.generate(11, (i) => now.year + i);

    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Até quando'),
          content: StatefulBuilder(
            builder: (context, setStateDialog) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<int>(
                    value: selectedMonth,
                    decoration: const InputDecoration(labelText: 'Mês'),
                    items: List.generate(12, (i) => i + 1)
                        .map((m) => DropdownMenuItem<int>(value: m, child: Text(m.toString().padLeft(2, '0'))))
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      setStateDialog(() {
                        selectedMonth = v;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    value: selectedYear,
                    decoration: const InputDecoration(labelText: 'Ano'),
                    items: years.map((y) => DropdownMenuItem<int>(value: y, child: Text(y.toString()))).toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      setStateDialog(() {
                        selectedYear = v;
                      });
                    },
                  ),
                ],
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );

    if (result == true) {
      setState(() {
        _recurringEndMonth = selectedMonth;
        _recurringEndYear = selectedYear;
      });
    }
  }

  String _recurringEndDateIso() {
    final lastDay = DateTime(_recurringEndYear, _recurringEndMonth + 1, 0);
    return lastDay.toIso8601String().split('T').first;
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _amountFocusNode.dispose();
    _descriptionController.removeListener(_onDescriptionChanged);
    _descriptionController.dispose();
    _amountController.dispose();
    _categoryController.dispose();
    _subcategoryController.dispose();
    _salaryFromController.dispose();
    _cardNameController.dispose();
    super.dispose();
  }

  // MANTENDO FUNÇÃO ORIGINAL DA IA SEM ALTERAÇÃO
  void _onDescriptionChanged() {
    final current = _descriptionController.text.trim();

    if (_categoryGenerated && current != _lastSuggestedDescription) {
      setState(() {
        _categoryGenerated = false;
        _categoryController.clear();
        _subcategoryController.clear();
      });
    }

    if (current.isEmpty && (_categoryController.text.isNotEmpty || _subcategoryController.text.isNotEmpty)) {
      setState(() {
        _categoryGenerated = false;
        _lastSuggestedDescription = '';
        _categoryController.clear();
        _subcategoryController.clear();
      });
    }

    setState(() {});
  }

  // MANTENDO FUNÇÃO ORIGINAL DA IA SEM ALTERAÇÃO
  Future<void> _suggestCategory(String description) async {
    if (_suggestingCategory) {
      return;
    }
    
    setState(() {
      _suggestingCategory = true;
      _categoryGenerated = false;
      _lastSuggestedDescription = description.trim();
      _categoryController.clear();
      _subcategoryController.clear();
      _salaryFromController.clear();
    });

    try {
      final uri = Uri.parse('$apiBaseUrl/gerenciamento-financeiro/api/suggest-category');
      final payload = {
        'user_id': widget.userId,
        'description': description,
        'type': _type,
      };

      final resp = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 12));

      Map<String, dynamic>? data;
      try {
        data = jsonDecode(resp.body) as Map<String, dynamic>;
      } catch (_) {
        data = null;
      }

      if (resp.statusCode != 200) {
        final msg = data?['message']?.toString();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(msg ?? 'Falha ao sugerir categoria (HTTP ${resp.statusCode}).'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      if (data == null) {
        throw Exception('Resposta inválida do servidor.');
      }

      if (data['success'] == true) {
        final category = data['category']?.toString();
        final subcategory = data['subcategory']?.toString();

        if (mounted) {
          setState(() {
            if (category != null && category.isNotEmpty) {
              _categoryController.text = category;
              _categoryGenerated = true;
            } else {
              _categoryGenerated = false;
            }
            final isSalary = _isSalaryCategory;
            if (!isSalary && subcategory != null && subcategory.isNotEmpty) {
              _subcategoryController.text = subcategory;
            } else {
              _subcategoryController.clear();
            }

            _lastSuggestedDescription = _descriptionController.text.trim();
          });
        }
        return;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data['message']?.toString() ?? 'Falha ao sugerir categoria.'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    } on TimeoutException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Timeout ao sugerir categoria: $e'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Falha ao sugerir categoria.'),
            backgroundColor: Color(0xFFEF4444),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _suggestingCategory = false;
        });
      }
    }
  }

  bool get _isSalaryCategory {
    final lower = _categoryController.text.trim().toLowerCase();
    return lower == 'salário' || lower == 'salario';
  }

  bool get _isCardFlow {
    final desc = _descriptionController.text.trim().toLowerCase();
    final cat = _categoryController.text.trim().toLowerCase();
    final sub = _subcategoryController.text.trim().toLowerCase();
    return _type == 'expense' &&
        (_paymentMethod == 'credito' ||
            desc.contains('cartão') ||
            desc.contains('cartao') ||
            cat.contains('cartão') ||
            cat.contains('cartao') ||
            sub.contains('cartão') ||
            sub.contains('cartao'));
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        _date = picked;
      });
    }
  }

  Future<void> _submit() async {
    // ... código original mantido igual
    if (!_formKey.currentState!.validate()) return;

    // Permite continuar mesmo se a IA não sugeriu (usuário pode digitar)
    if (_categoryController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Informe uma categoria para a transação.'),
          backgroundColor: Color(0xFFEF4444),
        ),
      );
      return;
    }

    final amount = double.tryParse(_amountController.text.replaceAll(',', '.'));
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe um valor válido.')),
      );
      return;
    }

    setState(() {
      _loading = true;
    });

    try {
      final uri = _isEditMode
          ? Uri.parse('$apiBaseUrl/gerenciamento-financeiro/api/transactions/${widget.transactionId}')
          : Uri.parse('$apiBaseUrl/gerenciamento-financeiro/api/transactions');
      final baseDesc = _descriptionController.text.trim();
      final salaryFrom = _salaryFromController.text.trim();
      final finalDesc = (_type == 'income' && _isSalaryCategory && salaryFrom.isNotEmpty)
          ? '$baseDesc - $salaryFrom'
          : baseDesc;

      final payload = {
        'user_id': widget.userId,
        'type': _type,
        'description': finalDesc,
        'amount': amount,
        'category_text': _categoryController.text.trim().isNotEmpty ? _categoryController.text.trim() : null,
        'transaction_date': _date.toIso8601String().split('T').first,
        'payment_method': _type == 'expense' ? (_paymentMethod ?? '') : null,
        'credit_card_id': (_type == 'expense' && _paymentMethod == 'credito') ? _selectedCreditCardId : null,
        'is_paid': _type == 'expense' ? _isPaid : true,
        'subcategory_text': _isCardFlow
            ? _cardNameController.text.trim()
            : _subcategoryController.text.trim().isNotEmpty
                ? _subcategoryController.text.trim()
                : null,
        'is_recurring': _isRecurring,
        'recurring_day': _isRecurring ? _recurringDay : null,
        'recurring_unlimited': _isRecurring ? _recurringUnlimited : null,
        'recurring_installments': (_isRecurring && !_recurringUnlimited && _type == 'expense')
            ? (_recurringInstallments < 1 ? 1 : _recurringInstallments)
            : null,
        'recurring_installments_start': (_isRecurring && !_recurringUnlimited && _type == 'expense')
            ? _recurringInstallmentsStart
            : null,
        'recurring_end_date': (_isRecurring && !_recurringUnlimited && _type != 'expense')
            ? _recurringEndDateIso()
            : null,
      };

      if (widget.workspaceId != null) {
        payload['workspace_id'] = widget.workspaceId;
      }

      final resp = _isEditMode
          ? await http.put(
              uri,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(payload),
            ).timeout(const Duration(seconds: 10))
          : await http.post(
              uri,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(payload),
            ).timeout(const Duration(seconds: 10));

      final data = jsonDecode(resp.body) as Map<String, dynamic>;

      if (((resp.statusCode == 201) || (resp.statusCode == 200)) && data['success'] == true) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Transação salva com sucesso!'),
            backgroundColor: Color(0xFF10B981),
          ),
        );
        financeRefreshTick.value = financeRefreshTick.value + 1;
        Navigator.of(context).pop(true);
        return;
      }

      final msg = data['message']?.toString() ?? 'Erro ao salvar transação.';
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Erro'),
            content: Text(msg),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Falha de Conexão'),
            content: Text(e.toString()),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
            ],
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  // APENAS OS WIDGETS VISUAIS FORAM MODERNIZADOS
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F2027),
      appBar: AppBar(
        title: Text(
          _isEditMode ? 'Editar transação' : 'Nova transação',
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
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
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 20),
                    _buildModernSectionHeader('Tipo de transação', Icons.swap_horiz),
                    const SizedBox(height: 16),
                    _buildTypeSelector(),
                    const SizedBox(height: 32),
                    
                    _buildModernSectionHeader('Informações básicas', Icons.info_outline),
                    const SizedBox(height: 16),
                    _buildModernTextField(
                      controller: _descriptionController,
                      label: 'Descrição',
                      icon: Icons.description_outlined,
                      validator: (v) => (v ?? '').trim().isEmpty ? 'Informe a descrição' : null,
                    ),
                    const SizedBox(height: 16),
                    _buildAmountField(),
                    const SizedBox(height: 16),
                    _buildModernTextField(
                      controller: _categoryController,
                      label: 'Categoria',
                      icon: Icons.category_outlined,
                      readOnly: false, // Permitir edição manual
                      suffix: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_suggestingCategory)
                            Container(
                              padding: const EdgeInsets.all(8),
                              child: const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00C9A7)),
                              ),
                            )
                          else
                            IconButton(
                              icon: const Icon(Icons.auto_awesome, color: Color(0xFF00C9A7), size: 20),
                              onPressed: () {
                                final desc = _descriptionController.text.trim();
                                if (desc.isNotEmpty) {
                                  _suggestCategory(desc);
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Digite uma descrição primeiro.')),
                                  );
                                }
                              },
                              tooltip: 'Sugerir com IA',
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildModernTextField(
                      controller: _subcategoryController,
                      label: 'Subcategoria',
                      icon: Icons.label_outlined,
                      readOnly: false, // Permitir edição manual
                    ),
                    
                    if (_isCardFlow) ...[
                      const SizedBox(height: 16),
                      _buildModernTextField(
                        controller: _cardNameController,
                        label: 'Nome do cartão',
                        icon: Icons.credit_card,
                      ),
                    ],
                    
                    if (_type == 'income' && _isSalaryCategory) ...[
                      const SizedBox(height: 16),
                      _buildModernTextField(
                        controller: _salaryFromController,
                        label: 'De quem é o salário?',
                        icon: Icons.person_outline,
                      ),
                    ],
                    
                    const SizedBox(height: 32),
                    _buildModernSectionHeader('Configurações', Icons.settings_outlined),
                    const SizedBox(height: 16),
                    
                    _buildRecurringSwitch(),
                    
                    if (_isRecurring) ...[
                      const SizedBox(height: 16),
                      _buildRecurringDayPicker(),
                      const SizedBox(height: 16),
                      _buildRecurringEndMode(),
                    ],
                    
                    if (!_isRecurring) ...[
                      const SizedBox(height: 16),
                      _buildDatePicker(),
                    ],
                    
                    if (_type == 'expense') ...[
                      const SizedBox(height: 16),
                      _buildPaymentMethodDropdown(),
                      if (_paymentMethod == 'credito') ...[
                        const SizedBox(height: 16),
                        _buildCreditCardSelector(),
                      ],
                      const SizedBox(height: 16),
                      _buildPaidSwitch(),
                    ],
                    
                    const SizedBox(height: 40),
                    _buildActionButtons(),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
            
            // Loading overlay para IA (mantendo função original)
            if (_suggestingCategory || (_isEditMode && _loading))
              Container(
                color: Colors.black.withOpacity(0.8),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F2027),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFF00C9A7).withOpacity(0.3)),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF00C9A7).withOpacity(0.2),
                              blurRadius: 20,
                              spreadRadius: 5,
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            const SizedBox(
                              width: 50,
                              height: 50,
                              child: CircularProgressIndicator(
                                strokeWidth: 4,
                                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00C9A7)),
                              ),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              _suggestingCategory ? 'IA gerando categoria...' : 'Carregando transação...',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Aguarde alguns segundos',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.7),
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildModernSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF00C9A7), Color(0xFF00B4D8)],
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF00C9A7).withOpacity(0.3),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTypeSelector() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildTypeButton(
              label: 'Despesa',
              icon: Icons.trending_up,
              color: const Color(0xFFEF4444),
              isSelected: _type == 'expense',
              onTap: () {
                setState(() {
                  _type = 'expense';
                  _isPaid = false;
                  _categoryController.clear();
                  _subcategoryController.clear();
                  _categoryGenerated = false;
                  _salaryFromController.clear();
                  _isRecurring = false;
                  _recurringUnlimited = true;
                  final now = DateTime.now();
                  _recurringEndMonth = now.month;
                  _recurringEndYear = now.year;
                  _recurringDay = 1;
                  _lastSuggestedDescription = '';
                });
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildTypeButton(
              label: 'Receita',
              icon: Icons.trending_down,
              color: const Color(0xFF10B981),
              isSelected: _type == 'income',
              onTap: () {
                setState(() {
                  _type = 'income';
                  _isPaid = true;
                  _categoryController.clear();
                  _subcategoryController.clear();
                  _categoryGenerated = false;
                  _salaryFromController.clear();
                  _isRecurring = false;
                  _recurringUnlimited = true;
                  final now = DateTime.now();
                  _recurringEndMonth = now.month;
                  _recurringEndYear = now.year;
                  _recurringDay = 1;
                  _lastSuggestedDescription = '';
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeButton({
    required String label,
    required IconData icon,
    required Color color,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: isSelected 
              ? Border.all(color: color, width: 2) 
              : Border.all(color: Colors.transparent, width: 2),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isSelected ? color : Colors.white.withOpacity(0.5),
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? color : Colors.white.withOpacity(0.5),
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAmountField() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.15)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextFormField(
        controller: _amountController,
        focusNode: _amountFocusNode,
        keyboardType: TextInputType.number,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
        decoration: InputDecoration(
          labelText: 'Valor',
          labelStyle: TextStyle(
            color: Colors.white.withOpacity(0.6),
            fontSize: 16,
          ),
          prefixIcon: Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withOpacity(0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.attach_money,
              color: Color(0xFF10B981),
              size: 20,
            ),
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        ),
        validator: (v) => (v ?? '').trim().isEmpty ? 'Informe o valor' : null,
      ),
    );
  }

  Widget _buildModernTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    int maxLines = 1,
    bool readOnly = false,
    Widget? suffix,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.15)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        maxLines: maxLines,
        readOnly: readOnly,
        style: TextStyle(
          color: readOnly ? Colors.white.withOpacity(0.8) : Colors.white,
          fontSize: 16,
        ),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(
            color: Colors.white.withOpacity(0.6),
            fontSize: 15,
          ),
          prefixIcon: Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              color: Colors.white.withOpacity(0.7),
              size: 20,
            ),
          ),
          suffixIcon: suffix,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        ),
        validator: validator,
      ),
    );
  }

  Widget _buildPaymentMethodDropdown() {
    final methods = [
      {'value': 'dinheiro', 'label': 'Dinheiro', 'icon': Icons.payments},
      {'value': 'pix', 'label': 'PIX', 'icon': Icons.qr_code},
      {'value': 'debito', 'label': 'Débito', 'icon': Icons.credit_card},
      {'value': 'credito', 'label': 'Cartão de crédito', 'icon': Icons.credit_card_outlined},
      {'value': 'transferencia', 'label': 'Transferência', 'icon': Icons.swap_horiz},
      {'value': 'boleto', 'label': 'Boleto', 'icon': Icons.receipt_long},
    ];

    final paymentMethodValue = (_paymentMethod != null && methods.any((m) => m['value'] == _paymentMethod))
        ? _paymentMethod!
        : null;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.15)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: DropdownButtonFormField<String>(
        value: paymentMethodValue,
        dropdownColor: const Color(0xFF1A2A35),
        style: const TextStyle(color: Colors.white, fontSize: 16),
        decoration: InputDecoration(
          labelText: 'Forma de pagamento',
          labelStyle: TextStyle(
            color: Colors.white.withOpacity(0.6),
            fontSize: 15,
          ),
          prefixIcon: Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.payment,
              color: Colors.white.withOpacity(0.7),
              size: 20,
            ),
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        ),
        items: methods
            .map((m) => DropdownMenuItem<String>(
                  value: m['value'] as String,
                  child: Row(
                    children: [
                      Icon(m['icon'] as IconData, size: 18, color: Colors.white.withOpacity(0.7)),
                      const SizedBox(width: 8),
                      Text(m['label'] as String),
                    ],
                  ),
                ))
            .toList(),
        onChanged: (v) {
          setState(() {
            _paymentMethod = v;
            if (_paymentMethod != 'credito') {
              _selectedCreditCardId = null;
              _subcategoryController.clear();
            }
          });
        },
        validator: (v) => v == null || v.isEmpty ? 'Selecione a forma de pagamento' : null,
      ),
    );
  }

  Widget _buildCreditCardSelector() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.15)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00C9A7).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.credit_card, color: Color(0xFF00C9A7), size: 20),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Cartões de crédito',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF00C9A7), Color(0xFF00B4D8)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TextButton.icon(
                  onPressed: _showAddCreditCardDialog,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Novo', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (_loadingCards)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00C9A7)),
              ),
            )
          else if (_creditCards.isEmpty)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.white.withOpacity(0.5), size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Nenhum cartão cadastrado',
                      style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 14),
                    ),
                  ),
                ],
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _selectedCreditCardId,
                    dropdownColor: const Color(0xFF1A2A35),
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                    decoration: InputDecoration(
                      labelText: 'Selecione um cartão',
                      labelStyle: TextStyle(color: Colors.white.withOpacity(0.6)),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15),
                        borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15),
                        borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15),
                        borderSide: const BorderSide(color: Color(0xFF00C9A7)),
                      ),
                    ),
                    items: _creditCards.map((card) {
                      return DropdownMenuItem<int>(
                        value: card['id'] as int,
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: const Color(0xFF00C9A7).withOpacity(0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.credit_card, color: Color(0xFF00C9A7), size: 16),
                            ),
                            const SizedBox(width: 8),
                            Text(card['name'] as String),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: (v) => setState(() => _selectedCreditCardId = v),
                    validator: (v) => v == null ? 'Selecione um cartão' : null,
                  ),
                ),
                if (_selectedCreditCardId != null) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () => _deleteCreditCard(_selectedCreditCardId!),
                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                    tooltip: 'Excluir cartão',
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildDatePicker() {
    String dateLabel = _type == 'expense' ? 'Data de vencimento' : 'Data da transação';
    if (_isRecurring && !_recurringUnlimited && _type == 'expense') {
      dateLabel = 'Data do 1º vencimento';
    }
    
    return GestureDetector(
      onTap: _pickDate,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.15)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.calendar_today, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    dateLabel,
                    style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_date.day.toString().padLeft(2, '0')}/${_date.month.toString().padLeft(2, '0')}/${_date.year}',
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, color: Colors.white.withOpacity(0.3), size: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildRecurringSwitch() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.15)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.repeat, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              _type == 'income'
                  ? 'Receita recorrente (todo mês)'
                  : 'Despesa recorrente (todo mês)',
              style: TextStyle(
                color: Colors.white.withOpacity(0.9),
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Switch(
            value: _isRecurring,
            onChanged: (v) {
              setState(() {
                _isRecurring = v;
                if (!_isRecurring) {
                  _recurringUnlimited = true;
                  final now = DateTime.now();
                  _recurringEndMonth = now.month;
                  _recurringEndYear = now.year;
                }
              });
            },
            activeColor: const Color(0xFF00C9A7),
            activeTrackColor: const Color(0xFF00C9A7).withOpacity(0.3),
          ),
        ],
      ),
    );
  }

  Widget _buildRecurringDayPicker() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.15)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.calendar_today, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              _type == 'income' ? 'Dia de recebimento' : 'Dia de vencimento',
              style: TextStyle(
                color: Colors.white.withOpacity(0.9),
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: DropdownButton<int>(
              value: _recurringDay,
              dropdownColor: const Color(0xFF1A2A35),
              style: const TextStyle(color: Colors.white, fontSize: 15),
              underline: Container(),
              items: List.generate(31, (index) => index + 1)
                  .map((day) => DropdownMenuItem<int>(
                        value: day,
                        child: Text('Dia $day'),
                      ))
                  .toList(),
              onChanged: (v) {
                if (v != null) {
                  setState(() {
                    _recurringDay = v;
                  });
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecurringEndMode() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.15)),
      ),
      child: Column(
        children: [
          if (_type == 'expense') ...[
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.format_list_numbered, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    'Parcelado',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Switch(
                  value: !_recurringUnlimited,
                  onChanged: (v) {
                    setState(() {
                      _recurringUnlimited = !v;
                      if (_recurringUnlimited) {
                        _recurringInstallments = 1;
                      } else {
                        if (_recurringInstallments < 1) {
                          _recurringInstallments = 1;
                        }
                      }
                    });
                  },
                  activeColor: const Color(0xFF00C9A7),
                  activeTrackColor: const Color(0xFF00C9A7).withOpacity(0.3),
                ),
              ],
            ),
          ] else ...[
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.all_inclusive, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    'Sem fim (ilimitado)',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Switch(
                  value: _recurringUnlimited,
                  onChanged: (v) {
                    setState(() {
                      _recurringUnlimited = v;
                      if (_recurringUnlimited) {
                        _recurringInstallments = 1;
                      }
                    });
                  },
                  activeColor: const Color(0xFF00C9A7),
                  activeTrackColor: const Color(0xFF00C9A7).withOpacity(0.3),
                ),
              ],
            ),
          ],
          
          if (!_recurringUnlimited && _type == 'expense') ...[
            const SizedBox(height: 20),
            const Divider(color: Colors.white12),
            const SizedBox(height: 20),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00C9A7).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.pin_outlined, color: Color(0xFF00C9A7), size: 20),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Número de Parcelas',
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$_recurringInstallments parcelas',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  children: [
                    IconButton(
                      onPressed: () {
                        if (_recurringInstallments > 1) {
                          setState(() => _recurringInstallments--);
                        }
                      },
                      icon: const Icon(Icons.remove_circle_outline, color: Colors.white60),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$_recurringInstallments',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(
                      onPressed: () {
                        setState(() => _recurringInstallments++);
                      },
                      icon: const Icon(Icons.add_circle_outline, color: Color(0xFF00C9A7)),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPaidSwitch() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.15)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              _isPaid ? Icons.check_circle : Icons.pending,
              color: _isPaid ? const Color(0xFF10B981) : const Color(0xFFFBBF24),
              size: 20,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Status do pagamento',
                  style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13),
                ),
                const SizedBox(height: 4),
                Text(
                  _isPaid ? 'Pago' : 'Pendente',
                  style: TextStyle(
                    color: _isPaid ? const Color(0xFF10B981) : const Color(0xFFFBBF24),
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: _isPaid,
            onChanged: (v) {
              setState(() {
                _isPaid = v;
              });
            },
            activeColor: const Color(0xFF10B981),
            activeTrackColor: const Color(0xFF10B981).withOpacity(0.3),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Column(
      children: [
        Container(
          width: double.infinity,
          height: 60,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF00C9A7), Color(0xFF00B4D8)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF00C9A7).withOpacity(0.4),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ElevatedButton(
            onPressed: _loading ? null : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              foregroundColor: Colors.white,
              shadowColor: Colors.transparent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
            child: _loading
                ? const SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white),
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle, size: 24),
                      SizedBox(width: 12),
                      Text(
                        'Salvar transação',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  Future<void> _showAddCreditCardDialog() async {
    final nameController = TextEditingController();
    final limitController = TextEditingController();
    final closingDayController = TextEditingController();
    final dueDayController = TextEditingController();
    bool saving = false;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              backgroundColor: const Color(0xFF0F2027),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: Colors.white.withOpacity(0.10)),
              ),
              title: const Text(
                'Cadastrar Cartão',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Nome do Cartão (ex: Nubank)',
                        labelStyle: TextStyle(color: Colors.white70),
                      ),
                    ),
                    TextField(
                      controller: limitController,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Limite (opcional)',
                        labelStyle: TextStyle(color: Colors.white70),
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: closingDayController,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(color: Colors.white),
                            decoration: const InputDecoration(
                              labelText: 'Dia Fechamento',
                              labelStyle: TextStyle(color: Colors.white70),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: dueDayController,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(color: Colors.white),
                            decoration: const InputDecoration(
                              labelText: 'Dia Vencimento',
                              labelStyle: TextStyle(color: Colors.white70),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: saving ? null : () async {
                    if (nameController.text.isEmpty) return;
                    setStateDialog(() => saving = true);
                    try {
                      final payload = {
                        'user_id': widget.userId,
                        'workspace_id': widget.workspaceId,
                        'name': nameController.text.trim(),
                        'limit': double.tryParse(limitController.text.replaceAll(',', '.')),
                        'closing_day': int.tryParse(closingDayController.text),
                        'due_day': int.tryParse(dueDayController.text),
                      };
                      final resp = await http.post(
                        Uri.parse('$apiBaseUrl/gerenciamento-financeiro/api/credit-cards'),
                        headers: {'Content-Type': 'application/json'},
                        body: jsonEncode(payload),
                      ).timeout(const Duration(seconds: 10));
                      if (resp.statusCode == 201) {
                        final data = jsonDecode(resp.body);
                        if (data['success'] == true) {
                          await _loadCreditCards();
                          if (!context.mounted) return;
                          if (mounted) {
                            setState(() {
                              _selectedCreditCardId = data['card']['id'];
                            });
                            Navigator.pop(context);
                          }
                        }
                      }
                    } catch (e) {
                      debugPrint('Erro ao salvar cartão: $e');
                    } finally {
                      setStateDialog(() => saving = false);
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00C9A7)),
                  child: saving ? const CircularProgressIndicator(strokeWidth: 2) : const Text('Salvar'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
