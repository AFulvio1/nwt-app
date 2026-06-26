import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' as drift;
import 'package:nwt_app/core/database/database.dart';
import 'package:nwt_app/features/transactions/transaction_modal.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.executor(NativeDatabase.memory(setup: (database) {
      database.execute('PRAGMA foreign_keys = ON;');
    }));
    // Seed initial dependencies
    final revMacroId = await db.into(db.macroCategories).insert(
      const MacroCategoriesCompanion(name: drift.Value('Revenues'), type: drift.Value('Revenue')),
    );
    final expMacroId = await db.into(db.macroCategories).insert(
      const MacroCategoriesCompanion(name: drift.Value('Expenses'), type: drift.Value('Expense')),
    );
    await db.into(db.categories).insert(
      CategoriesCompanion(macroCategoryId: drift.Value(revMacroId), name: const drift.Value('Income')),
    );
    await db.into(db.categories).insert(
      CategoriesCompanion(macroCategoryId: drift.Value(expMacroId), name: const drift.Value('Groceries')),
    );
    await db.into(db.accounts).insert(
      const AccountsCompanion(name: drift.Value('Bank Account'), currency: drift.Value('EUR'), type: drift.Value('bank')),
    );
    // Seed base_currency setting
    await db.into(db.appSettings).insert(
      const AppSettingsCompanion(key: drift.Value('base_currency'), value: drift.Value('EUR')),
    );
  });

  tearDown(() async {
    await db.close();
  });

  testWidgets('TransactionModal saves transaction with selected custom date', (WidgetTester tester) async {
    // Build the modal widget inside a ProviderScope with our in-memory database
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: TransactionModal(),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify it rendered
    expect(find.byType(TransactionModal), findsOneWidget);

    // Description is entered
    await tester.enterText(find.widgetWithText(TextFormField, 'Description'), 'Custom Date UI Test');

    // Enter Amount
    await tester.enterText(find.widgetWithText(TextFormField, 'Amount'), '150');

    // Tap Date picker button
    final dateButtonFinder = find.byIcon(Icons.calendar_today);
    expect(dateButtonFinder, findsOneWidget);
    await tester.tap(dateButtonFinder);
    await tester.pumpAndSettle();

    // Tap day 15
    await tester.tap(find.text('15'));
    await tester.pumpAndSettle();

    // Tap OK
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    // Record Transaction
    await tester.tap(find.text('Record Transaction'));
    await tester.pumpAndSettle();

    // Verify saved transaction has custom date
    final savedTxs = await db.select(db.transactions).get();
    expect(savedTxs.length, 1);
    final tx = savedTxs.first;
    expect(tx.description, 'Custom Date UI Test');
    expect(tx.date.day, 15);

    // Clean up widget tree to dispose stream providers and clear any pending timers
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
