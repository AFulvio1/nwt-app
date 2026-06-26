import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../core/database/database.dart';
import '../../shared/providers.dart';
import 'transactions_filter.dart';
import 'csv_export_service.dart';

const List<Color> _chartColors = [
  Colors.blue,
  Colors.green,
  Colors.orange,
  Colors.purple,
  Colors.red,
  Colors.teal,
  Colors.amber,
  Colors.indigo,
  Colors.pink,
  Colors.cyan,
];

class TransactionsView extends ConsumerStatefulWidget {
  const TransactionsView({super.key});

  @override
  ConsumerState<TransactionsView> createState() => _TransactionsViewState();
}

class _TransactionsViewState extends ConsumerState<TransactionsView> {
  final _searchController = TextEditingController();
  bool _showFilters = false;
  String _activeTab = 'history'; // 'history' or 'analysis'
  String _analysisType = 'Expense'; // 'Expense' or 'Income'
  int? _touchedIndex;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final currentFilter = ref.read(transactionsFilterProvider);
      _searchController.text = currentFilter.searchQuery;
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _clearFilters() {
    _searchController.clear();
    ref.read(transactionsFilterProvider.notifier).setFilter(TransactionsFilter());
  }

  bool _hasActiveFilters(TransactionsFilter filter) {
    return filter.accountId != null ||
        filter.categoryId != null ||
        filter.dateFilter != DateFilterType.all ||
        filter.transactionType != 'All';
  }

  int _getActiveFiltersCount(TransactionsFilter filter) {
    int count = 0;
    if (filter.accountId != null) count++;
    if (filter.categoryId != null) count++;
    if (filter.dateFilter != DateFilterType.all) count++;
    if (filter.transactionType != 'All') count++;
    return count;
  }

