import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../core/database/database.dart';
import '../../shared/providers.dart';
import '../transactions/transaction_modal.dart';
import '../auth/auth_service.dart';

class DashboardView extends ConsumerWidget {
  const DashboardView({super.key});

  void _showTransactionModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const TransactionModal(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboardDataAsync = ref.watch(dashboardDataProvider);
    final recentTxsAsync = ref.watch(transactionsStreamProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Net Worth Tracker',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.lock_outline),
            onPressed: () {
              ref.read(authServiceProvider.notifier).lock();
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Reset Ledger'),
                  content: const Text('Are you sure you want to delete all settings, accounts, and transactions?'),
                  actions: [
                    TextButton(
                      child: const Text('Cancel'),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    TextButton(
                      style: TextButton.styleFrom(foregroundColor: Colors.red),
                      child: const Text('Reset'),
                      onPressed: () async {
                        Navigator.of(context).pop();
                        await ref.read(authServiceProvider.notifier).resetCredentials();
                      },
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showTransactionModal(context),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
      ),
      body: dashboardDataAsync.when(
        data: (data) => _buildContent(context, ref, data, recentTxsAsync.value ?? []),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
      ),
    );
  }

  Widget _buildContent(BuildContext context, WidgetRef ref, DashboardData data, List<TransactionWithEntries> txs) {
    final formatter = NumberFormat.simpleCurrency(name: data.baseCurrency, decimalDigits: 2);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Net Worth Central Card
          _buildNetWorthCard(context, data.netWorth, formatter),
          const SizedBox(height: 16),

          // Secondary KPI Cards (Assets & Liabilities)
          Row(
            children: [
              Expanded(
                child: _buildKpiCard(
                  context,
                  title: 'Assets',
                  amount: data.totalAssets,
                  formatter: formatter,
                  color: Theme.of(context).colorScheme.secondary,
                  icon: Icons.trending_up,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildKpiCard(
                  context,
                  title: 'Liabilities',
                  amount: data.totalLiabilities,
                  formatter: formatter,
                  color: Theme.of(context).colorScheme.error,
                  icon: Icons.trending_down,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Chart Section
          Text(
            'Net Worth Development',
            style: GoogleFonts.outfit(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          _buildChartCard(context, data),
          const SizedBox(height: 24),

          // Recent Transactions Section Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Recent Transactions',
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              TextButton(
                onPressed: () => _showTransactionModal(context),
                child: const Text('Add Entry'),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Transaction list
          if (txs.isEmpty)
            _buildEmptyTransactionsCard(context)
          else
            _buildTransactionsList(context, ref, txs, formatter),
        ],
      ),
    );
  }

  Widget _buildNetWorthCard(BuildContext context, double amount, NumberFormat formatter) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Theme.of(context).colorScheme.primary,
            Theme.of(context).colorScheme.primary.withRed(50).withBlue(220),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'NET WORTH',
                style: GoogleFonts.outfit(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
              const Icon(
                Icons.account_balance,
                color: Colors.white70,
                size: 20,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            formatter.format(amount),
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.shield_outlined, color: Colors.white70, size: 14),
              const SizedBox(width: 6),
              Text(
                'Secured Local Ledger',
                style: GoogleFonts.outfit(
                  color: Colors.white70,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildKpiCard(
    BuildContext context, {
    required String title,
    required double amount,
    required NumberFormat formatter,
    required Color color,
    required IconData icon,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title.toUpperCase(),
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).textTheme.bodyMedium?.color?.withValues(alpha: 0.6),
                  ),
                ),
                Icon(icon, size: 16, color: color),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              formatter.format(amount),
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChartCard(BuildContext context, DashboardData data) {
    if (data.historyPoints.isEmpty) {
      return Card(
        child: Container(
          height: 180,
          alignment: Alignment.center,
          child: Text(
            'No transactions recorded yet.\nStart by adding some transactions to see your chart.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).textTheme.bodyMedium?.color),
          ),
        ),
      );
    }

    final spots = <FlSpot>[];
    for (int i = 0; i < data.historyPoints.length; i++) {
      spots.add(FlSpot(i.toDouble(), data.historyPoints[i]['netWorth']));
    }

    // Ensure we have at least 2 points to draw a line
    if (spots.length == 1) {
      spots.insert(0, FlSpot(-1, spots[0].y));
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.only(top: 24, bottom: 8, left: 16, right: 24),
        child: SizedBox(
          height: 180,
          child: LineChart(
            LineChartData(
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (value) => FlLine(
                  color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
                  strokeWidth: 1,
                ),
              ),
              titlesData: FlTitlesData(
                show: true,
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 22,
                    interval: 1,
                    getTitlesWidget: (value, meta) {
                      final int idx = value.toInt();
                      if (idx >= 0 && idx < data.historyPoints.length) {
                        final DateTime date = data.historyPoints[idx]['date'];
                        return Text(
                          DateFormat('dd/MM').format(date),
                          style: const TextStyle(fontSize: 10),
                        );
                      }
                      return const Text('');
                    },
                  ),
                ),
              ),
              borderData: FlBorderData(show: false),
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: true,
                  gradient: LinearGradient(
                    colors: [
                      Theme.of(context).colorScheme.primary,
                      Theme.of(context).colorScheme.secondary,
                    ],
                  ),
                  barWidth: 3,
                  isStrokeCapRound: true,
                  dotData: const FlDotData(show: true),
                  belowBarData: BarAreaData(
                    show: true,
                    gradient: LinearGradient(
                      colors: [
                        Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
                        Theme.of(context).colorScheme.secondary.withValues(alpha: 0.02),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyTransactionsCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
        child: Column(
          children: [
            Icon(Icons.receipt_long_outlined, size: 48, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(
              'No Transactions Yet',
              style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 6),
            const Text(
              'Record your first double-entry transaction using the action button.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionsList(BuildContext context, WidgetRef ref, List<TransactionWithEntries> txs, NumberFormat formatter) {
    // Show top 5 recent transactions
    final itemsToShow = txs.take(5).toList();

    return Column(
      children: itemsToShow.map((txWithEntries) {
        final tx = txWithEntries.transaction;
        
        // Sum of debits (positive entries) to show as a single summary transaction amount
        double txSum = 0.0;
        for (final entry in txWithEntries.entries) {
          if (entry.amountInBase > 0) {
            txSum += entry.amountInBase / 100.0;
          }
        }

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
              foregroundColor: Theme.of(context).colorScheme.primary,
              child: const Icon(Icons.swap_horiz),
            ),
            title: Text(
              tx.description,
              style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            subtitle: Text(
              DateFormat('yyyy-MM-dd').format(tx.date),
              style: const TextStyle(fontSize: 12),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  formatter.format(txSum),
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20, color: Colors.grey),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Delete Transaction'),
                        content: const Text('Are you sure you want to delete this transaction from the ledger?'),
                        actions: [
                          TextButton(
                            child: const Text('Cancel'),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                          TextButton(
                            style: TextButton.styleFrom(foregroundColor: Colors.red),
                            child: const Text('Delete'),
                            onPressed: () async {
                              Navigator.of(context).pop();
                              await ref.read(databaseProvider).deleteTransaction(tx.id);
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
