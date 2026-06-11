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
}