  Future<void> _selectCustomDateRange(BuildContext context, TransactionsFilter filter) async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDateRange: filter.customDateRange ??
          DateTimeRange(
            start: DateTime.now().subtract(const Duration(days: 7)),
            end: DateTime.now(),
          ),
    );
    if (picked != null) {
      ref.read(transactionsFilterProvider.notifier).setFilter(filter.copyWith(
        dateFilter: DateFilterType.custom,
        customDateRange: () => picked,
      ));
    }
  }

  void _showDoubleEntryDialog(
    BuildContext context,
    TransactionWithEntries txWithEntries,
    NumberFormat formatter,
    List<Account> accounts,
    List<Category> categories,
  ) {
    final tx = txWithEntries.transaction;
    final entries = txWithEntries.entries;
    final accountMap = {for (var a in accounts) a.id: a};
    final categoryMap = {for (var c in categories) c.id: c};

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Ledger Double-Entry',
                style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              const SizedBox(height: 4),
              Text(
                tx.description,
                style: GoogleFonts.outfit(fontSize: 14, color: Colors.grey),
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: [
                Text(
                  'Recorded on: ${DateFormat('yyyy-MM-dd HH:mm').format(tx.date)}',
                  style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),
                Text(
                  'DEBITS (Positive / Inflow)',
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: Colors.green,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 6),
                ...entries.where((e) => e.amount >= 0).map((entry) {
                  final String name = entry.accountId != null
                      ? 'Account: ${accountMap[entry.accountId]?.name ?? 'Unknown'}'
                      : 'Category: ${categoryMap[entry.categoryId]?.name ?? 'Unknown'}';
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: const Icon(Icons.arrow_downward, color: Colors.green, size: 16),
                    title: Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                    trailing: Text(
                      '+${formatter.format(entry.amount / 100.0)}',
                      style: GoogleFonts.outfit(color: Colors.green, fontWeight: FontWeight.bold),
                    ),
                  );
                }),
                const SizedBox(height: 16),
                Text(
                  'CREDITS (Negative / Outflow)',
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: Colors.red,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 6),
                ...entries.where((e) => e.amount < 0).map((entry) {
                  final String name = entry.accountId != null
                      ? 'Account: ${accountMap[entry.accountId]?.name ?? 'Unknown'}'
                      : 'Category: ${categoryMap[entry.categoryId]?.name ?? 'Unknown'}';
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: const Icon(Icons.arrow_upward, color: Colors.red, size: 16),
                    title: Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                    trailing: Text(
                      formatter.format(entry.amount / 100.0),
                      style: GoogleFonts.outfit(color: Colors.red, fontWeight: FontWeight.bold),
                    ),
                  );
                }),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline, size: 16, color: Colors.grey),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Double-entry validation ensures total debits equal total credits in base currency (Sum = 0.00).',
                          style: TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(transactionsFilterProvider);
    final filteredTxs = ref.watch(filteredTransactionsProvider);
    final analysisData = ref.watch(analysisDataProvider);

    final accountsAsync = ref.watch(allAccountsStreamProvider);
    final categoriesAsync = ref.watch(categoriesStreamProvider);
    final macrosAsync = ref.watch(macroCategoriesStreamProvider);
    final baseCurrencyAsync = ref.watch(baseCurrencyProvider);

    if (accountsAsync.isLoading ||
        categoriesAsync.isLoading ||
        macrosAsync.isLoading ||
        baseCurrencyAsync.isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final accounts = accountsAsync.value ?? [];
    final categories = categoriesAsync.value ?? [];
    final baseCurrency = baseCurrencyAsync.value ?? 'EUR';
    final formatter = NumberFormat.simpleCurrency(name: baseCurrency, decimalDigits: 2);

    return Scaffold(
      body: Column(
        children: [
          // 1. Search Bar & Toggle Panels
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, top: 12, bottom: 8),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: 'Search description...',
                          prefixIcon: const Icon(Icons.search, size: 20),
                          suffixIcon: _searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 18),
                                  onPressed: () {
                                    _searchController.clear();
                                    ref.read(transactionsFilterProvider.notifier).setFilter(
                                        filter.copyWith(searchQuery: ''));
                                  },
                                )
                              : null,
                          contentPadding: const EdgeInsets.symmetric(vertical: 0),
                        ),
                        onChanged: (val) {
                          ref.read(transactionsFilterProvider.notifier).setFilter(
                              filter.copyWith(searchQuery: val.trim()));
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        IconButton.filledTonal(
                          onPressed: () {
                            setState(() {
                              _showFilters = !_showFilters;
                            });
                          },
                          icon: Icon(
                            _showFilters ? Icons.filter_list_off : Icons.filter_list,
                            color: _hasActiveFilters(filter) ? Theme.of(context).colorScheme.primary : null,
                          ),
                        ),
                        if (_hasActiveFilters(filter))
                          Positioned(
                            right: -2,
                            top: -2,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                '${_getActiveFiltersCount(filter)}',
                                style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                              ),
                            ),
                          )
                      ],
                    ),
                  ],
                ),

                // Expanded Filters section
                AnimatedCrossFade(
                  firstChild: const SizedBox.shrink(),
                  secondChild: Container(
                    margin: const EdgeInsets.only(top: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.15)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Account & Category dropdown row
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<int?>(
                                initialValue: filter.accountId,
                                decoration: const InputDecoration(
                                  labelText: 'Account',
                                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                ),
                                style: const TextStyle(fontSize: 12),
                                items: [
                                  const DropdownMenuItem(value: null, child: Text('All Accounts')),
                                  ...accounts.map(
                                    (a) => DropdownMenuItem(
                                      value: a.id,
                                      child: Text(a.name, overflow: TextOverflow.ellipsis),
                                    ),
                                  ),
                                ],
                                onChanged: (val) {
                                  ref.read(transactionsFilterProvider.notifier).setFilter(filter.copyWith(
                                    accountId: () => val,
                                  ));
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: DropdownButtonFormField<int?>(
                                initialValue: filter.categoryId,
                                decoration: const InputDecoration(
                                  labelText: 'Category',
                                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                ),
                                style: const TextStyle(fontSize: 12),
                                items: [
                                  const DropdownMenuItem(value: null, child: Text('All Categories')),
                                  ...categories.map(
                                    (c) => DropdownMenuItem(
                                      value: c.id,
                                      child: Text(c.name, overflow: TextOverflow.ellipsis),
                                    ),
                                  ),
                                ],
                                onChanged: (val) {
                                  ref.read(transactionsFilterProvider.notifier).setFilter(filter.copyWith(
                                    categoryId: () => val,
                                  ));
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),

                        // Date period selection row
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<DateFilterType>(
                                initialValue: filter.dateFilter,
                                decoration: const InputDecoration(
                                  labelText: 'Period',
                                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                ),
                                style: const TextStyle(fontSize: 12),
                                items: const [
                                  DropdownMenuItem(value: DateFilterType.all, child: Text('All Time')),
                                  DropdownMenuItem(value: DateFilterType.thisWeek, child: Text('This Week')),
                                  DropdownMenuItem(value: DateFilterType.thisMonth, child: Text('This Month')),
                                  DropdownMenuItem(value: DateFilterType.last30Days, child: Text('Last 30 Days')),
                                  DropdownMenuItem(value: DateFilterType.thisYear, child: Text('This Year')),
                                  DropdownMenuItem(value: DateFilterType.custom, child: Text('Custom Range...')),
                                ],
                                onChanged: (val) {
                                  if (val == DateFilterType.custom) {
                                    _selectCustomDateRange(context, filter);
                                  } else {
                                    ref.read(transactionsFilterProvider.notifier).setFilter(filter.copyWith(
                                      dateFilter: val,
                                      customDateRange: () => null,
                                    ));
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                initialValue: filter.transactionType,
                                decoration: const InputDecoration(
                                  labelText: 'Type',
                                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                ),
                                style: const TextStyle(fontSize: 12),
                                items: const [
                                  DropdownMenuItem(value: 'All', child: Text('All Types')),
                                  DropdownMenuItem(value: 'Income', child: Text('Income')),
                                  DropdownMenuItem(value: 'Expense', child: Text('Expense')),
                                ],
                                onChanged: (val) {
                                  ref.read(transactionsFilterProvider.notifier).setFilter(filter.copyWith(
                                    transactionType: val,
                                  ));
                                },
                              ),
                            ),
                          ],
                        ),

                        // Custom Date range label display if active
                        if (filter.dateFilter == DateFilterType.custom && filter.customDateRange != null) ...[
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Selected: ${DateFormat('yyyy-MM-dd').format(filter.customDateRange!.start)} to ${DateFormat('yyyy-MM-dd').format(filter.customDateRange!.end)}',
                                style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic),
                              ),
                              TextButton(
                                onPressed: () => _selectCustomDateRange(context, filter),
                                style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(40, 24)),
                                child: const Text('Change', style: TextStyle(fontSize: 11)),
                              ),
                            ],
                          ),
                        ],

                        // Clear filters action row
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton.icon(
                              onPressed: _clearFilters,
                              icon: const Icon(Icons.clear_all, size: 16),
                              label: const Text('Reset All', style: TextStyle(fontSize: 12)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  crossFadeState: _showFilters ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                  duration: const Duration(milliseconds: 250),
                ),
              ],
            ),
          ),

          // 2. Sliding Segment Control (History vs. Analysis)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Container(
              height: 46,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _activeTab = 'history'),
                      child: Container(
                        decoration: BoxDecoration(
                          color: _activeTab == 'history' ? Theme.of(context).colorScheme.surface : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: _activeTab == 'history'
                              ? [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.05),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  )
                                ]
                              : null,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          'History',
                          style: GoogleFonts.outfit(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: _activeTab == 'history'
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).textTheme.bodyMedium?.color?.withValues(alpha: 0.7),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _activeTab = 'analysis'),
                      child: Container(
                        decoration: BoxDecoration(
                          color: _activeTab == 'analysis' ? Theme.of(context).colorScheme.surface : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: _activeTab == 'analysis'
                              ? [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.05),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  )
                                ]
                              : null,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          'Analysis',
                          style: GoogleFonts.outfit(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: _activeTab == 'analysis'
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).textTheme.bodyMedium?.color?.withValues(alpha: 0.7),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),

          // 3. Tab contents
          Expanded(
            child: _activeTab == 'history'
                ? _buildHistoryTab(context, filteredTxs, formatter, accounts, categories)
                : _buildAnalysisTab(context, analysisData, formatter),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryTab(
    BuildContext context,
    List<TransactionWithEntries> txs,
    NumberFormat formatter,
    List<Account> accounts,
    List<Category> categories,
  ) {
    if (txs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.search_off_outlined, size: 64, color: Theme.of(context).colorScheme.outline),
              const SizedBox(height: 16),
              Text(
                'No Transactions Found',
                style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              const Text(
                'Try broadening your filter criteria or recording new transactions.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    final baseCurrency = ref.read(baseCurrencyProvider).value ?? 'EUR';
    final categoriesList = ref.read(categoriesStreamProvider).value ?? [];
    final macrosList = ref.read(macroCategoriesStreamProvider).value ?? [];

    return Column(
      children: [
        // Export Action Row
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Showing ${txs.length} transactions',
                style: const TextStyle(fontSize: 12, color: Colors.grey, fontStyle: FontStyle.italic),
              ),
              TextButton.icon(
                onPressed: () async {
                  await CsvExportService.exportAndShare(
                    txs,
                    accounts,
                    categoriesList,
                    macrosList,
                    baseCurrency,
                  );
                },
                icon: const Icon(Icons.share, size: 16),
                label: const Text('Export CSV', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ),

        // Transaction List
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 24),
            itemCount: txs.length,
            itemBuilder: (context, index) {
              final txWithEntries = txs[index];
              final tx = txWithEntries.transaction;
              final entries = txWithEntries.entries;

              // Find account name and category name for short summary
              final accEntry = entries.firstWhere((e) => e.accountId != null, orElse: () => entries.first);
              final catEntry = entries.firstWhere((e) => e.categoryId != null, orElse: () => entries.first);

              final account = accounts.firstWhere((a) => a.id == accEntry.accountId, orElse: () => accounts.first);
              final category = categories.firstWhere((c) => c.id == catEntry.categoryId, orElse: () => categories.first);

              // Calculate total amount in base currency of this transaction (Sum of positive entries)
              double txSum = 0.0;
              for (final entry in entries) {
                if (entry.amountInBase > 0) {
                  txSum += entry.amountInBase / 100.0;
                }
              }

              // Determine type for indicator
              final bool isIncome = entries.any((e) => e.accountId != null && e.amount > 0);

              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                child: ListTile(
                  onTap: () => _showDoubleEntryDialog(context, txWithEntries, formatter, accounts, categories),
                  leading: CircleAvatar(
                    backgroundColor: isIncome ? Colors.green.withValues(alpha: 0.12) : Colors.orange.withValues(alpha: 0.12),
                    foregroundColor: isIncome ? Colors.green : Colors.orange,
                    child: Icon(isIncome ? Icons.trending_up : Icons.trending_down, size: 20),
                  ),
                  title: Text(
                    tx.description,
                    style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  subtitle: Text(
                    '${DateFormat('yyyy-MM-dd').format(tx.date)} • ${account.name} → ${category.name}',
                    style: const TextStyle(fontSize: 11),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${isIncome ? '+' : '-'}${formatter.format(txSum)}',
                        style: GoogleFonts.outfit(
                          fontWeight: FontWeight.bold,
                          color: isIncome ? Colors.green : Colors.red,
                        ),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18, color: Colors.grey),
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Delete Transaction'),
                              content: const Text('Are you sure you want to delete this transaction from the ledger?'),
                              actions: [
                                TextButton(
                                  child: const Text('Cancel'),
                                  onPressed: () => Navigator.of(context).pop(),
                                ),
                                TextButton(
                                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                                  child: const Text('Delete'),
                                  onPressed: () async {
                                    Navigator.of(context).pop();
                                    await ref.read(databaseProvider).deleteTransaction(tx.id);
                                  },
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAnalysisTab(BuildContext context, AnalysisData data, NumberFormat formatter) {
    final bool hasData = data.totalIncome > 0 || data.totalExpense > 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. KPI Savings Card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Theme.of(context).colorScheme.primaryContainer,
                  Theme.of(context).colorScheme.surfaceContainerHighest,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.1)),
            ),
            child: Column(
              children: [
                Text(
                  'NET SAVINGS',
                  style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey),
                ),
                const SizedBox(height: 6),
                Text(
                  formatter.format(data.netSavings),
                  style: GoogleFonts.outfit(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: data.netSavings >= 0 ? Colors.green : Colors.red,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          const Icon(Icons.arrow_downward, color: Colors.green, size: 20),
                          const SizedBox(height: 4),
                          Text('Income', style: TextStyle(fontSize: 11, color: Colors.grey)),
                          Text(
                            formatter.format(data.totalIncome),
                            style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.green),
                          ),
                        ],
                      ),
                    ),
                    Container(height: 30, width: 1, color: Colors.grey.withValues(alpha: 0.3)),
                    Expanded(
                      child: Column(
                        children: [
                          const Icon(Icons.arrow_upward, color: Colors.orange, size: 20),
                          const SizedBox(height: 4),
                          Text('Expenses', style: TextStyle(fontSize: 11, color: Colors.grey)),
                          Text(
                            formatter.format(data.totalExpense),
                            style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.orange),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          if (!hasData)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  children: [
                    const Icon(Icons.pie_chart_outline, size: 48, color: Colors.grey),
                    const SizedBox(height: 12),
                    Text(
                      'No Data for Analysis',
                      style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Make sure you have transactions recorded and within the active filter scope.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            // 2. Type Selector Toggle for Breakdown (Expense vs. Income)
            Center(
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'Expense',
                    icon: Icon(Icons.trending_down_outlined),
                    label: Text('Expenses'),
                  ),
                  ButtonSegment(
                    value: 'Income',
                    icon: Icon(Icons.trending_up_outlined),
                    label: Text('Income'),
                  ),
                ],
                selected: {_analysisType},
                onSelectionChanged: (val) {
                  setState(() {
                    _analysisType = val.first;
                    _touchedIndex = null;
                  });
                },
              ),
            ),
            const SizedBox(height: 20),

            // 3. Pie Chart section
            _buildPieChart(context, data, formatter),
            const SizedBox(height: 24),

            // 4. Progress list breakdown
            Text(
              '$_analysisType Category Share',
              style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _buildCategoryBreakdownList(context, data, formatter),
          ],
        ],
      ),
    );
  }

  Widget _buildPieChart(BuildContext context, AnalysisData data, NumberFormat formatter) {
    final breakdown = _analysisType == 'Expense' ? data.expenseBreakdown : data.incomeBreakdown;

    if (breakdown.isEmpty) {
      return SizedBox(
        height: 160,
        child: Center(
          child: Text(
            'No ${_analysisType.toLowerCase()} categories recorded yet.',
            style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic),
          ),
        ),
      );
    }

    return SizedBox(
      height: 200,
      child: Stack(
        alignment: Alignment.center,
        children: [
          PieChart(
            PieChartData(
              pieTouchData: PieTouchData(
                touchCallback: (FlTouchEvent event, pieTouchResponse) {
                  setState(() {
                    if (!event.isInterestedForInteractions ||
                        pieTouchResponse == null ||
                        pieTouchResponse.touchedSection == null) {
                      _touchedIndex = null;
                      return;
                    }
                    _touchedIndex = pieTouchResponse.touchedSection!.touchedSectionIndex;
                  });
                },
              ),
              borderData: FlBorderData(show: false),
              sectionsSpace: 3,
              centerSpaceRadius: 50,
              sections: List.generate(breakdown.length, (i) {
                final item = breakdown[i];
                final isTouched = i == _touchedIndex;
                final radius = isTouched ? 30.0 : 24.0;
                final color = _chartColors[i % _chartColors.length];

                return PieChartSectionData(
                  color: color,
                  value: item.amount,
                  title: isTouched ? '${(item.percentage * 100).toStringAsFixed(1)}%' : '',
                  radius: radius,
                  titleStyle: GoogleFonts.outfit(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                );
              }),
            ),
          ),
          // Total in middle
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'TOTAL',
                style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey),
              ),
              Text(
                formatter.format(_analysisType == 'Expense' ? data.totalExpense : data.totalIncome),
                style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryBreakdownList(
    BuildContext context,
    AnalysisData data,
    NumberFormat formatter,
  ) {
    final breakdown = _analysisType == 'Expense' ? data.expenseBreakdown : data.incomeBreakdown;

    return Column(
      children: List.generate(breakdown.length, (i) {
        final item = breakdown[i];
        final color = _chartColors[i % _chartColors.length];

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        item.category.name,
                        style: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                    ],
                  ),
                  Text(
                    '${formatter.format(item.amount)} (${(item.percentage * 100).toStringAsFixed(1)}%)',
                    style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: item.percentage,
                  backgroundColor: Theme.of(context).colorScheme.outline.withValues(alpha: 0.1),
                  color: color,
                  minHeight: 6,
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}
