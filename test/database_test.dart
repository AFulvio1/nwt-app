import 'package:drift/native.dart';
import 'package:drift/drift.dart' as drift;
import 'package:flutter_test/flutter_test.dart';
import 'package:nwt_app/core/database/database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    // Open in-memory database for testing
    db = AppDatabase.executor(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('Double-Entry Ledger Validation Tests', () {
    late int bankAccountId;
    late int creditCardAccountId;

    setUp(() async {
      // Seed initial mock schema dependencies
      // 1. Macro categories
      final assetMacroId = await db.into(db.macroCategories).insert(
            const MacroCategoriesCompanion(name: drift.Value('Assets'), type: drift.Value('Asset')),
          );
      final liabilityMacroId = await db.into(db.macroCategories).insert(
            const MacroCategoriesCompanion(name: drift.Value('Liabilities'), type: drift.Value('Liability')),
          );

      // 2. Categories
      final bankCatId = await db.into(db.categories).insert(
            CategoriesCompanion(macroCategoryId: drift.Value(assetMacroId), name: const drift.Value('Bank')),
          );
      final cardCatId = await db.into(db.categories).insert(
            CategoriesCompanion(macroCategoryId: drift.Value(liabilityMacroId), name: const drift.Value('Credit Card')),
          );

      // 3. Accounts
      bankAccountId = await db.into(db.accounts).insert(
            AccountsCompanion(
              categoryId: drift.Value(bankCatId),
              name: const drift.Value('Bank Account'),
              currency: const drift.Value('EUR'),
            ),
          );
      creditCardAccountId = await db.into(db.accounts).insert(
            AccountsCompanion(
              categoryId: drift.Value(cardCatId),
              name: const drift.Value('Visa Card'),
              currency: const drift.Value('EUR'),
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
          amount: const drift.Value(10000),
          amountInBase: const drift.Value(10000),
          exchangeRate: const drift.Value(1.0),
        ),
        // Credit Credit Card Account (-100 EUR)
        EntriesCompanion(
          accountId: drift.Value(creditCardAccountId),
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
          amount: const drift.Value(10000),
          amountInBase: const drift.Value(10000),
          exchangeRate: const drift.Value(1.0),
        ),
        // Credit Credit Card (-80 EUR) - Unbalanced by 20 EUR!
        EntriesCompanion(
          accountId: drift.Value(creditCardAccountId),
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
  });

  group('Accounts and Categories CRUD & Integrity Tests', () {
    test('Category and Account CRUD operations', () async {
      // 1. Seed Macro Category
      final assetMacroId = await db.into(db.macroCategories).insert(
            const MacroCategoriesCompanion(name: drift.Value('Assets'), type: drift.Value('Asset')),
          );

      // 2. Add Category
      final catId = await db.addCategory(CategoriesCompanion(
        macroCategoryId: drift.Value(assetMacroId),
        name: const drift.Value('Test Bank Category'),
      ));
      expect(catId, greaterThan(0));

      final categories = await db.select(db.categories).get();
      expect(categories.any((c) => c.id == catId && c.name == 'Test Bank Category'), true);

      // 3. Update Category
      final category = categories.firstWhere((c) => c.id == catId);
      final updatedCat = category.copyWith(name: 'Updated Category Name');
      final updateSuccess = await db.updateCategory(updatedCat);
      expect(updateSuccess, true);

      final updatedCategories = await db.select(db.categories).get();
      expect(updatedCategories.any((c) => c.id == catId && c.name == 'Updated Category Name'), true);

      // 4. Add Account
      final accId = await db.addAccount(AccountsCompanion(
        categoryId: drift.Value(catId),
        name: const drift.Value('Test Account'),
        currency: const drift.Value('USD'),
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

    test('Integrity checks prevent deleting categories with accounts and accounts with entries', () async {
      final assetMacroId = await db.into(db.macroCategories).insert(
            const MacroCategoriesCompanion(name: drift.Value('Assets'), type: drift.Value('Asset')),
          );

      final catId = await db.addCategory(CategoriesCompanion(
        macroCategoryId: drift.Value(assetMacroId),
        name: const drift.Value('Investment Category'),
      ));

      final accId = await db.addAccount(AccountsCompanion(
        categoryId: drift.Value(catId),
        name: const drift.Value('Brokerage Account'),
        currency: const drift.Value('EUR'),
      ));

      // Attempt to delete category when it has accounts - should be false
      final canDeleteCatBefore = await db.canDeleteCategory(catId);
      expect(canDeleteCatBefore, false);

      // Attempt to delete account when it has no entries - should be true
      final canDeleteAccBefore = await db.canDeleteAccount(accId);
      expect(canDeleteAccBefore, true);

      // Add a balanced transaction using this account
      final expenseMacroId = await db.into(db.macroCategories).insert(
            const MacroCategoriesCompanion(name: drift.Value('Expenses'), type: drift.Value('Expense')),
          );
      final expenseCatId = await db.addCategory(CategoriesCompanion(
        macroCategoryId: drift.Value(expenseMacroId),
        name: const drift.Value('Fees'),
      ));
      final expenseAccId = await db.addAccount(AccountsCompanion(
        categoryId: drift.Value(expenseCatId),
        name: const drift.Value('Broker Fees'),
        currency: const drift.Value('EUR'),
      ));

      await db.createBalancedTransaction(
        transaction: TransactionsCompanion(
          date: drift.Value(DateTime.now()),
          description: const drift.Value('Broker Fee Payment'),
        ),
        entries: [
          EntriesCompanion(
            accountId: drift.Value(accId),
            amount: const drift.Value(-1000), // Credit Brokerage (-10 EUR)
            amountInBase: const drift.Value(-1000),
          ),
          EntriesCompanion(
            accountId: drift.Value(expenseAccId),
            amount: const drift.Value(1000), // Debit Fees (+10 EUR)
            amountInBase: const drift.Value(1000),
          ),
        ],
      );

      // Now attempt to delete account when it has entries - should be false
      final canDeleteAccAfter = await db.canDeleteAccount(accId);
      expect(canDeleteAccAfter, false);
    });
  });
}
