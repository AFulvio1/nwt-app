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

  group('Double-Entry Ledger Validation Tests', () {
    late int bankAccountId;
    late int incomeCategoryId;

    setUp(() async {
      // Seed initial mock schema dependencies
      // 1. Macro categories
      final revenueMacroId = await db.into(db.macroCategories).insert(
            const MacroCategoriesCompanion(name: drift.Value('Revenues'), type: drift.Value('Revenue')),
          );

      // 2. Categories
      incomeCategoryId = await db.into(db.categories).insert(
            CategoriesCompanion(macroCategoryId: drift.Value(revenueMacroId), name: const drift.Value('Income')),
          );

      // 3. Accounts (No categoryId needed in new schema)
      bankAccountId = await db.into(db.accounts).insert(
            const AccountsCompanion(
              name: drift.Value('Bank Account'),
              currency: drift.Value('EUR'),
              type: drift.Value('bank'),
            ),
          );
    });

    test('Saving a balanced transaction should succeed', () async {
      final txCompanion = TransactionsCompanion(
        date: drift.Value(DateTime.now()),
        description: const drift.Value('Balanced Transfer'),
      );

      final entriesComcompanions = [
        // Debit Bank Account (+100 EUR)
        EntriesCompanion(
          accountId: drift.Value(bankAccountId),
          categoryId: const drift.Value(null),
          amount: const drift.Value(10000),
          amountInBase: const drift.Value(10000),
          exchangeRate: const drift.Value(1.0),
        ),
        // Credit Income Category (-100 EUR)
        EntriesCompanion(
          accountId: const drift.Value(null),
          categoryId: drift.Value(incomeCategoryId),
          amount: const drift.Value(-10000),
          amountInBase: const drift.Value(-10000),
          exchangeRate: const drift.Value(1.0),
        ),
      ];

      final txId = await db.createBalancedTransaction(
        transaction: txCompanion,
        entries: entriesComcompanions,
      );

      expect(txId, greaterThan(0));

      final savedTxs = await db.select(db.transactions).get();
      expect(savedTxs.length, 1);

      final savedEntries = await db.select(db.entries).get();
      expect(savedEntries.length, 2);
    });

    test('Saving an unbalanced transaction should throw exception and roll back', () async {
      final txCompanion = TransactionsCompanion(
        date: drift.Value(DateTime.now()),
        description: const drift.Value('Unbalanced Transfer'),
      );

      final entriesComcompanions = [
        // Debit Bank (+100 EUR)
        EntriesCompanion(
          accountId: drift.Value(bankAccountId),
          categoryId: const drift.Value(null),
          amount: const drift.Value(10000),
          amountInBase: const drift.Value(10000),
          exchangeRate: const drift.Value(1.0),
        ),
        // Credit Income Category (-80 EUR) - Unbalanced by 20 EUR!
        EntriesCompanion(
          accountId: const drift.Value(null),
          categoryId: drift.Value(incomeCategoryId),
          amount: const drift.Value(-8000),
          amountInBase: const drift.Value(-8000),
          exchangeRate: const drift.Value(1.0),
        ),
      ];

      expect(
        () => db.createBalancedTransaction(
          transaction: txCompanion,
          entries: entriesComcompanions,
        ),
        throwsA(isA<Exception>()),
      );

      // Verify that no transaction and no entries were saved (rollback verified)
      final savedTxs = await db.select(db.transactions).get();
      expect(savedTxs.isEmpty, true);

      final savedEntries = await db.select(db.entries).get();
      expect(savedEntries.isEmpty, true);
    });

    test('Saving transaction with less than 2 entries should fail', () async {
      final txCompanion = TransactionsCompanion(
        date: drift.Value(DateTime.now()),
        description: const drift.Value('Single Entry'),
      );

      final entriesComcompanions = [
        EntriesCompanion(
          accountId: drift.Value(bankAccountId),
          categoryId: const drift.Value(null),
          amount: const drift.Value(0), // Balanced by itself, but illegal as ledger entry count < 2
          amountInBase: const drift.Value(0),
          exchangeRate: const drift.Value(1.0),
        ),
      ];

      expect(
        () => db.createBalancedTransaction(
          transaction: txCompanion,
          entries: entriesComcompanions,
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('Saving a transaction with a custom date should persist that specific custom date', () async {
      final customDate = DateTime(2025, 12, 25, 10, 30);
      final txCompanion = TransactionsCompanion(
        date: drift.Value(customDate),
        description: const drift.Value('Custom Date Transaction'),
      );

      final entriesComcompanions = [
        EntriesCompanion(
          accountId: drift.Value(bankAccountId),
          categoryId: const drift.Value(null),
          amount: const drift.Value(5000),
          amountInBase: const drift.Value(5000),
          exchangeRate: const drift.Value(1.0),
        ),
        EntriesCompanion(
          accountId: const drift.Value(null),
          categoryId: drift.Value(incomeCategoryId),
          amount: const drift.Value(-5000),
          amountInBase: const drift.Value(-5000),
          exchangeRate: const drift.Value(1.0),
        ),
      ];

      final txId = await db.createBalancedTransaction(
        transaction: txCompanion,
        entries: entriesComcompanions,
      );

      expect(txId, greaterThan(0));

      final savedTxs = await db.select(db.transactions).get();
      expect(savedTxs.length, 1);
      expect(savedTxs.first.date, customDate);
    });
  });

  group('Accounts and Categories CRUD & Integrity Tests', () {
    test('Category and Account CRUD operations', () async {
      // 1. Seed Macro Category
      final revenueMacroId = await db.into(db.macroCategories).insert(
            const MacroCategoriesCompanion(name: drift.Value('Revenues'), type: drift.Value('Revenue')),
          );

      // 2. Add Category
      final catId = await db.addCategory(CategoriesCompanion(
        macroCategoryId: drift.Value(revenueMacroId),
        name: const drift.Value('Test Revenue Category'),
      ));
      expect(catId, greaterThan(0));

      final categories = await db.select(db.categories).get();
      expect(categories.any((c) => c.id == catId && c.name == 'Test Revenue Category'), true);

      // 3. Update Category
      final category = categories.firstWhere((c) => c.id == catId);
      final updatedCat = category.copyWith(name: 'Updated Category Name');
      final updateSuccess = await db.updateCategory(updatedCat);
      expect(updateSuccess, true);

      final updatedCategories = await db.select(db.categories).get();
      expect(updatedCategories.any((c) => c.id == catId && c.name == 'Updated Category Name'), true);

      // 4. Add Account (No categoryId references)
      final accId = await db.addAccount(const AccountsCompanion(
        name: drift.Value('Test Account'),
        currency: drift.Value('USD'),
        type: drift.Value('bank'),
      ));
      expect(accId, greaterThan(0));

      final accounts = await db.select(db.accounts).get();
      expect(accounts.any((a) => a.id == accId && a.name == 'Test Account'), true);

      // 5. Update Account
      final account = accounts.firstWhere((a) => a.id == accId);
      final updatedAcc = account.copyWith(name: 'Updated Account Name');
      final updateAccSuccess = await db.updateAccount(updatedAcc);
      expect(updateAccSuccess, true);

      final updatedAccounts = await db.select(db.accounts).get();
      expect(updatedAccounts.any((a) => a.id == accId && a.name == 'Updated Account Name'), true);

      // 6. Delete Account & Category
      // Delete Account first
      await db.deleteAccount(accId);
      final postDeleteAccounts = await db.select(db.accounts).get();
      expect(postDeleteAccounts.any((a) => a.id == accId), false);

      // Delete Category
      await db.deleteCategory(catId);
      final postDeleteCategories = await db.select(db.categories).get();
      expect(postDeleteCategories.any((c) => c.id == catId), false);
    });

    test('Integrity checks prevent deleting categories and accounts with entries', () async {
      final revenueMacroId = await db.into(db.macroCategories).insert(
            const MacroCategoriesCompanion(name: drift.Value('Revenues'), type: drift.Value('Revenue')),
          );

      final catId = await db.addCategory(CategoriesCompanion(
        macroCategoryId: drift.Value(revenueMacroId),
        name: const drift.Value('Investment Category'),
      ));

      final accId = await db.addAccount(const AccountsCompanion(
        name: drift.Value('Brokerage Account'),
        currency: drift.Value('EUR'),
        type: drift.Value('bank'),
      ));

      // Attempt to delete category when it has no entries - should be true
      final canDeleteCatBefore = await db.canDeleteCategory(catId);
      expect(canDeleteCatBefore, true);

      // Attempt to delete account when it has no entries - should be true
      final canDeleteAccBefore = await db.canDeleteAccount(accId);
      expect(canDeleteAccBefore, true);

      // Add a balanced transaction using this account and category
      await db.createBalancedTransaction(
        transaction: TransactionsCompanion(
          date: drift.Value(DateTime.now()),
          description: const drift.Value('Broker Fee Payment'),
        ),
        entries: [
          EntriesCompanion(
            accountId: drift.Value(accId),
            categoryId: const drift.Value(null),
            amount: const drift.Value(-1000), // Credit Brokerage (-10 EUR)
            amountInBase: const drift.Value(-1000),
          ),
          EntriesCompanion(
            accountId: const drift.Value(null),
            categoryId: drift.Value(catId),
            amount: const drift.Value(1000), // Debit Fees (+10 EUR)
            amountInBase: const drift.Value(1000),
          ),
        ],
      );

      // Now attempt to delete account when it has entries - should be false
      final canDeleteAccAfter = await db.canDeleteAccount(accId);
      expect(canDeleteAccAfter, false);

      // Now attempt to delete category when it has entries - should be false
      final canDeleteCatAfter = await db.canDeleteCategory(catId);
      expect(canDeleteCatAfter, false);
    });
  });
}
