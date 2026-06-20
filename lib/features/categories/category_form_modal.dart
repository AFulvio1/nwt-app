import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as drift;
import 'package:google_fonts/google_fonts.dart';
import '../../core/database/database.dart';
import '../../shared/providers.dart';

class CategoryFormModal extends ConsumerStatefulWidget {
  final Category? categoryToEdit;

  const CategoryFormModal({
    super.key,
    this.categoryToEdit,
  });

  @override
  ConsumerState<CategoryFormModal> createState() => _CategoryFormModalState();
}

class _CategoryFormModalState extends ConsumerState<CategoryFormModal> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  int? _selectedMacroCategoryId;

  @override
  void initState() {
    super.initState();
    if (widget.categoryToEdit != null) {
      _nameController.text = widget.categoryToEdit!.name;
      _descriptionController.text = widget.categoryToEdit!.description ?? '';
      _selectedMacroCategoryId = widget.categoryToEdit!.macroCategoryId;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submit(List<MacroCategory> macros) async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedMacroCategoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a macro category')),
      );
      return;
    }

    try {
      final db = ref.read(databaseProvider);
      final name = _nameController.text.trim();
      final desc = _descriptionController.text.trim();

      if (widget.categoryToEdit == null) {
        // Create
        final companion = CategoriesCompanion(
          name: drift.Value(name),
          macroCategoryId: drift.Value(_selectedMacroCategoryId!),
          description: desc.isNotEmpty ? drift.Value(desc) : const drift.Value.absent(),
        );
        await db.addCategory(companion);
      } else {
        // Update
        final updated = widget.categoryToEdit!.copyWith(
          name: name,
          macroCategoryId: _selectedMacroCategoryId!,
          description: drift.Value(desc.isNotEmpty ? desc : null),
        );
        await db.updateCategory(updated);
      }

      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.categoryToEdit == null
                ? 'Category added successfully'
                : 'Category updated successfully'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving category: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final macrosAsync = ref.watch(macroCategoriesStreamProvider);

    return macrosAsync.when(
      data: (macros) {
        // Filter macros to Revenue and Expense only
        final revenueExpenseMacros = macros.where((m) => m.type == 'Revenue' || m.type == 'Expense').toList();

        if (_selectedMacroCategoryId == null && revenueExpenseMacros.isNotEmpty) {
          _selectedMacroCategoryId = revenueExpenseMacros.first.id;
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
                        widget.categoryToEdit == null ? 'Add Category' : 'Edit Category',
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
                      labelText: 'Category Name',
                      hintText: 'e.g. Entertainment, Health',
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter category name';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int>(
                    initialValue: _selectedMacroCategoryId,
                    decoration: const InputDecoration(
                      labelText: 'Macro Category Group',
                    ),
                    items: revenueExpenseMacros.map((macro) {
                      return DropdownMenuItem<int>(
                        value: macro.id,
                        child: Text('${macro.name} (${macro.type})'),
                      );
                    }).toList(),
                    onChanged: widget.categoryToEdit != null
                        ? null // Disable type change on edit to preserve ledger structural integrity
                        : (value) {
                            setState(() {
                              _selectedMacroCategoryId = value;
                            });
                          },
                    validator: (value) => value == null ? 'Select macro category' : null,
                  ),
                  if (widget.categoryToEdit != null) ...[
                    const SizedBox(height: 4),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        'Macro group cannot be changed for existing categories.',
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
                      hintText: 'Describe this category...',
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () => _submit(macros),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      widget.categoryToEdit == null ? 'Add Category' : 'Save Changes',
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
  }
}
