import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_riverpod/flutter_riverpod.dart';

part 'database.g.dart';

// ---------------------------------------------------------
// TABLES DEFINITIONS
// ---------------------------------------------------------

class MacroCategories extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get type => text()(); // Asset, Liability, Equity, Revenue, Expense
}

class Categories extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get macroCategoryId => integer().references(MacroCategories, #id, onDelete: KeyAction.cascade)();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();
}

class Accounts extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get categoryId => integer().references(Categories, #id)();
  TextColumn get name => text()();
  TextColumn get currency => text()(); // e.g. EUR, USD, GBP
  TextColumn get description => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
}

class Transactions extends Table {
  IntColumn get id => integer().autoIncrement()();
  DateTimeColumn get date => dateTime()();
  TextColumn get description => text()();
}

class Entries extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get transactionId => integer().references(Transactions, #id, onDelete: KeyAction.cascade)();
  IntColumn get accountId => integer().references(Accounts, #id)();
  IntColumn get amount => integer()(); // Cents in native account currency. Debit (+), Credit (-)
  IntColumn get amountInBase => integer()(); // Cents converted to base currency. Debit (+), Credit (-)
  RealColumn get exchangeRate => real().withDefault(const Constant(1.0))();
}

class Assets extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get ticker => text().nullable()();
  TextColumn get type => text()(); // Crypto, Stock, RealEstate, Commodity, Cash
  RealColumn get quantity => real()();
  IntColumn get averageBuyPrice => integer()(); // in cents (base currency)
  IntColumn get currentPrice => integer().nullable()(); // in cents (base currency)
}

class InvestmentTransactions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get transactionId => integer().references(Transactions, #id, onDelete: KeyAction.cascade)();
  IntColumn get assetId => integer().references(Assets, #id)();
  TextColumn get type => text()(); // BUY, SELL
  IntColumn get price => integer()(); // price per asset in cents (base currency)
  RealColumn get quantity => real()();
  IntColumn get fee => integer().withDefault(const Constant(0))(); // fee in cents (base currency)
}

class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  @override
  Set<Column> get primaryKey => {key};
}

// ---------------------------------------------------------
// DATABASE CLASS
// ---------------------------------------------------------

@DriftDatabase(tables: [
  MacroCategories,
  Categories,
  Accounts,
  Transactions,
  Entries,
  Assets,
  InvestmentTransactions,
  AppSettings,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());
  AppDatabase.executor(super.e);

  @override
  int get schemaVersion => 1;

  // Custom exception for unbalanced transactions
  static const String unbalancedErrorMessage = 'Double-entry transaction is not balanced in base currency. The sum of all base entries must equal exactly 0.';

  // ---------------------------------------------------------
  // TRANSACTION WRITING (ACID with Double-Entry Validation)
  // ---------------------------------------------------------

  /// Creates a transaction and its entries, validating that the sum of amountInBase equals exactly zero.
  Future<int> createBalancedTransaction({
    required TransactionsCompanion transaction,
    required List<EntriesCompanion> entries,
  }) async {
    return await this.transaction(() async {
      // 1. Validate total balance in base currency
      int sumBase = 0;
      for (final entry in entries) {
        if (!entry.amountInBase.present) {
          throw ArgumentError('Each entry must specify amountInBase.');
        }
        sumBase += entry.amountInBase.value;
      }

      if (sumBase != 0) {
        throw Exception('$unbalancedErrorMessage (Sum: ${sumBase / 100})');
      }

      if (entries.length < 2) {
        throw Exception('A transaction must contain at least two entries.');
      }

      // 2. Insert transaction
      final txId = await into(transactions).insert(transaction);

      // 3. Insert entries with the foreign key
      for (final entry in entries) {
        final entryWithTxId = entry.copyWith(transactionId: Value(txId));
        await into(this.entries).insert(entryWithTxId);
      }

      return txId;
    });
  }

  /// Deletes a transaction and all its entries (via cascade delete)
  Future<void> deleteTransaction(int transactionId) async {
    await (delete(transactions)..where((t) => t.id.equals(transactionId))).go();
  }

  // ---------------------------------------------------------
  // SEEDING UTILITY
  // ---------------------------------------------------------

  Future<void> seedInitialData(String baseCurrency) async {
    await transaction(() async {
      // 1. Insert settings
      await into(appSettings).insertOnConflictUpdate(
        AppSettingsCompanion(key: const Value('base_currency'), value: Value(baseCurrency)),
      );

      // Check if macro categories already exist
      final existingMacros = await select(macroCategories).get();
      if (existingMacros.isNotEmpty) return;

      // Seed macro categories
      final assetId = await into(macroCategories).insert(const MacroCategoriesCompanion(name: Value('Assets'), type: Value('Asset')));
      final liabilityId = await into(macroCategories).insert(const MacroCategoriesCompanion(name: Value('Liabilities'), type: Value('Liability')));
      final revenueId = await into(macroCategories).insert(const MacroCategoriesCompanion(name: Value('Revenues'), type: Value('Revenue')));
      final expenseId = await into(macroCategories).insert(const MacroCategoriesCompanion(name: Value('Expenses'), type: Value('Expense')));

      // Seed default categories
      final bankCatId = await into(categories).insert(CategoriesCompanion(macroCategoryId: Value(assetId), name: const Value('Cash & Bank'), isDefault: const Value(true)));
      final cardCatId = await into(categories).insert(CategoriesCompanion(macroCategoryId: Value(liabilityId), name: const Value('Credit Cards'), isDefault: const Value(true)));
      await into(categories).insert(CategoriesCompanion(macroCategoryId: Value(revenueId), name: const Value('Salary & Income'), isDefault: const Value(true)));
      await into(categories).insert(CategoriesCompanion(macroCategoryId: Value(expenseId), name: const Value('Groceries'), isDefault: const Value(true)));
      await into(categories).insert(CategoriesCompanion(macroCategoryId: Value(expenseId), name: const Value('Housing & Rent'), isDefault: const Value(true)));

      // Seed default accounts
      await into(accounts).insert(AccountsCompanion(
        categoryId: Value(bankCatId),
        name: const Value('Primary Bank Account'),
        currency: Value(baseCurrency),
      ));
      await into(accounts).insert(AccountsCompanion(
        categoryId: Value(bankCatId),
        name: const Value('Cash Wallet'),
        currency: Value(baseCurrency),
      ));
      await into(accounts).insert(AccountsCompanion(
        categoryId: Value(cardCatId),
        name: const Value('Primary Credit Card'),
        currency: Value(baseCurrency),
      ));
    });
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'nwt_database.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(() => db.close());
  return db;
});
