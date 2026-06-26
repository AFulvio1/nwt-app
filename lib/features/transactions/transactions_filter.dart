import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/database/database.dart';
import '../../shared/providers.dart';

enum DateFilterType {
  all,
  thisWeek,
  thisMonth,
  last30Days,
  thisYear,
  custom,
}

class TransactionsFilter {
  final String searchQuery;
  final int? accountId;
  final int? categoryId;
  final DateFilterType dateFilter;
  final DateTimeRange? customDateRange;
  final String transactionType; // 'All', 'Income', 'Expense'

  TransactionsFilter({
    this.searchQuery = '',
    this.accountId,
    this.categoryId,
    this.dateFilter = DateFilterType.all,
    this.customDateRange,
    this.transactionType = 'All',
  });

  TransactionsFilter copyWith({
    String? searchQuery,
    int? Function()? accountId,
    int? Function()? categoryId,
    DateFilterType? dateFilter,
    DateTimeRange? Function()? customDateRange,
    String? transactionType,
  }) {
    return TransactionsFilter(
      searchQuery: searchQuery ?? this.searchQuery,
      accountId: accountId != null ? accountId() : this.accountId,
      categoryId: categoryId != null ? categoryId() : this.categoryId,
      dateFilter: dateFilter ?? this.dateFilter,
      customDateRange: customDateRange != null ? customDateRange() : this.customDateRange,
      transactionType: transactionType ?? this.transactionType,
    );
  }
}

class TransactionsFilterNotifier extends Notifier<TransactionsFilter> {
  @override
  TransactionsFilter build() {
    return TransactionsFilter();
  }

  void setFilter(TransactionsFilter filter) {
    state = filter;
  }
}

// NotifierProvider for the active filters
final transactionsFilterProvider = NotifierProvider<TransactionsFilterNotifier, TransactionsFilter>(() {
  return TransactionsFilterNotifier();
});

// Provider that applies the active filters to the transactions list
final filteredTransactionsProvider = Provider<List<TransactionWithEntries>>((ref) {
  final txsAsync = ref.watch(transactionsStreamProvider);
  final filter = ref.watch(transactionsFilterProvider);
  final categoriesAsync = ref.watch(categoriesStreamProvider);
  final macrosAsync = ref.watch(macroCategoriesStreamProvider);

  if (txsAsync.isLoading || categoriesAsync.isLoading || macrosAsync.isLoading) {
    return [];
  }

  final txs = txsAsync.value ?? [];
  final categories = categoriesAsync.value ?? [];
  final macros = macrosAsync.value ?? [];

  final categoryMap = {for (var c in categories) c.id: c};
  final macroMap = {for (var m in macros) m.id: m};

  return txs.where((txWithEntries) {
    final tx = txWithEntries.transaction;
    final entries = txWithEntries.entries;

    // 1. Filter by Search Query (Description)
    if (filter.searchQuery.isNotEmpty) {
      if (!tx.description.toLowerCase().contains(filter.searchQuery.toLowerCase())) {
        return false;
      }
    }

    // 2. Filter by Account
    if (filter.accountId != null) {
      final hasAccount = entries.any((e) => e.accountId == filter.accountId);
      if (!hasAccount) return false;
    }

    // 3. Filter by Category
    if (filter.categoryId != null) {
      final hasCategory = entries.any((e) => e.categoryId == filter.categoryId);
      if (!hasCategory) return false;
    }

    // 4. Filter by Date
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final txDate = tx.date;

    switch (filter.dateFilter) {
      case DateFilterType.all:
        break;
      case DateFilterType.thisWeek:
        final startOfWeek = today.subtract(Duration(days: today.weekday - 1));
        final endOfWeek = startOfWeek.add(const Duration(days: 7));
        if (txDate.isBefore(startOfWeek) || !txDate.isBefore(endOfWeek)) {
          return false;
        }
        break;
      case DateFilterType.thisMonth:
        if (txDate.year != today.year || txDate.month != today.month) {
          return false;
        }
        break;
      case DateFilterType.last30Days:
        final thirtyDaysAgo = today.subtract(const Duration(days: 30));
        if (txDate.isBefore(thirtyDaysAgo)) {
          return false;
        }
        break;
      case DateFilterType.thisYear:
        if (txDate.year != today.year) {
          return false;
        }
        break;
      case DateFilterType.custom:
        if (filter.customDateRange != null) {
          final start = DateTime(
            filter.customDateRange!.start.year,
            filter.customDateRange!.start.month,
            filter.customDateRange!.start.day,
          );
          final end = DateTime(
            filter.customDateRange!.end.year,
            filter.customDateRange!.end.month,
            filter.customDateRange!.end.day,
            23,
            59,
            59,
          );
          if (txDate.isBefore(start) || txDate.isAfter(end)) {
            return false;
          }
        }
        break;
    }

    // 5. Filter by Transaction Type (All, Income, Expense)
    if (filter.transactionType != 'All') {
      final catEntry = entries.firstWhere(
        (e) => e.categoryId != null,
        orElse: () => const Entry(id: -1, transactionId: -1, amount: 0, amountInBase: 0, exchangeRate: 1.0),
      );
      if (catEntry.id == -1) {
        return false;
      }
      final cat = categoryMap[catEntry.categoryId];
      if (cat == null) return false;
      final macro = macroMap[cat.macroCategoryId];
      if (macro == null) return false;

      final isIncome = macro.type == 'Revenue';
      final filterIsIncome = filter.transactionType == 'Income';
      if (isIncome != filterIsIncome) {
        return false;
      }
    }

    return true;
  }).toList();
});

