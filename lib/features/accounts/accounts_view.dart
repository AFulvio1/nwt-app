import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../core/database/database.dart';
import '../../shared/providers.dart';
import 'account_form_modal.dart';

class AccountsView extends ConsumerWidget {
  const AccountsView({super.key});

  void _showAccountForm(BuildContext context, [Account? account]) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => AccountFormModal(accountToEdit: account),
    );
  }

  Future<void> _deleteAccount(BuildContext context, WidgetRef ref, Account account) async {
    final db = ref.read(databaseProvider);
    final canDelete = await db.canDeleteAccount(account.id);

    if (!context.mounted) return;

    if (!canDelete) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Cannot Delete Account'),
          content: Text(
            'The account "${account.name}" already has transaction entries in the ledger.\n\n'
            'To keep your historical financial records intact, you cannot delete this account. '
            'Instead, you can set it to "Inactive" so it is hidden from future transactions.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(context).pop();
                try {
                  final deactivated = account.copyWith(isActive: false);
                  await db.updateAccount(deactivated);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Account deactivated successfully')),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Error deactivating account: $e'),
                        backgroundColor: Theme.of(context).colorScheme.error,
                      ),
                    );
                  }
                }
              },
              child: const Text('Deactivate'),
            ),
          ],
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Account'),
        content: Text('Are you sure you want to delete the account "${account.name}"?'),
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
                await db.deleteAccount(account.id);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Account deleted successfully')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error deleting account: $e'),
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
    final accountsAsync = ref.watch(allAccountsStreamProvider);
    final balancesAsync = ref.watch(accountBalancesProvider);

    return Scaffold(
      body: accountsAsync.when(
        data: (accounts) {
          if (accounts.isEmpty) {
            return _buildEmptyState(context);
          }

          // Group accounts by type (bank vs cash)
          final bankAccounts = accounts.where((a) => a.type == 'bank').toList();
          final cashAccounts = accounts.where((a) => a.type == 'cash').toList();
          final balances = balancesAsync.value ?? {};

          return ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              if (bankAccounts.isNotEmpty)
                _buildAccountGroup(
                  context,
                  ref,
                  'Bank Accounts',
                  Icons.account_balance,
                  Theme.of(context).colorScheme.primary,
                  bankAccounts,
                  balances,
                ),
              if (cashAccounts.isNotEmpty)
                _buildAccountGroup(
                  context,
                  ref,
                  'Cash Wallets',
                  Icons.wallet_outlined,
                  Theme.of(context).colorScheme.secondary,
                  cashAccounts,
                  balances,
                ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error loading accounts: $err')),
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
              Icons.account_balance_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              'No Accounts Found',
              style: GoogleFonts.outfit(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Tap the add button to create your first account (e.g. Bank Account, Cash Wallet).',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountGroup(
    BuildContext context,
    WidgetRef ref,
    String title,
    IconData typeIcon,
    Color typeColor,
    List<Account> accounts,
    Map<int, double> balances,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Group Header
            Row(
              children: [
                Icon(typeIcon, color: typeColor, size: 20),
                const SizedBox(width: 8),
                Text(
                  title.toUpperCase(),
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

            // List of Accounts under this group
            ...accounts.map((account) {
              final double balance = balances[account.id] ?? 0.0;
              final formatter = NumberFormat.simpleCurrency(name: account.currency, decimalDigits: 2);
              final formattedBalance = formatter.format(balance);

              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                title: Row(
                  children: [
                    Expanded(
                      child: Text(
                        account.name,
                        style: GoogleFonts.outfit(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: account.isActive
                              ? Theme.of(context).textTheme.bodyLarge?.color
                              : Theme.of(context).textTheme.bodyLarge?.color?.withValues(alpha: 0.5),
                          decoration: account.isActive ? null : TextDecoration.lineThrough,
                        ),
                      ),
                    ),
                    if (!account.isActive) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'Inactive',
                          style: TextStyle(
                            fontSize: 10,
                            color: Theme.of(context).textTheme.bodySmall?.color,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                subtitle: account.description != null && account.description!.isNotEmpty
                    ? Text(
                        account.description!,
                        style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic),
                      )
                    : null,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      formattedBalance,
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: balance >= 0 ? Colors.green : Colors.red,
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 20),
                      onPressed: () => _showAccountForm(context, account),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 20, color: Colors.grey),
                      onPressed: () => _deleteAccount(context, ref, account),
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
