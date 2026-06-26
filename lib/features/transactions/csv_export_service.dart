import 'dart:io';
import 'package:csv/csv.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/database/database.dart';
import '../../shared/providers.dart';

class CsvExportService {
  static Future<void> exportAndShare(
    List<TransactionWithEntries> transactions,
    List<Account> accounts,
    List<Category> categories,
    List<MacroCategory> macros,
    String baseCurrency,
  ) async {
    final accountMap = {for (var a in accounts) a.id: a};
    final categoryMap = {for (var c in categories) c.id: c};
    final macroMap = {for (var m in macros) m.id: m};

    final headers = [
      'Date',
      'Description',
      'Type',
      'Account',
      'Category',
      'Amount',
      'Currency',
      'Amount in Base ($baseCurrency)'
    ];

    final List<List<dynamic>> rows = [headers];

    for (final txWithEntries in transactions) {
      final tx = txWithEntries.transaction;
      final entries = txWithEntries.entries;

      final dateStr = DateFormat('yyyy-MM-dd').format(tx.date);
      final desc = tx.description;

      final accountEntries = entries.where((e) => e.accountId != null).toList();
      final categoryEntries = entries.where((e) => e.categoryId != null).toList();

      String accountName = '';
      String categoryName = '';
      String txType = 'Transfer';
      double amount = 0.0;
      double amountInBase = 0.0;
      String currency = baseCurrency;

      if (categoryEntries.isNotEmpty) {
        final catEntry = categoryEntries.first;
        final cat = categoryMap[catEntry.categoryId];
        categoryName = cat?.name ?? 'Unknown Category';
        final macro = cat != null ? macroMap[cat.macroCategoryId] : null;

        if (macro != null) {
          txType = macro.type == 'Revenue' ? 'Income' : 'Expense';
        }

        if (accountEntries.isNotEmpty) {
          final accEntry = accountEntries.first;
          final acc = accountMap[accEntry.accountId];
          accountName = acc?.name ?? 'Unknown Account';
          currency = acc?.currency ?? baseCurrency;
          amount = (accEntry.amount / 100.0).abs();
          amountInBase = (accEntry.amountInBase / 100.0).abs();
        }
      } else {
        txType = 'Transfer';
        categoryName = 'Transfer';

        final List<String> accNames = [];
        for (final entry in accountEntries) {
          final acc = accountMap[entry.accountId];
          if (acc != null) {
            final double val = entry.amount / 100.0;
            accNames.add('${acc.name} (${val > 0 ? "+" : ""}${val.toStringAsFixed(2)} ${acc.currency})');
            if (val > 0) {
              amount = val;
              amountInBase = entry.amountInBase / 100.0;
              currency = acc.currency;
            }
          }
        }
        accountName = accNames.join(' -> ');
      }

      rows.add([
        dateStr,
        desc,
        txType,
        accountName,
        categoryName,
        amount,
        currency,
        amountInBase,
      ]);
    }

    final csvString = Csv().encode(rows);

    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/transactions_export.csv');
    await file.writeAsString(csvString);

    final xFile = XFile(file.path);
    await SharePlus.instance.share(
      ShareParams(
        files: [xFile],
        subject: 'Transactions Export',
      ),
    );
  }
}
