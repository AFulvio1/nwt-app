import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart';
import '../core/database/database.dart';

// Stream of all active accounts
final accountsStreamProvider = StreamProvider<List<Account>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.accounts)..where((t) => t.isActive.equals(true))).watch();
});

// Stream of all categories
final categoriesStreamProvider = StreamProvider<List<Category>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.select(db.categories).watch();
});

// Stream of all macro categories
final macroCategoriesStreamProvider = StreamProvider<List<MacroCategory>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.select(db.macroCategories).watch();
});

// Class representing a full transaction with all its ledger entries
class TransactionWithEntries {
  final Transaction transaction;
  final List<Entry> entries;

  TransactionWithEntries({required this.transaction, required this.entries});
}

// Stream of all transactions, ordered by date descending, with their entries joined
final transactionsStreamProvider = StreamProvider<List<TransactionWithEntries>>((ref) {
  final db = ref.watch(databaseProvider);

  // We watch all transactions and entries, then group them in Dart
  final txsStream = (db.select(db.transactions)
        ..orderBy([(t) => OrderingTerm(expression: t.date, mode: OrderingMode.desc)]))
      .watch();
  db.select(db.entries).watch();

  return txsStream.asyncMap((txs) async {
    final entries = await db.select(db.entries).get();
    return txs.map((tx) {
      final txEntries = entries.where((e) => e.transactionId == tx.id).toList();
      return TransactionWithEntries(transaction: tx, entries: txEntries);
    }).toList();
  });
});

// Stream of all tracked assets
final assetsStreamProvider = StreamProvider<List<Asset>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.select(db.assets).watch();
});

// FutureProvider to fetch the base currency from settings
final baseCurrencyProvider = FutureProvider<String>((ref) async {
  final db = ref.watch(databaseProvider);
  final setting = await (db.select(db.appSettings)..where((t) => t.key.equals('base_currency'))).getSingleOrNull();
  return setting?.value ?? 'EUR';
});

// Class representing dashboard data KPIs and charts
class DashboardData {
  final double netWorth;
  final double totalAssets;
  final double totalLiabilities;
  final List<Map<String, dynamic>> historyPoints; // list of {date: DateTime, netWorth: double}
  final String baseCurrency;

  DashboardData({
    required this.netWorth,
    required this.totalAssets,
    required this.totalLiabilities,
    required this.historyPoints,
    required this.baseCurrency,
  });
}

// Provider combining database streams to compute financial metrics
final dashboardDataProvider = Provider<AsyncValue<DashboardData>>((ref) {
  final accountsAsync = ref.watch(accountsStreamProvider);
  final categoriesAsync = ref.watch(categoriesStreamProvider);
  final macrosAsync = ref.watch(macroCategoriesStreamProvider);
  final txsAsync = ref.watch(transactionsStreamProvider);
  final baseCurrencyAsync = ref.watch(baseCurrencyProvider);

  if (accountsAsync.isLoading ||
      categoriesAsync.isLoading ||
      macrosAsync.isLoading ||
      txsAsync.isLoading ||
      baseCurrencyAsync.isLoading) {
    return const AsyncValue.loading();
  }

  if (accountsAsync.hasError) return AsyncValue.error(accountsAsync.error!, accountsAsync.stackTrace!);
  if (categoriesAsync.hasError) return AsyncValue.error(categoriesAsync.error!, categoriesAsync.stackTrace!);
  if (macrosAsync.hasError) return AsyncValue.error(macrosAsync.error!, macrosAsync.stackTrace!);
  if (txsAsync.hasError) return AsyncValue.error(txsAsync.error!, txsAsync.stackTrace!);
  if (baseCurrencyAsync.hasError) return AsyncValue.error(baseCurrencyAsync.error!, baseCurrencyAsync.stackTrace!);

  final accounts = accountsAsync.value!;
  final categories = categoriesAsync.value!;
  final macros = macrosAsync.value!;
  final txsWithEntries = txsAsync.value!;
  final baseCurrency = baseCurrencyAsync.value!;

  // Map accounts to their macro category types
  final accountToMacroType = <int, String>{};
  for (final account in accounts) {
    final cat = categories.firstWhere((c) => c.id == account.categoryId, orElse: () => categories.first);
    final macro = macros.firstWhere((m) => m.id == cat.macroCategoryId, orElse: () => macros.first);
    accountToMacroType[account.id] = macro.type; // Asset, Liability, Revenue, Expense, Equity
  }

  // Calculate current balances in base currency
  double assetsSum = 0.0;
  double liabilitiesSum = 0.0;

  for (final txWithEntries in txsWithEntries) {
    for (final entry in txWithEntries.entries) {
      final type = accountToMacroType[entry.accountId];
      final val = entry.amountInBase / 100.0;
      if (type == 'Asset') {
        assetsSum += val;
      } else if (type == 'Liability') {
        liabilitiesSum += val; // will be negative, representing debt
      }
    }
  }

  // Calculate history of net worth at each transaction date
  final historyPoints = <Map<String, dynamic>>[];
  double runningNetWorth = 0.0;
  
  // Sort transactions chronologically
  final sortedTxs = List<TransactionWithEntries>.from(txsWithEntries)
    ..sort((a, b) => a.transaction.date.compareTo(b.transaction.date));
  
  for (final txWithEntries in sortedTxs) {
    double txNetWorthImpact = 0.0;
    for (final entry in txWithEntries.entries) {
      final type = accountToMacroType[entry.accountId];
      final val = entry.amountInBase / 100.0;
      if (type == 'Asset' || type == 'Liability') {
        txNetWorthImpact += val;
      }
    }
    runningNetWorth += txNetWorthImpact;
    historyPoints.add({
      'date': txWithEntries.transaction.date,
      'netWorth': runningNetWorth,
    });
  }

  return AsyncValue.data(DashboardData(
    netWorth: assetsSum + liabilitiesSum, // Assets are positive, Liabilities are negative
    totalAssets: assetsSum,
    totalLiabilities: liabilitiesSum.abs(), // Show positive for UI KPI card
    historyPoints: historyPoints,
    baseCurrency: baseCurrency,
  ));
});
