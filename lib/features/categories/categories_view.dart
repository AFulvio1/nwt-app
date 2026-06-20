import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/database/database.dart';
import '../../shared/providers.dart';
import 'category_form_modal.dart';

class CategoriesView extends ConsumerWidget {
  const CategoriesView({super.key});

  void _showCategoryForm(BuildContext context, [Category? category]) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => CategoryFormModal(categoryToEdit: category),
    );
  }

  Future<void> _deleteCategory(BuildContext context, WidgetRef ref, Category category) async {
    final db = ref.read(databaseProvider);
    final canDelete = await db.canDeleteCategory(category.id);

    if (!context.mounted) return;

    if (!canDelete) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Cannot Delete Category'),
          content: Text(
            'The category "${category.name}" is currently associated with one or more accounts.\n\n'
            'Please reassign or delete those accounts before deleting this category.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Category'),
        content: Text('Are you sure you want to delete the category "${category.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () async {
              Navigator.of(context).pop();
              try {
                await db.deleteCategory(category.id);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Category deleted successfully')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error deleting category: $e'),
                      backgroundColor: Theme.of(context).colorScheme.error,
                    ),
                  );
                }
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(categoriesStreamProvider);
    final macrosAsync = ref.watch(macroCategoriesStreamProvider);

    return Scaffold(
      body: categoriesAsync.when(
        data: (categories) {
          return macrosAsync.when(
            data: (macros) {
              // Filter to Revenue and Expense macro categories only
              final revenueExpenseMacros = macros.where((m) => m.type == 'Revenue' || m.type == 'Expense').toList();

              // Filter categories to only Revenue and Expense categories
              final revenueExpenseCategories = categories.where((cat) {
                final macro = macros.firstWhere(
                  (m) => m.id == cat.macroCategoryId,
                  orElse: () => MacroCategory(id: -1, name: 'Unknown', type: 'Unknown'),
                );
                return macro.type == 'Revenue' || macro.type == 'Expense';
              }).toList();

              if (revenueExpenseCategories.isEmpty) {
                return _buildEmptyState(context);
              }

              // Group categories by Macro Category ID
              final categoriesByMacro = <int, List<Category>>{};
              for (final cat in revenueExpenseCategories) {
                categoriesByMacro.putIfAbsent(cat.macroCategoryId, () => []).add(cat);
              }

              return ListView.builder(
                padding: const EdgeInsets.all(16.0),
                itemCount: revenueExpenseMacros.length,
                itemBuilder: (context, index) {
                  final macro = revenueExpenseMacros[index];
                  final macroCategories = categoriesByMacro[macro.id] ?? [];

                  if (macroCategories.isEmpty) {
                    return const SizedBox.shrink();
                  }

                  return _buildMacroGroup(context, ref, macro, macroCategories);
                },
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) => Center(child: Text('Error loading macro groups: $err')),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error loading categories: $err')),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.category_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              'No Categories Found',
              style: GoogleFonts.outfit(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Tap the add button to create your first transaction category.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMacroGroup(
    BuildContext context,
    WidgetRef ref,
    MacroCategory macro,
    List<Category> categories,
  ) {
    IconData typeIcon;
    Color typeColor;

    switch (macro.type) {
      case 'Asset':
        typeIcon = Icons.trending_up;
        typeColor = Theme.of(context).colorScheme.secondary;
        break;
      case 'Liability':
        typeIcon = Icons.trending_down;
        typeColor = Theme.of(context).colorScheme.error;
        break;
      case 'Revenue':
        typeIcon = Icons.account_balance_wallet_outlined;
        typeColor = Colors.green;
        break;
      case 'Expense':
      default:
        typeIcon = Icons.shopping_bag_outlined;
        typeColor = Colors.orange;
        break;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Macro Category Header
            Row(
              children: [
                Icon(typeIcon, color: typeColor, size: 20),
                const SizedBox(width: 8),
                Text(
                  macro.name.toUpperCase(),
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: typeColor,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),

            // List of Categories under this Macro Category
            ...categories.map((category) {
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                title: Text(
                  category.name,
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                subtitle: category.description != null && category.description!.isNotEmpty
                    ? Text(
                        category.description!,
                        style: const TextStyle(fontSize: 12),
                      )
                    : null,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 20),
                      onPressed: () => _showCategoryForm(context, category),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 20, color: Colors.grey),
                      onPressed: () => _deleteCategory(context, ref, category),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
