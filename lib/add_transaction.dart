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
  bool _isPaid = false; // Despesas iniciam como pendente
  bool _suggestingCategory = false;
  bool _categoryGenerated = false; // Controla se categoria já foi gerada
  bool _manualCategory = false;
  String _lastSuggestedDescription = '';
  bool _isRecurring = false; // Transação recorrente
  int _recurringDay = 1; // Dia do vencimento (1-31)
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

  Future<void> _deleteTransaction() async {
    if (!_isEditMode) return;

    String? scope;
    if (_isRecurring) {
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

    setState(() {
      _loading = true;
    });

    try {
      http.Response resp;
      if (kIsWeb) {
        Uri buildRemoveUri(String prefix) => Uri.parse(
          '$apiBaseUrl$prefix/api/transactions/${widget.transactionId}/remove?user_id=${widget.userId}${scope != null ? '&scope=$scope' : ''}',
        );

        var uri = buildRemoveUri('/gerenciamento-financeiro');
        resp = await http.get(uri).timeout(const Duration(seconds: 10));

        if (resp.statusCode == 404 && resp.body.toLowerCase().contains('<!doctype html>')) {
          uri = buildRemoveUri('');
          resp = await http.get(uri).timeout(const Duration(seconds: 10));
        }
      } else {
        bool isRouteMismatch(http.Response r) {
          final bodyLower = r.body.toLowerCase();
          return bodyLower.contains('<!doctype html>') ||
              bodyLower.contains('endpoint não encontrado') ||
              bodyLower.contains('endpoint nao encontrado');
        }

        Uri buildDeleteUri(String prefix) => Uri.parse(
          '$apiBaseUrl$prefix/api/transactions/${widget.transactionId}?user_id=${widget.userId}${scope != null ? '&scope=$scope' : ''}',
        );
        Uri buildRemoveUri(String prefix) => Uri.parse(
          '$apiBaseUrl$prefix/api/transactions/${widget.transactionId}/remove?user_id=${widget.userId}${scope != null ? '&scope=$scope' : ''}',
        );

        var deleteUri = buildDeleteUri('/gerenciamento-financeiro');

        resp = await http
            .delete(
              deleteUri,
              headers: {'Content-Type': 'application/json'},
            )
            .timeout(const Duration(seconds: 10));

        if (resp.statusCode == 404 || resp.statusCode == 405) {
          final fallbackUri = buildRemoveUri('/gerenciamento-financeiro');
          resp = await http
              .get(
                fallbackUri,
                headers: {'Content-Type': 'application/json'},
              )
              .timeout(const Duration(seconds: 10));
        }

        if (resp.statusCode == 404 && isRouteMismatch(resp)) {
          deleteUri = buildDeleteUri('');
          resp = await http
              .delete(
                deleteUri,
                headers: {'Content-Type': 'application/json'},
              )
              .timeout(const Duration(seconds: 10));

          if (resp.statusCode == 404 || resp.statusCode == 405) {
            final fallbackUri = buildRemoveUri('');
            resp = await http
                .get(
                  fallbackUri,
                  headers: {'Content-Type': 'application/json'},
                )
                .timeout(const Duration(seconds: 10));
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
        Navigator.of(context).pop(true);
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
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

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
    
    // Listener para quando campo valor receber foco
    _amountFocusNode.addListener(() {
      if (_amountFocusNode.hasFocus) {
        final text = _descriptionController.text.trim();
        if (text.length >= 3 && !_suggestingCategory && !_categoryGenerated) {
          _suggestCategory(text);
        }
      }
    });
  }

  Future<void> _loadTransactionForEdit() async {
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

      final resp = await http.get(uri, headers: {'Content-Type': 'application/json'});

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
        
        // Se for cartão de crédito, mover o nome para o campo específico
        if (_paymentMethod == 'credito' && subText != null && subText.isNotEmpty) {
          _cardNameController.text = subText;
          _subcategoryController.clear();
        }

        _paymentMethod = _normalizePaymentMethod(tx['payment_method']);
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

  Widget _buildRecurringEndMode() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
      ),
      child: Column(
        children: [
          if (_type == 'expense') ...[
            Row(
              children: [
                Icon(Icons.format_list_numbered, color: Colors.white.withOpacity(0.5), size: 22),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    'Parcelado',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 15,
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
                Icon(Icons.all_inclusive, color: Colors.white.withOpacity(0.5), size: 22),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    'Sem fim (ilimitado)',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 15,
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
          ],
          if (!_recurringUnlimited && _type == 'expense') ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withOpacity(0.10)),
              ),
              child: Row(
                children: [
                  Icon(Icons.play_arrow_rounded, color: Colors.white.withOpacity(0.5), size: 22),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      'Começar',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 15,
                      ),
                    ),
                  ),
                  DropdownButton<String>(
                    value: _recurringInstallmentsStart,
                    dropdownColor: const Color(0xFF1A2A35),
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                    underline: Container(),
                    items: const [
                      DropdownMenuItem<String>(
                        value: 'current_month',
                        child: Text('Mês atual'),
                      ),
                      DropdownMenuItem<String>(
                        value: 'due_date',
                        child: Text('No vencimento'),
                      ),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() {
                        _recurringInstallmentsStart = v;
                      });
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withOpacity(0.10)),
              ),
              child: Row(
                children: [
                  Icon(Icons.confirmation_number_outlined, color: Colors.white.withOpacity(0.5), size: 22),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      'Parcelas',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 15,
                      ),
                    ),
                  ),
                  DropdownButton<int>(
                    value: _recurringInstallments < 1 ? 1 : _recurringInstallments,
                    dropdownColor: const Color(0xFF1A2A35),
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                    underline: Container(),
                    items: List.generate(36, (index) => index + 1)
                        .map((n) => DropdownMenuItem<int>(
                              value: n,
                              child: Text('$n'),
                            ))
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() {
                        _recurringInstallments = v;
                      });
                    },
                  ),
                ],
              ),
            ),
          ],
          if (!_recurringUnlimited && _type != 'expense') ...[
            const SizedBox(height: 14),
            GestureDetector(
              onTap: _pickRecurringEndMonthYear,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withOpacity(0.10)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.event, color: Colors.white.withOpacity(0.5), size: 22),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Até quando',
                            style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${_recurringEndMonth.toString().padLeft(2, '0')}/${_recurringEndYear}',
                            style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.arrow_forward_ios, color: Colors.white.withOpacity(0.3), size: 16),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
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

  void _onDescriptionChanged() {
    final current = _descriptionController.text.trim();

    // Se o usuário alterou a descrição depois de já ter gerado a categoria,
    // invalidar a sugestão atual e forçar uma nova geração ao focar no campo Valor.
    if (_categoryGenerated && current != _lastSuggestedDescription) {
      setState(() {
        _categoryGenerated = false;
        _categoryController.clear();
        _subcategoryController.clear();
      });
    }

    // Se apagar a descrição, limpar tudo.
    if (current.isEmpty && (_categoryController.text.isNotEmpty || _subcategoryController.text.isNotEmpty)) {
      setState(() {
        _categoryGenerated = false;
        _lastSuggestedDescription = '';
        _categoryController.clear();
        _subcategoryController.clear();
      });
    }

    // Rebuild to avaliar fluxo de cartão quando o usuário digita "cartão"
    setState(() {});
  }

  Future<void> _suggestCategory(String description) async {
    // Evitar múltiplas chamadas simultâneas
    if (_suggestingCategory) {
      return;
    }
    
    setState(() {
      _suggestingCategory = true;
      _categoryGenerated = false;
      _manualCategory = false;
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
        final preview = resp.body.length > 180 ? resp.body.substring(0, 180) : resp.body;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(msg ?? 'Falha ao sugerir categoria (HTTP ${resp.statusCode}).'),
              backgroundColor: Colors.red,
            ),
          );
          setState(() {
            _manualCategory = true;
          });
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

            // Sincronizar com o texto atual para não invalidar a sugestão
            // quando o usuário continuou digitando enquanto a IA respondia.
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
        setState(() {
          _manualCategory = true;
        });
      }
    } on TimeoutException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Timeout ao sugerir categoria: $e'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
        setState(() {
          _manualCategory = true;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Falha ao sugerir categoria.'),
            backgroundColor: Color(0xFFEF4444),
          ),
        );
        setState(() {
          _manualCategory = true;
        });
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
    if (!_formKey.currentState!.validate()) return;

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
        'payment_method': _type == 'expense' ? _paymentMethod : null,
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

      // Garantir que a transação seja vinculada ao workspace ativo
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
        Navigator.of(context).pop(true);
        return;
      }

      final msg = data['message']?.toString() ?? 'Erro ao salvar transação.';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Falha de conexão: ${e.toString().substring(0, 100)}'),
            duration: const Duration(seconds: 5),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditMode ? 'Editar transação' : 'Nova transação', style: const TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (_isEditMode)
            IconButton(
              onPressed: _loading ? null : _deleteTransaction,
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Excluir',
            ),
        ],
      ),
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          Container(
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
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 100, 20, 20),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
              _buildSectionTitle('Tipo de transação'),
              const SizedBox(height: 10),
              _buildTypeSelector(),
              const SizedBox(height: 24),
              _buildSectionTitle('Informações básicas'),
              const SizedBox(height: 10),
                    _buildModernTextField(
                      controller: _descriptionController,
                      label: 'Descrição',
                      icon: Icons.description_outlined,
                      validator: (v) => (v ?? '').trim().isEmpty ? 'Informe a descrição' : null,
                    ),
                    const SizedBox(height: 14),
                    _buildAmountFieldWithAutoSuggest(),
              const SizedBox(height: 14),
              _buildModernTextField(
                controller: _categoryController,
                label: 'Categoria',
                icon: Icons.category_outlined,
                readOnly: !_manualCategory,
              ),
              const SizedBox(height: 14),
              _buildModernTextField(
                controller: _subcategoryController,
                label: 'Subcategoria',
                icon: Icons.label_outlined,
                readOnly: !_manualCategory,
              ),
              // Campo nome do cartão aparece quando fluxo de cartão for detectado
              if (_isCardFlow) ...[
                const SizedBox(height: 14),
                _buildModernTextField(
                  controller: _cardNameController,
                  label: 'Nome do cartão',
                  icon: Icons.credit_card,
                ),
              ],
              if (_type == 'income' && _isSalaryCategory) ...[
                const SizedBox(height: 14),
                _buildModernTextField(
                  controller: _salaryFromController,
                  label: 'De quem é o salário?',
                  icon: Icons.person_outline,
                ),
              ],
              const SizedBox(height: 24),
              _buildSectionTitle('Detalhes'),
              const SizedBox(height: 10),
              _buildRecurringSwitch(),
              if (_isRecurring) const SizedBox(height: 14),
              if (_isRecurring) _buildRecurringDayPicker(),
              if (_isRecurring) const SizedBox(height: 14),
              if (_isRecurring) _buildRecurringEndMode(),
              const SizedBox(height: 14),
              if (!_isRecurring) _buildDatePicker(),
              if (!_isRecurring) const SizedBox(height: 14),

              if (_type == 'expense') _buildPaymentMethodDropdown(),
              if (_type == 'expense') const SizedBox(height: 14),
              if (_type == 'expense') _buildPaidSwitch(),
              if (_type == 'expense') const SizedBox(height: 14),
              if (_isEditMode) ...[
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton.icon(
                    onPressed: _loading ? null : _deleteTransaction,
                    icon: const Icon(Icons.delete_outline, color: Color(0xFFEF4444)),
                    label: const Text(
                      'Excluir transação',
                      style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFFEF4444)),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFEF4444)),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
              ],
              const SizedBox(height: 32),
              _buildSubmitButton(),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ),
          // Overlay de loading quando IA está processando ou carregando edição
          if (_suggestingCategory || (_isEditMode && _loading))
            Container(
              color: Colors.black.withOpacity(0.7),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 60,
                      height: 60,
                      child: CircularProgressIndicator(
                        strokeWidth: 4,
                        valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00C9A7)),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          Text(
                            _suggestingCategory ? 'IA gerando categoria...' : 'Carregando transação...',
                            style: TextStyle(
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
                              fontSize: 13,
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
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        color: Colors.white.withOpacity(0.9),
        fontSize: 16,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.3,
      ),
    );
  }

  Widget _buildTypeSelector() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildTypeButton(
              label: 'Despesa',
              icon: Icons.arrow_upward,
              color: const Color(0xFFEF4444),
              isSelected: _type == 'expense',
              onTap: () {
                setState(() {
                  _type = 'expense';
                  _isPaid = false; // Despesa = pendente
                  _categoryController.clear();
                  _subcategoryController.clear();
                  _categoryGenerated = false; // Reseta flag ao trocar tipo
                  _manualCategory = false;
                  _salaryFromController.clear();
                  _isRecurring = false; // Reseta recorrente
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
          Expanded(
            child: _buildTypeButton(
              label: 'Receita',
              icon: Icons.arrow_downward,
              color: const Color(0xFF10B981),
              isSelected: _type == 'income',
              onTap: () {
                setState(() {
                  _type = 'income';
                  _isPaid = true; // Receita = paga
                  _categoryController.clear();
                  _subcategoryController.clear();
                  _categoryGenerated = false; // Reseta flag ao trocar tipo
                  _manualCategory = false;
                  _salaryFromController.clear();
                  _isRecurring = false; // Reseta recorrente
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
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: isSelected ? Border.all(color: color.withOpacity(0.4), width: 2) : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: isSelected ? color : Colors.white.withOpacity(0.5), size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? color : Colors.white.withOpacity(0.5),
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAmountFieldWithAutoSuggest() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
      ),
      child: TextFormField(
        controller: _amountController,
        focusNode: _amountFocusNode,
        keyboardType: TextInputType.number,
        style: const TextStyle(color: Colors.white, fontSize: 15),
        decoration: InputDecoration(
          labelText: 'Valor',
          labelStyle: TextStyle(color: Colors.white.withOpacity(0.6)),
          prefixIcon: Icon(Icons.attach_money, color: Colors.white.withOpacity(0.5), size: 22),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
      ),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        maxLines: maxLines,
        readOnly: readOnly,
        style: const TextStyle(color: Colors.white, fontSize: 15),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: Colors.white.withOpacity(0.6)),
          prefixIcon: Icon(icon, color: Colors.white.withOpacity(0.5), size: 22),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
        validator: validator,
      ),
    );
  }

  Widget _buildPaymentMethodDropdown() {
    final methods = [
      {'value': '', 'label': 'Não informado'},
      {'value': 'dinheiro', 'label': 'Dinheiro'},
      {'value': 'pix', 'label': 'PIX'},
      {'value': 'debito', 'label': 'Débito'},
      {'value': 'credito', 'label': 'Cartão de crédito'},
      {'value': 'transferencia', 'label': 'Transferência'},
      {'value': 'boleto', 'label': 'Boleto'},
    ];

    final paymentMethodValue = (_paymentMethod != null && methods.any((m) => m['value'] == _paymentMethod))
        ? _paymentMethod!
        : '';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: DropdownButtonFormField<String>(
        value: paymentMethodValue,
        dropdownColor: const Color(0xFF1A2A35),
        style: const TextStyle(color: Colors.white, fontSize: 15),
        decoration: InputDecoration(
          labelText: 'Forma de pagamento',
          labelStyle: TextStyle(color: Colors.white.withOpacity(0.6)),
          prefixIcon: Icon(Icons.payment, color: Colors.white.withOpacity(0.5), size: 22),
          border: InputBorder.none,
        ),
        items: methods
            .map((m) => DropdownMenuItem<String>(
                  value: m['value'] as String,
                  child: Text(m['label'] as String),
                ))
            .toList(),
        onChanged: (v) {
          setState(() {
            _paymentMethod = (v == null || v.isEmpty) ? null : v;
            if (_paymentMethod != 'credito') {
              _subcategoryController.clear();
            }
          });
        },
      ),
    );
  }

  Widget _buildDatePicker() {
    final dateLabel = _type == 'expense' ? 'Data de vencimento' : 'Data da transação';
    
    return GestureDetector(
      onTap: _pickDate,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.10)),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today, color: Colors.white.withOpacity(0.5), size: 22),
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
                    style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
      ),
      child: Row(
        children: [
          Icon(Icons.repeat, color: Colors.white.withOpacity(0.5), size: 22),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              _type == 'income'
                  ? 'Receita recorrente (todo mês)'
                  : 'Despesa recorrente (todo mês)',
              style: TextStyle(
                color: Colors.white.withOpacity(0.9),
                fontSize: 15,
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
      ),
      child: Row(
        children: [
          Icon(Icons.calendar_today, color: Colors.white.withOpacity(0.5), size: 22),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              _type == 'income' ? 'Dia de recebimento' : 'Dia de vencimento',
              style: TextStyle(
                color: Colors.white.withOpacity(0.9),
                fontSize: 15,
              ),
            ),
          ),
          DropdownButton<int>(
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
        ],
      ),
    );
  }

  Widget _buildPaidSwitch() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle_outline, color: Colors.white.withOpacity(0.5), size: 22),
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

  Widget _buildSubmitButton() {
    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF00C9A7), Color(0xFF00B4D8)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00C9A7).withOpacity(0.35),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: _loading ? null : _submit,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        child: _loading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.check_circle, size: 22),
                  SizedBox(width: 10),
                  Text('Salvar transação', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                ],
              ),
      ),
    );
  }
}

class _CategoryItem {
  final int id;
  final String name;

  _CategoryItem({required this.id, required this.name});
}