class CategoryBreakdown {
  final Category category;
  final MacroCategory macroCategory;
  final double amount;
  final double percentage;

  CategoryBreakdown({
    required this.category,
    required this.macroCategory,
    required this.amount,
    required this.percentage,
  });
}

class AnalysisData {
  final double totalIncome;
  final double totalExpense;
  final double netSavings;
  final List<CategoryBreakdown> incomeBreakdown;
  final List<CategoryBreakdown> expenseBreakdown;

  AnalysisData({
    required this.totalIncome,
    required this.totalExpense,
    required this.netSavings,
    required this.incomeBreakdown,
    required this.expenseBreakdown,
  });
}

// Provider that calculates income, expense and savings breakdowns from the filtered transaction list
final analysisDataProvider = Provider<AnalysisData>((ref) {
  final filteredTxs = ref.watch(filteredTransactionsProvider);
  final categoriesAsync = ref.watch(categoriesStreamProvider);
  final macrosAsync = ref.watch(macroCategoriesStreamProvider);

  final categories = categoriesAsync.value ?? [];
  final macros = macrosAsync.value ?? [];

  final categoryMap = {for (var c in categories) c.id: c};
  final macroMap = {for (var m in macros) m.id: m};

  double totalIncome = 0.0;
  double totalExpense = 0.0;

  final incomeMap = <int, double>{};
  final expenseMap = <int, double>{};

  for (final txWithEntries in filteredTxs) {
    for (final entry in txWithEntries.entries) {
      if (entry.categoryId != null) {
        final cat = categoryMap[entry.categoryId!];
        if (cat != null) {
          final macro = macroMap[cat.macroCategoryId];
          if (macro != null) {
            final double amount = (entry.amountInBase / 100.0).abs();
            if (macro.type == 'Revenue') {
              totalIncome += amount;
              incomeMap[cat.id] = (incomeMap[cat.id] ?? 0.0) + amount;
            } else if (macro.type == 'Expense') {
              totalExpense += amount;
              expenseMap[cat.id] = (expenseMap[cat.id] ?? 0.0) + amount;
            }
          }
        }
      }
    }
  }

  final incomeBreakdown = incomeMap.entries.map((e) {
    final cat = categoryMap[e.key]!;
    final macro = macroMap[cat.macroCategoryId]!;
    return CategoryBreakdown(
      category: cat,
      macroCategory: macro,
      amount: e.value,
      percentage: totalIncome > 0 ? (e.value / totalIncome) : 0.0,
    );
  }).toList()..sort((a, b) => b.amount.compareTo(a.amount));

  final expenseBreakdown = expenseMap.entries.map((e) {
    final cat = categoryMap[e.key]!;
    final macro = macroMap[cat.macroCategoryId]!;
    return CategoryBreakdown(
      category: cat,
      macroCategory: macro,
      amount: e.value,
      percentage: totalExpense > 0 ? (e.value / totalExpense) : 0.0,
    );
  }).toList()..sort((a, b) => b.amount.compareTo(a.amount));

  return AnalysisData(
    totalIncome: totalIncome,
    totalExpense: totalExpense,
    netSavings: totalIncome - totalExpense,
    incomeBreakdown: incomeBreakdown,
    expenseBreakdown: expenseBreakdown,
  );
});
