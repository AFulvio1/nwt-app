import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as drift;
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../core/database/database.dart';
import '../../shared/providers.dart';

class TransactionModal extends ConsumerStatefulWidget {
  const TransactionModal({super.key});

  @override
  ConsumerState<TransactionModal> createState() => _TransactionModalState();
}

class _EntryInputRow {
  int? accountId;
  String accountName = '';
  String accountCurrency = 'EUR';
  bool isDebit = true; // true = Debit (+), false = Credit (-)
  double nativeAmount = 0.0;
  double exchangeRate = 1.0;
  double get baseAmount => nativeAmount * exchangeRate;
}

class _TransactionModalState extends ConsumerState<TransactionModal> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  DateTime _selectedDate = DateTime.now();

  final List<_EntryInputRow> _entries = [
    _EntryInputRow(),
    _EntryInputRow(),
  ];

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  // Calculate base sum
  double _calculateBalance() {
    double sum = 0.0;
    for (final entry in _entries) {
      final sign = entry.isDebit ? 1.0 : -1.0;
      sum += entry.baseAmount * sign;
    }
    return sum;
  }

  double _calculateTotalDebits() {
    double sum = 0.0;
    for (final entry in _entries) {
      if (entry.isDebit) sum += entry.baseAmount;
    }
    return sum;
  }

  double _calculateTotalCredits() {
    double sum = 0.0;
    for (final entry in _entries) {
      if (!entry.isDebit) sum += entry.baseAmount;
    }
    return sum;
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _submitTransaction(String baseCurrency) async {
    if (!_formKey.currentState!.validate()) return;

    final double balance = _calculateBalance();
    if (balance.abs() > 0.001) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Transaction is unbalanced by ${balance.toStringAsFixed(2)} $baseCurrency'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    try {
      final db = ref.read(databaseProvider);

      // Create companion entries
      final entriesComcompanions = _entries.map((entry) {
        final double sign = entry.isDebit ? 1.0 : -1.0;
        final int amountCents = (entry.nativeAmount * 100 * sign).round();
        final int amountBaseCents = (entry.baseAmount * 100 * sign).round();

        return EntriesCompanion(
          accountId: drift.Value(entry.accountId!),
          amount: drift.Value(amountCents),
          amountInBase: drift.Value(amountBaseCents),
          exchangeRate: drift.Value(entry.exchangeRate),
        );
      }).toList();

      final transactionCompanion = TransactionsCompanion(
        date: drift.Value(_selectedDate),
        description: drift.Value(_descriptionController.text.trim()),
      );

      await db.createBalancedTransaction(
        transaction: transactionCompanion,
        entries: entriesComcompanions,
      );

      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Transaction saved successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving transaction: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final accountsAsync = ref.watch(accountsStreamProvider);
    final baseCurrencyAsync = ref.watch(baseCurrencyProvider);

    final baseCurrency = baseCurrencyAsync.value ?? 'EUR';
    final accounts = accountsAsync.value ?? [];

    final double balance = _calculateBalance();
    final double debits = _calculateTotalDebits();
    final double credits = _calculateTotalCredits();
    final bool isBalanced = balance.abs() < 0.01;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        top: 24,
        left: 20,
        right: 20,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Modal Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'New Balanced Transaction',
                    style: GoogleFonts.outfit(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const Divider(),
              const SizedBox(height: 12),

              // Date Picker and Description Row
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: OutlinedButton.icon(
                      onPressed: () => _selectDate(context),
                      icon: const Icon(Icons.calendar_today),
                      label: Text(DateFormat('yyyy-MM-dd').format(_selectedDate)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      controller: _descriptionController,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                        hintText: 'e.g. Grocery Store',
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Enter description';
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // List of Entries
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Ledger Entries',
                    style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _entries.add(_EntryInputRow());
                      });
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Add Entry'),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Entry Rows Builder
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _entries.length,
                itemBuilder: (context, index) {
                  final entry = _entries[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: Theme.of(context).colorScheme.outline.withOpacity(0.5)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Entry #${index + 1}',
                                style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
                              ),
                              if (_entries.length > 2)
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                                  onPressed: () {
                                    setState(() {
                                      _entries.removeAt(index);
                                    });
                                  },
                                  constraints: const BoxConstraints(),
                                  padding: EdgeInsets.zero,
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          // Row 1: Account Selection
                          DropdownButtonFormField<int>(
                            value: entry.accountId,
                            decoration: const InputDecoration(labelText: 'Account'),
                            items: accounts.map((acc) {
                              return DropdownMenuItem<int>(
                                value: acc.id,
                                child: Text('${acc.name} (${acc.currency})'),
                              );
                            }).toList(),
                            onChanged: (value) {
                              setState(() {
                                entry.accountId = value;
                                final acc = accounts.firstWhere((a) => a.id == value);
                                entry.accountName = acc.name;
                                entry.accountCurrency = acc.currency;
                                entry.exchangeRate = acc.currency == baseCurrency ? 1.0 : 1.1; // Default stub conversion
                              });
                            },
                            validator: (value) => value == null ? 'Select account' : null,
                          ),
                          const SizedBox(height: 8),
                          // Row 2: Type (Debit/Credit), Amount, Exchange Rate
                          Row(
                            children: [
                              // Debit/Credit Toggle
                              Expanded(
                                flex: 3,
                                child: DropdownButtonFormField<bool>(
                                  value: entry.isDebit,
                                  decoration: const InputDecoration(labelText: 'Type'),
                                  items: const [
                                    DropdownMenuItem(value: true, child: Text('Debit (+)')),
                                    DropdownMenuItem(value: false, child: Text('Credit (-)')),
                                  ],
                                  onChanged: (val) {
                                    if (val != null) {
                                      setState(() {
                                        entry.isDebit = val;
                                      });
                                    }
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              // Amount Input
                              Expanded(
                                flex: 4,
                                child: TextFormField(
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  decoration: InputDecoration(
                                    labelText: 'Amount',
                                    suffixText: entry.accountCurrency,
                                  ),
                                  onChanged: (val) {
                                    setState(() {
                                      entry.nativeAmount = double.tryParse(val) ?? 0.0;
                                    });
                                  },
                                  validator: (value) {
                                    final val = double.tryParse(value ?? '');
                                    if (val == null || val <= 0) return 'Invalid';
                                    return null;
                                  },
                                ),
                              ),
                            ],
                          ),
                          if (entry.accountCurrency != baseCurrency) ...[
                            const SizedBox(height: 8),
                            // Row 3: Exchange rate config (only if currency is different from base)
                            Row(
                              children: [
                                Expanded(
                                  flex: 1,
                                  child: TextFormField(
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    initialValue: entry.exchangeRate.toString(),
                                    decoration: InputDecoration(
                                      labelText: 'Exchange Rate',
                                      helperText: '1 ${entry.accountCurrency} = X $baseCurrency',
                                    ),
                                    onChanged: (val) {
                                      setState(() {
                                        entry.exchangeRate = double.tryParse(val) ?? 1.0;
                                      });
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  flex: 1,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).colorScheme.outline.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      'Base: ${entry.baseAmount.toStringAsFixed(2)} $baseCurrency',
                                      style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),

              // Double-Entry Balance Bar
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isBalanced
                      ? Theme.of(context).colorScheme.secondary.withOpacity(0.15)
                      : Theme.of(context).colorScheme.error.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isBalanced ? Theme.of(context).colorScheme.secondary : Theme.of(context).colorScheme.error,
                    width: 1.5,
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Total Debits:',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        Text(
                          '${debits.toStringAsFixed(2)} $baseCurrency',
                          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.green),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Total Credits:',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        Text(
                          '${credits.toStringAsFixed(2)} $baseCurrency',
                          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.red),
                        ),
                      ],
                    ),
                    const Divider(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Balance status:',
                          style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
                        ),
                        Row(
                          children: [
                            Icon(
                              isBalanced ? Icons.check_circle_outline : Icons.warning_amber_rounded,
                              color: isBalanced ? Colors.green : Colors.red,
                              size: 20,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              isBalanced
                                  ? 'Balanced'
                                  : 'Unbalanced by ${balance.toStringAsFixed(2)} $baseCurrency',
                              style: GoogleFonts.outfit(
                                fontWeight: FontWeight.bold,
                                color: isBalanced ? Colors.green : Colors.red,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Submit Button
              ElevatedButton(
                onPressed: isBalanced ? () => _submitTransaction(baseCurrency) : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Theme.of(context).colorScheme.outline.withOpacity(0.5),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  'Record Transaction',
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}
