import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:nwt_app/core/database/database.dart';
import 'package:nwt_app/shared/providers.dart';
import 'package:nwt_app/features/transactions/transactions_filter.dart';

void main() {
  final mockMacros = [
    MacroCategory(id: 1, name: 'Revenues', type: 'Revenue'),
    MacroCategory(id: 2, name: 'Expenses', type: 'Expense'),
  ];

  final mockCategories = [
    Category(id: 11, macroCategoryId: 1, name: 'Salary', isDefault: true),
    Category(id: 12, macroCategoryId: 2, name: 'Groceries', isDefault: true),
  ];

  final mockAccounts = [
    Account(id: 21, name: 'Bank Account', currency: 'EUR', type: 'bank', isActive: true),
    Account(id: 22, name: 'Cash Wallet', currency: 'EUR', type: 'cash', isActive: true),
  ];

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day, 12, 0);
  final yesterday = today.subtract(const Duration(days: 1));
  final fortyFiveDaysAgo = today.subtract(const Duration(days: 45));

  final mockTxs = [
    TransactionWithEntries(
      transaction: Transaction(id: 101, date: today, description: 'Salary Job A'),
      entries: [
        Entry(id: 1, transactionId: 101, accountId: 21, categoryId: null, amount: 100000, amountInBase: 100000, exchangeRate: 1.0),
        Entry(id: 2, transactionId: 101, accountId: null, categoryId: 11, amount: -100000, amountInBase: -100000, exchangeRate: 1.0),
      ],
    ),
    TransactionWithEntries(
      transaction: Transaction(id: 102, date: yesterday, description: 'Weekly groceries supermarket'),
      entries: [
        Entry(id: 3, transactionId: 102, accountId: 22, categoryId: null, amount: -5000, amountInBase: -5000, exchangeRate: 1.0),
        Entry(id: 4, transactionId: 102, accountId: null, categoryId: 12, amount: 5000, amountInBase: 5000, exchangeRate: 1.0),
      ],
    ),
    TransactionWithEntries(
      transaction: Transaction(id: 103, date: fortyFiveDaysAgo, description: 'Online groceries shipping'),
      entries: [
        Entry(id: 5, transactionId: 103, accountId: 21, categoryId: null, amount: -12000, amountInBase: -12000, exchangeRate: 1.0),
        Entry(id: 6, transactionId: 103, accountId: null, categoryId: 12, amount: 12000, amountInBase: 12000, exchangeRate: 1.0),
      ],
    ),
  ];

  late ProviderContainer container;

  setUp(() async {
    container = ProviderContainer(
      overrides: [
        transactionsStreamProvider.overrideWith((ref) => Stream.value(mockTxs)),
        accountsStreamProvider.overrideWith((ref) => Stream.value(mockAccounts)),
        allAccountsStreamProvider.overrideWith((ref) => Stream.value(mockAccounts)),
        categoriesStreamProvider.overrideWith((ref) => Stream.value(mockCategories)),
        macroCategoriesStreamProvider.overrideWith((ref) => Stream.value(mockMacros)),
        baseCurrencyProvider.overrideWith((ref) => Future.value('EUR')),
      ],
    );

    // Keep all providers alive during tests
    container.listen(transactionsStreamProvider, (_, _) {});
    container.listen(accountsStreamProvider, (_, _) {});
    container.listen(allAccountsStreamProvider, (_, _) {});
    container.listen(categoriesStreamProvider, (_, _) {});
    container.listen(macroCategoriesStreamProvider, (_, _) {});
    container.listen(baseCurrencyProvider, (_, _) {});
    container.listen(filteredTransactionsProvider, (_, _) {});
    container.listen(analysisDataProvider, (_, _) {});

    // Flush the stream events so everything is loaded
    await Future.delayed(Duration.zero);
  });

  tearDown(() {
    container.dispose();
  });

  group('Transactions Filter & Search Tests', () {
    test('Default filter returns all transactions', () {
      final filtered = container.read(filteredTransactionsProvider);
      expect(filtered.length, 3);
    });

    test('Search filter matches description query', () {
      container.read(transactionsFilterProvider.notifier).setFilter(TransactionsFilter(
        searchQuery: 'groceries',
      ));

      final filtered = container.read(filteredTransactionsProvider);
      expect(filtered.length, 2);
      expect(filtered.every((tx) => tx.transaction.description.toLowerCase().contains('groceries')), true);
    });

    test('Account filter matches specific account ID', () {
      container.read(transactionsFilterProvider.notifier).setFilter(TransactionsFilter(
        accountId: 22,
      ));

      final filtered = container.read(filteredTransactionsProvider);
      expect(filtered.length, 1);
      expect(filtered.first.transaction.id, 102);
    });

    test('Category filter matches specific category ID', () {
      container.read(transactionsFilterProvider.notifier).setFilter(TransactionsFilter(
        categoryId: 11,
      ));

      final filtered = container.read(filteredTransactionsProvider);
      expect(filtered.length, 1);
      expect(filtered.first.transaction.id, 101);
    });

    test('Transaction Type filter separates Income vs Expense', () {
      container.read(transactionsFilterProvider.notifier).setFilter(TransactionsFilter(
        transactionType: 'Income',
      ));
      var filtered = container.read(filteredTransactionsProvider);
      expect(filtered.length, 1);
      expect(filtered.first.transaction.id, 101);

      container.read(transactionsFilterProvider.notifier).setFilter(TransactionsFilter(
        transactionType: 'Expense',
      ));
      filtered = container.read(filteredTransactionsProvider);
      expect(filtered.length, 2);
      expect(filtered.any((tx) => tx.transaction.id == 102), true);
      expect(filtered.any((tx) => tx.transaction.id == 103), true);
    });

    test('Date filter thisMonth excludes older transactions', () {
      container.read(transactionsFilterProvider.notifier).setFilter(TransactionsFilter(
        dateFilter: DateFilterType.thisMonth,
      ));

      final filtered = container.read(filteredTransactionsProvider);
      expect(filtered.length, 2);
      expect(filtered.any((tx) => tx.transaction.id == 103), false);
    });

    test('Custom date range filter works correctly', () {
      container.read(transactionsFilterProvider.notifier).setFilter(TransactionsFilter(
        dateFilter: DateFilterType.custom,
        customDateRange: DateTimeRange(
          start: fortyFiveDaysAgo.subtract(const Duration(days: 1)),
          end: yesterday,
        ),
      ));

      final filtered = container.read(filteredTransactionsProvider);
      expect(filtered.length, 2);
      expect(filtered.any((tx) => tx.transaction.id == 101), false);
    });
  });

  group('Transactions Analysis Tests', () {
    test('Calculates aggregated totals correctly', () {
      final analysis = container.read(analysisDataProvider);
      
      expect(analysis.totalIncome, 1000.00);
      expect(analysis.totalExpense, 170.00);
      expect(analysis.netSavings, 830.00);
    });

    test('Calculates category breakdowns and percentages correctly', () {
      final analysis = container.read(analysisDataProvider);
      
      expect(analysis.expenseBreakdown.length, 1);
      final groceriesBreakdown = analysis.expenseBreakdown.first;
      expect(groceriesBreakdown.category.id, 12);
      expect(groceriesBreakdown.amount, 170.00);
      expect(groceriesBreakdown.percentage, 1.0);

      expect(analysis.incomeBreakdown.length, 1);
      final salaryBreakdown = analysis.incomeBreakdown.first;
      expect(salaryBreakdown.category.id, 11);
      expect(salaryBreakdown.amount, 1000.00);
      expect(salaryBreakdown.percentage, 1.0);
    });
  });
}
