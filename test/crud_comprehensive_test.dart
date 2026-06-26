import 'package:drift/native.dart';
import 'package:drift/drift.dart' as drift;
import 'package:flutter_test/flutter_test.dart';
import 'package:nwt_app/core/database/database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    // Open in-memory database for testing with foreign key constraints enabled
    db = AppDatabase.executor(NativeDatabase.memory(setup: (database) {
      database.execute('PRAGMA foreign_keys = ON;');
    }));
  });

  tearDown(() async {
    await db.close();
  });

  group('Accounts Comprehensive CRUD Tests', () {
    test('Create accounts with default and custom settings', () async {
      // 1. Create a default bank account
      final bankId = await db.addAccount(const AccountsCompanion(
        name: drift.Value('Main Bank Account'),
        currency: drift.Value('EUR'),
        type: drift.Value('bank'),
      ));
      expect(bankId, greaterThan(0));

      // 2. Create a cash wallet account
      final cashId = await db.addAccount(const AccountsCompanion(
        name: drift.Value('Pocket Cash'),
        currency: drift.Value('USD'),
        type: drift.Value('cash'),
        description: drift.Value('Daily spending money'),
        isActive: drift.Value(false),
      ));
      expect(cashId, greaterThan(0));

      // 3. Verify accounts exist and have correct fields
      final accounts = await db.select(db.accounts).get();
      expect(accounts.length, 2);

      final bank = accounts.firstWhere((a) => a.id == bankId);
      expect(bank.name, 'Main Bank Account');
      expect(bank.currency, 'EUR');
      expect(bank.type, 'bank');
      expect(bank.isActive, true); // Default value is true
      expect(bank.description, isNull);

      final cash = accounts.firstWhere((a) => a.id == cashId);
      expect(cash.name, 'Pocket Cash');
      expect(cash.currency, 'USD');
      expect(cash.type, 'cash');
      expect(cash.isActive, false);
      expect(cash.description, 'Daily spending money');
    });

    test('Update account details', () async {
      final accId = await db.addAccount(const AccountsCompanion(
        name: drift.Value('Original Name'),
        currency: drift.Value('EUR'),
        type: drift.Value('bank'),
      ));

      final accountsBefore = await db.select(db.accounts).get();
      final account = accountsBefore.firstWhere((a) => a.id == accId);

      // Perform update
      final updatedAccount = account.copyWith(
        name: 'Updated Name',
        currency: 'USD',
        type: 'cash',
        isActive: false,
        description: const drift.Value('New Description'),
      );

      final success = await db.updateAccount(updatedAccount);
      expect(success, true);

      // Verify update in DB
      final accountsAfter = await db.select(db.accounts).get();
      final updated = accountsAfter.firstWhere((a) => a.id == accId);
      expect(updated.name, 'Updated Name');
      expect(updated.currency, 'USD');
      expect(updated.type, 'cash');
      expect(updated.isActive, false);
      expect(updated.description, 'New Description');
    });

    test('Delete account', () async {
      final accId = await db.addAccount(const AccountsCompanion(
        name: drift.Value('Account to Delete'),
        currency: drift.Value('EUR'),
      ));

      // Verify it is inserted
      var accounts = await db.select(db.accounts).get();
      expect(accounts.any((a) => a.id == accId), true);

      // Delete it
      final deletedCount = await db.deleteAccount(accId);
      expect(deletedCount, 1);

      // Verify it is gone
      accounts = await db.select(db.accounts).get();
      expect(accounts.any((a) => a.id == accId), false);
    });

    test('canDeleteAccount validation', () async {
      // 1. Setup macro category and category
      final macroId = await db.into(db.macroCategories).insert(
        const MacroCategoriesCompanion(name: drift.Value('Revenues'), type: drift.Value('Revenue')),
      );
      final catId = await db.addCategory(CategoriesCompanion(
        macroCategoryId: drift.Value(macroId),
        name: const drift.Value('Income'),
      ));

      // 2. Setup account
      final accId = await db.addAccount(const AccountsCompanion(
        name: drift.Value('Salary Account'),
        currency: drift.Value('EUR'),
      ));

      // Can delete before transaction
      var canDelete = await db.canDeleteAccount(accId);
      expect(canDelete, true);

      // 3. Create a transaction using this account
      await db.createBalancedTransaction(
        transaction: TransactionsCompanion(
          date: drift.Value(DateTime.now()),
          description: const drift.Value('Balanced Paycheck'),
        ),
        entries: [
          EntriesCompanion(
            accountId: drift.Value(accId),
            categoryId: const drift.Value(null),
            amount: const drift.Value(200000),
            amountInBase: const drift.Value(200000),
          ),
          EntriesCompanion(
            accountId: const drift.Value(null),
            categoryId: drift.Value(catId),
            amount: const drift.Value(-200000),
            amountInBase: const drift.Value(-200000),
          ),
        ],
      );

      // Cannot delete after transaction
      canDelete = await db.canDeleteAccount(accId);
      expect(canDelete, false);
    });
  });

  group('Categories Comprehensive CRUD Tests', () {
    late int macroId;

    setUp(() async {
      macroId = await db.into(db.macroCategories).insert(
        const MacroCategoriesCompanion(name: drift.Value('Expenses'), type: drift.Value('Expense')),
      );
    });

    test('Create categories with default and custom settings', () async {
      // 1. Create default category
      final cat1 = await db.addCategory(CategoriesCompanion(
        macroCategoryId: drift.Value(macroId),
        name: const drift.Value('Groceries'),
      ));

      // 2. Create custom category
      final cat2 = await db.addCategory(CategoriesCompanion(
        macroCategoryId: drift.Value(macroId),
        name: const drift.Value('Subscriptions'),
        description: const drift.Value('Streaming services'),
        isDefault: const drift.Value(true),
      ));

      // 3. Verify in DB
      final categories = await db.select(db.categories).get();
      expect(categories.length, 2);

      final c1 = categories.firstWhere((c) => c.id == cat1);
      expect(c1.name, 'Groceries');
      expect(c1.macroCategoryId, macroId);
      expect(c1.isDefault, false); // Default value is false
      expect(c1.description, isNull);

      final c2 = categories.firstWhere((c) => c.id == cat2);
      expect(c2.name, 'Subscriptions');
      expect(c2.macroCategoryId, macroId);
      expect(c2.isDefault, true);
      expect(c2.description, 'Streaming services');
    });

    test('Update category details', () async {
      final catId = await db.addCategory(CategoriesCompanion(
        macroCategoryId: drift.Value(macroId),
        name: const drift.Value('Original Category'),
      ));

      final categoriesBefore = await db.select(db.categories).get();
      final category = categoriesBefore.firstWhere((c) => c.id == catId);

      // Update category
      final updatedCategory = category.copyWith(
        name: 'Updated Category Name',
        description: const drift.Value('Updated Description'),
        isDefault: true,
      );

      final success = await db.updateCategory(updatedCategory);
      expect(success, true);

      // Verify updates in DB
      final categoriesAfter = await db.select(db.categories).get();
      final updated = categoriesAfter.firstWhere((c) => c.id == catId);
      expect(updated.name, 'Updated Category Name');
      expect(updated.description, 'Updated Description');
      expect(updated.isDefault, true);
    });

    test('Delete category', () async {
      final catId = await db.addCategory(CategoriesCompanion(
        macroCategoryId: drift.Value(macroId),
        name: const drift.Value('Category to Delete'),
      ));

      var categories = await db.select(db.categories).get();
      expect(categories.any((c) => c.id == catId), true);

      // Delete
      final deletedCount = await db.deleteCategory(catId);
      expect(deletedCount, 1);

      // Verify gone
      categories = await db.select(db.categories).get();
      expect(categories.any((c) => c.id == catId), false);
    });

    test('canDeleteCategory validation', () async {
      final catId = await db.addCategory(CategoriesCompanion(
        macroCategoryId: drift.Value(macroId),
        name: const drift.Value('Dinner Out'),
      ));

      final accId = await db.addAccount(const AccountsCompanion(
        name: drift.Value('Bank Card'),
        currency: drift.Value('EUR'),
      ));

      // Can delete before transaction
      var canDelete = await db.canDeleteCategory(catId);
      expect(canDelete, true);

      // Create transaction using category
      await db.createBalancedTransaction(
        transaction: TransactionsCompanion(
          date: drift.Value(DateTime.now()),
          description: const drift.Value('Restaurante Meal'),
        ),
        entries: [
          EntriesCompanion(
            accountId: drift.Value(accId),
            categoryId: const drift.Value(null),
            amount: const drift.Value(-4500),
            amountInBase: const drift.Value(-4500),
          ),
          EntriesCompanion(
            accountId: const drift.Value(null),
            categoryId: drift.Value(catId),
            amount: const drift.Value(4500),
            amountInBase: const drift.Value(4500),
          ),
        ],
      );

      // Cannot delete after transaction
      canDelete = await db.canDeleteCategory(catId);
      expect(canDelete, false);
    });
  });

  group('Transactions Comprehensive CRUD Tests', () {
    late int accId;
    late int catId;

    setUp(() async {
      final macroId = await db.into(db.macroCategories).insert(
        const MacroCategoriesCompanion(name: drift.Value('Expenses'), type: drift.Value('Expense')),
      );
      catId = await db.addCategory(CategoriesCompanion(
        macroCategoryId: drift.Value(macroId),
        name: const drift.Value('Miscellaneous'),
      ));
      accId = await db.addAccount(const AccountsCompanion(
        name: drift.Value('Primary Account'),
        currency: drift.Value('EUR'),
      ));
    });

    test('Insert transaction with various custom dates', () async {
      final pastDate = DateTime(2020, 1, 15, 12, 0);
      final futureDate = DateTime(2030, 8, 22, 18, 30);

      // 1. Save past transaction
      final txId1 = await db.createBalancedTransaction(
        transaction: TransactionsCompanion(
          date: drift.Value(pastDate),
          description: const drift.Value('Past transaction'),
        ),
        entries: [
          EntriesCompanion(accountId: drift.Value(accId), amount: const drift.Value(-1000), amountInBase: const drift.Value(-1000)),
          EntriesCompanion(categoryId: drift.Value(catId), amount: const drift.Value(1000), amountInBase: const drift.Value(1000)),
        ],
      );

      // 2. Save future transaction
      final txId2 = await db.createBalancedTransaction(
        transaction: TransactionsCompanion(
          date: drift.Value(futureDate),
          description: const drift.Value('Future transaction'),
        ),
        entries: [
          EntriesCompanion(accountId: drift.Value(accId), amount: const drift.Value(-500), amountInBase: const drift.Value(-500)),
          EntriesCompanion(categoryId: drift.Value(catId), amount: const drift.Value(500), amountInBase: const drift.Value(500)),
        ],
      );

      // Verify retrieved dates match exactly
      final savedTxs = await db.select(db.transactions).get();
      expect(savedTxs.length, 2);

      final tx1 = savedTxs.firstWhere((t) => t.id == txId1);
      expect(tx1.date, pastDate);
      expect(tx1.description, 'Past transaction');

      final tx2 = savedTxs.firstWhere((t) => t.id == txId2);
      expect(tx2.date, futureDate);
      expect(tx2.description, 'Future transaction');
    });

    test('Delete transaction removes transaction and cascade-deletes entries', () async {
      final txId = await db.createBalancedTransaction(
        transaction: TransactionsCompanion(
          date: drift.Value(DateTime.now()),
          description: const drift.Value('Transaction to delete'),
        ),
        entries: [
          EntriesCompanion(accountId: drift.Value(accId), amount: const drift.Value(-2000), amountInBase: const drift.Value(-2000)),
          EntriesCompanion(categoryId: drift.Value(catId), amount: const drift.Value(2000), amountInBase: const drift.Value(2000)),
        ],
      );

      // Verify transaction and entries exist
      final txsBefore = await db.select(db.transactions).get();
      expect(txsBefore.any((t) => t.id == txId), true);
      final entriesBefore = await db.select(db.entries).get();
      expect(entriesBefore.where((e) => e.transactionId == txId).length, 2);

      // Delete transaction
      await db.deleteTransaction(txId);

      // Verify transaction and entries are cascade deleted
      final txsAfter = await db.select(db.transactions).get();
      expect(txsAfter.any((t) => t.id == txId), false);
      final entriesAfter = await db.select(db.entries).get();
      expect(entriesAfter.where((e) => e.transactionId == txId).isEmpty, true);
    });

    test('Update transaction description and date via Drift API', () async {
      final originalDate = DateTime(2026, 1, 1);
      final txId = await db.createBalancedTransaction(
        transaction: TransactionsCompanion(
          date: drift.Value(originalDate),
          description: const drift.Value('Original Description'),
        ),
        entries: [
          EntriesCompanion(accountId: drift.Value(accId), amount: const drift.Value(-300), amountInBase: const drift.Value(-300)),
          EntriesCompanion(categoryId: drift.Value(catId), amount: const drift.Value(300), amountInBase: const drift.Value(300)),
        ],
      );

      // Perform update using drift update builder
      final updatedDate = DateTime(2026, 6, 15);
      final rowsUpdated = await (db.update(db.transactions)
            ..where((t) => t.id.equals(txId)))
          .write(TransactionsCompanion(
            description: const drift.Value('Updated Description'),
            date: drift.Value(updatedDate),
          ));
      expect(rowsUpdated, 1);

      // Verify updates in DB
      final savedTxs = await db.select(db.transactions).get();
      final tx = savedTxs.firstWhere((t) => t.id == txId);
      expect(tx.description, 'Updated Description');
      expect(tx.date, updatedDate);
    });
  });
}
