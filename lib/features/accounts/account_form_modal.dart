import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as drift;
import 'package:google_fonts/google_fonts.dart';
import '../../core/database/database.dart';
import '../../shared/providers.dart';

class AccountFormModal extends ConsumerStatefulWidget {
  final Account? accountToEdit;

  const AccountFormModal({
    super.key,
    this.accountToEdit,
  });

  @override
  ConsumerState<AccountFormModal> createState() => _AccountFormModalState();
}

class _AccountFormModalState extends ConsumerState<AccountFormModal> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  int? _selectedCategoryId;
  String _selectedCurrency = 'EUR';
  bool _isActive = true;

  final List<String> _currencies = ['EUR', 'USD', 'GBP', 'CHF', 'JPY', 'CAD', 'AUD'];

  @override
  void initState() {
    super.initState();
    if (widget.accountToEdit != null) {
      _nameController.text = widget.accountToEdit!.name;
      _descriptionController.text = widget.accountToEdit!.description ?? '';
      _selectedCategoryId = widget.accountToEdit!.categoryId;
      _selectedCurrency = widget.accountToEdit!.currency;
      _isActive = widget.accountToEdit!.isActive;
    } else {
      // Default to base currency if available
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final baseCurrency = await ref.read(baseCurrencyProvider.future);
        if (mounted && widget.accountToEdit == null) {
          setState(() {
            if (_currencies.contains(baseCurrency)) {
              _selectedCurrency = baseCurrency;
            } else {
              _selectedCurrency = baseCurrency;
              if (!_currencies.contains(baseCurrency)) {
                _currencies.add(baseCurrency);
              }
            }
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCategoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a category')),
      );
      return;
    }

    try {
      final db = ref.read(databaseProvider);
      final name = _nameController.text.trim();
      final desc = _descriptionController.text.trim();

      if (widget.accountToEdit == null) {
        // Create
        final companion = AccountsCompanion(
          name: drift.Value(name),
          categoryId: drift.Value(_selectedCategoryId!),
          currency: drift.Value(_selectedCurrency),
          description: desc.isNotEmpty ? drift.Value(desc) : const drift.Value.absent(),
          isActive: const drift.Value(true),
        );
        await db.addAccount(companion);
      } else {
        // Update
        final updated = widget.accountToEdit!.copyWith(
          name: name,
          categoryId: _selectedCategoryId!,
          currency: _selectedCurrency,
          description: drift.Value(desc.isNotEmpty ? desc : null),
          isActive: _isActive,
        );
        await db.updateAccount(updated);
      }

      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.accountToEdit == null
                ? 'Account created successfully'
                : 'Account updated successfully'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving account: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(categoriesStreamProvider);
    final macrosAsync = ref.watch(macroCategoriesStreamProvider);

    return categoriesAsync.when(
      data: (categories) {
        return macrosAsync.when(
          data: (macros) {
            // Filter to Asset categories only
            final assetCategories = categories.where((cat) {
              final macro = macros.firstWhere(
                (m) => m.id == cat.macroCategoryId,
                orElse: () => MacroCategory(id: -1, name: 'Unknown', type: 'Unknown'),
              );
              return macro.type == 'Asset';
            }).toList();

            if (_selectedCategoryId == null && assetCategories.isNotEmpty) {
              _selectedCategoryId = assetCategories.first.id;
            }

            return Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
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
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            widget.accountToEdit == null ? 'Create Account' : 'Edit Account',
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
                      TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Account Name',
                          hintText: 'e.g. Chase Checkings, Cash Wallet',
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter account name';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<int>(
                        initialValue: _selectedCategoryId,
                        decoration: const InputDecoration(
                          labelText: 'Category',
                        ),
                        items: assetCategories.map((cat) {
                          final macro = macros.firstWhere(
                            (m) => m.id == cat.macroCategoryId,
                            orElse: () => MacroCategory(id: -1, name: 'Unknown', type: 'Unknown'),
                          );
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
                      DropdownButtonFormField<String>(
                        initialValue: _selectedCurrency,
                        decoration: const InputDecoration(
                          labelText: 'Currency',
                        ),
                        items: _currencies.map((curr) {
                          return DropdownMenuItem<String>(
                            value: curr,
                            child: Text(curr),
                          );
                        }).toList(),
                        onChanged: widget.accountToEdit != null
                            ? null // Disable currency modification on edit to preserve transaction ledger logic
                            : (value) {
                                if (value != null) {
                                  setState(() {
                                    _selectedCurrency = value;
                                  });
                                }
                              },
                        validator: (value) => value == null ? 'Select currency' : null,
                      ),
                      if (widget.accountToEdit != null) ...[
                        const SizedBox(height: 4),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Text(
                            'Currency cannot be changed for existing accounts.',
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.7),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _descriptionController,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Description (Optional)',
                          hintText: 'Describe this account...',
                        ),
                      ),
                      if (widget.accountToEdit != null) ...[
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Active Status',
                                  style: GoogleFonts.outfit(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                                Text(
                                  'Inactive accounts are hidden in selection dropdowns.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(context).textTheme.bodySmall?.color,
                                  ),
                                ),
                              ],
                            ),
                            Switch(
                              value: _isActive,
                              onChanged: (value) {
                                setState(() {
                                  _isActive = value;
                                });
                              },
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          widget.accountToEdit == null ? 'Create Account' : 'Save Changes',
                          style: GoogleFonts.outfit(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
          loading: () => Container(
            height: 200,
            alignment: Alignment.center,
            child: const CircularProgressIndicator(),
          ),
          error: (e, _) => Container(
            height: 100,
            alignment: Alignment.center,
            child: Text('Error loading macro categories: $e'),
          ),
        );
      },
      loading: () => Container(
        height: 200,
        alignment: Alignment.center,
        child: const CircularProgressIndicator(),
      ),
      error: (e, _) => Container(
        height: 100,
        alignment: Alignment.center,
        child: Text('Error loading categories: $e'),
      ),
    );
  }
}
