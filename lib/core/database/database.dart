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
  TextColumn get name => text()();
  TextColumn get currency => text()(); // e.g. EUR, USD, GBP
  TextColumn get type => text().withDefault(const Constant('bank'))(); // e.g. bank, cash
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
  IntColumn get accountId => integer().nullable().references(Accounts, #id)();
  IntColumn get categoryId => integer().nullable().references(Categories, #id)();
  IntColumn get amount => integer()(); // Cents. Debit (+), Credit (-)
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
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (m, from, to) async {
          // Destructive migration for development simplicity
          for (final table in allTables) {
            await m.drop(table);
          }
          await m.createAll();
        },
      );

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
  // ACCOUNTS CRUD
  // ---------------------------------------------------------

  Future<int> addAccount(AccountsCompanion account) => into(accounts).insert(account);
  Future<bool> updateAccount(Account account) => update(accounts).replace(account);
  Future<int> deleteAccount(int id) => (delete(accounts)..where((a) => a.id.equals(id))).go();

  Future<bool> canDeleteAccount(int accountId) async {
    final entry = await (select(entries)..where((e) => e.accountId.equals(accountId))..limit(1)).getSingleOrNull();
    return entry == null;
  }

  // ---------------------------------------------------------
  // CATEGORIES CRUD
  // ---------------------------------------------------------

  Future<int> addCategory(CategoriesCompanion category) => into(categories).insert(category);
  Future<bool> updateCategory(Category category) => update(categories).replace(category);
  Future<int> deleteCategory(int id) => (delete(categories)..where((c) => c.id.equals(id))).go();

  Future<bool> canDeleteCategory(int categoryId) async {
    final entry = await (select(entries)..where((e) => e.categoryId.equals(categoryId))..limit(1)).getSingleOrNull();
    return entry == null;
  }

  // ---------------------------------------------------------
  // SEEDING UTILITY
  // ---------------------------------------------------------

  Future<void> seedInitialData(String baseCurrency, {String template = 'personal'}) async {
    await transaction(() async {
      // 1. Insert settings
      await into(appSettings).insertOnConflictUpdate(
        AppSettingsCompanion(key: const Value('base_currency'), value: Value(baseCurrency)),
      );

      // Check if macro categories already exist
      final existingMacros = await select(macroCategories).get();
      if (existingMacros.isNotEmpty) return;

      // Seed macro categories
      final revenueId = await into(macroCategories).insert(const MacroCategoriesCompanion(name: Value('Revenues'), type: Value('Revenue')));
      final expenseId = await into(macroCategories).insert(const MacroCategoriesCompanion(name: Value('Expenses'), type: Value('Expense')));

      if (template == 'personal') {
        // Seed default categories
        await into(categories).insert(CategoriesCompanion(macroCategoryId: Value(revenueId), name: const Value('Income'), isDefault: const Value(true)));
        await into(categories).insert(CategoriesCompanion(macroCategoryId: Value(revenueId), name: const Value('Extra Income'), isDefault: const Value(true)));
        await into(categories).insert(CategoriesCompanion(macroCategoryId: Value(expenseId), name: const Value('Groceries'), isDefault: const Value(true)));
        await into(categories).insert(CategoriesCompanion(macroCategoryId: Value(expenseId), name: const Value('Rent'), isDefault: const Value(true)));
        await into(categories).insert(CategoriesCompanion(macroCategoryId: Value(expenseId), name: const Value('Utilities'), isDefault: const Value(true)));
        await into(categories).insert(CategoriesCompanion(macroCategoryId: Value(expenseId), name: const Value('Leisure'), isDefault: const Value(true)));
        await into(categories).insert(CategoriesCompanion(macroCategoryId: Value(expenseId), name: const Value('Travel'), isDefault: const Value(true)));
        await into(categories).insert(CategoriesCompanion(macroCategoryId: Value(expenseId), name: const Value('Other'), isDefault: const Value(true)));

        // Seed default accounts
        await into(accounts).insert(AccountsCompanion(
          name: const Value('Primary Bank Account'),
          currency: Value(baseCurrency),
          type: const Value('bank'),
        ));
        await into(accounts).insert(AccountsCompanion(
          name: const Value('Cash Wallet'),
          currency: Value(baseCurrency),
          type: const Value('cash'),
        ));
      } else if (template == 'business') {
        // Seed default categories
        await into(categories).insert(CategoriesCompanion(macroCategoryId: Value(revenueId), name: const Value('Sales Revenue'), isDefault: const Value(true)));
        await into(categories).insert(CategoriesCompanion(macroCategoryId: Value(revenueId), name: const Value('Other Revenue'), isDefault: const Value(true)));
        await into(categories).insert(CategoriesCompanion(macroCategoryId: Value(expenseId), name: const Value('Operating Expenses'), isDefault: const Value(true)));
        await into(categories).insert(CategoriesCompanion(macroCategoryId: Value(expenseId), name: const Value('Taxes'), isDefault: const Value(true)));
        await into(categories).insert(CategoriesCompanion(macroCategoryId: Value(expenseId), name: const Value('Software & Tools'), isDefault: const Value(true)));
        await into(categories).insert(CategoriesCompanion(macroCategoryId: Value(expenseId), name: const Value('Office & Rent'), isDefault: const Value(true)));
        await into(categories).insert(CategoriesCompanion(macroCategoryId: Value(expenseId), name: const Value('Other Expenses'), isDefault: const Value(true)));

        // Seed default accounts
        await into(accounts).insert(AccountsCompanion(
          name: const Value('Business Bank Account'),
          currency: Value(baseCurrency),
          type: const Value('bank'),
        ));
        await into(accounts).insert(AccountsCompanion(
          name: const Value('Cash Wallet'),
          currency: Value(baseCurrency),
          type: const Value('cash'),
        ));
      }
    });
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    // If the local workspace directory exists (development machine),
    // save the database directly in the project folder to make it easily
    // accessible to VS Code and SQLite Viewer without symlink/permission issues.
    final devDir = Directory('/Users/antoniofulvio/Projects/nwt-app');
    if (await devDir.exists()) {
      final file = File(p.join(devDir.path, 'nwt_database.sqlite'));
      return NativeDatabase.createInBackground(file);
    }

    final dbFolder = await getApplicationSupportDirectory();
    final file = File(p.join(dbFolder.path, 'nwt_database.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(() => db.close());
  return db;
});
