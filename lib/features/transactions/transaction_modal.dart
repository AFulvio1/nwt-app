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

class _TransactionModalState extends ConsumerState<TransactionModal> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  final _amountController = TextEditingController();
  DateTime _selectedDate = DateTime.now();

  int? _selectedReferenceAccountId;
  int? _selectedCategoryId;

  @override
  void dispose() {
    _descriptionController.dispose();
    _amountController.dispose();
    super.dispose();
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

  Future<void> _submitTransaction(
    String baseCurrency,
    List<Account> accounts,
    List<Category> categories,
    List<MacroCategory> macros,
  ) async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedReferenceAccountId == null || _selectedCategoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select both an account and a category')),
      );
      return;
    }

    final double? amountDouble = double.tryParse(_amountController.text.trim());
    if (amountDouble == null || amountDouble <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid amount greater than 0')),
      );
      return;
    }

    try {
      final db = ref.read(databaseProvider);

      // Find selected category to determine if it is Revenue (Income) or Expense (Outcome)
      final category = categories.firstWhere((c) => c.id == _selectedCategoryId);
      final macro = macros.firstWhere((m) => m.id == category.macroCategoryId);

      final bool isIncome = macro.type == 'Revenue';

      // Validation: Prevent spending more than available balance on Asset accounts
      if (!isIncome) {
        final referenceAccount = accounts.firstWhere((a) => a.id == _selectedReferenceAccountId);
        final dbEntries = await (db.select(db.entries)..where((e) => e.accountId.equals(_selectedReferenceAccountId!))).get();
        int balanceCents = 0;
        for (final entry in dbEntries) {
          balanceCents += entry.amount;
        }
        final double currentBalance = balanceCents / 100.0;

        if (currentBalance < amountDouble) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Insufficient funds in ${referenceAccount.name}. '
                  'Available: ${currentBalance.toStringAsFixed(2)} $baseCurrency. '
                  'Required: ${amountDouble.toStringAsFixed(2)} $baseCurrency.',
                ),
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
            );
          }
          return;
        }
      }

      // Debit = positive, Credit = negative
      // If Income (Revenue):
      // - Reference Account is DEBIT (+)
      // - Category is CREDIT (-)
      // If Expense (Outcome):
      // - Reference Account is CREDIT (-)
      // - Category is DEBIT (+)
      final int refAmountCents = (amountDouble * 100 * (isIncome ? 1.0 : -1.0)).round();
      final int catAmountCents = (amountDouble * 100 * (isIncome ? -1.0 : 1.0)).round();

      final entriesComcompanions = [
        EntriesCompanion(
          accountId: drift.Value(_selectedReferenceAccountId!),
          categoryId: const drift.Value(null),
          amount: drift.Value(refAmountCents),
          amountInBase: drift.Value(refAmountCents), // Assuming 1.0 exchange rate
          exchangeRate: const drift.Value(1.0),
        ),
        EntriesCompanion(
          accountId: const drift.Value(null),
          categoryId: drift.Value(_selectedCategoryId!),
          amount: drift.Value(catAmountCents),
          amountInBase: drift.Value(catAmountCents), // Assuming 1.0 exchange rate
          exchangeRate: const drift.Value(1.0),
        ),
      ];

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
    final categoriesAsync = ref.watch(categoriesStreamProvider);
    final macrosAsync = ref.watch(macroCategoriesStreamProvider);
    final baseCurrencyAsync = ref.watch(baseCurrencyProvider);

    if (accountsAsync.isLoading ||
        categoriesAsync.isLoading ||
        macrosAsync.isLoading ||
        baseCurrencyAsync.isLoading) {
      return Container(
        height: 200,
        alignment: Alignment.center,
        child: const CircularProgressIndicator(),
      );
    }

    final baseCurrency = baseCurrencyAsync.value ?? 'EUR';
    final accounts = accountsAsync.value ?? [];
    final categories = categoriesAsync.value ?? [];
    final macros = macrosAsync.value ?? [];

    final referenceAccounts = accounts;
    final categoryList = categories;

    if (_selectedReferenceAccountId == null && referenceAccounts.isNotEmpty) {
      _selectedReferenceAccountId = referenceAccounts.first.id;
    }
    if (_selectedCategoryId == null && categoryList.isNotEmpty) {
      _selectedCategoryId = categoryList.first.id;
    }

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
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
                    'New Transaction',
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
              const SizedBox(height: 16),

              // Reference Account Selection
              DropdownButtonFormField<int>(
                initialValue: _selectedReferenceAccountId,
                decoration: const InputDecoration(
                  labelText: 'Reference Account',
                  hintText: 'Select account (e.g. Bank Account)',
                ),
                items: referenceAccounts.map((acc) {
                  return DropdownMenuItem<int>(
                    value: acc.id,
                    child: Text('${acc.name} (${acc.currency})'),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedReferenceAccountId = value;
                  });
                },
                validator: (value) => value == null ? 'Select reference account' : null,
              ),
              const SizedBox(height: 16),

              // Category Selection
              DropdownButtonFormField<int>(
                initialValue: _selectedCategoryId,
                decoration: const InputDecoration(
                  labelText: 'Category',
                  hintText: 'Select category (e.g. Salary, Groceries)',
                ),
                items: categoryList.map((cat) {
                  final macro = macros.firstWhere((m) => m.id == cat.macroCategoryId, orElse: () => macros.first);
                  return DropdownMenuItem<int>(
                    value: cat.id,
                    child: Text('${cat.name} (${macro.name})'),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedCategoryId = value;
                  });
                },
                validator: (value) => value == null ? 'Select category' : null,
              ),
              const SizedBox(height: 16),

              // Amount Input Field
              TextFormField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Amount',
                  suffixText: baseCurrency,
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Enter amount';
                  }
                  final double? amt = double.tryParse(value);
                  if (amt == null || amt <= 0) {
                    return 'Enter a valid amount';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),

              // Submit Button
              ElevatedButton(
                onPressed: () => _submitTransaction(baseCurrency, accounts, categories, macros),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
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
