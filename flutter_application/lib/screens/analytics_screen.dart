import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/expense_provider.dart';

const _categoryColors = <String, Color>{
  'food': Color(0xFFEF5350),
  'transport': Color(0xFF42A5F5),
  'entertainment': Color(0xFFAB47BC),
  'housing': Color(0xFF8D6E63),
  'health': Color(0xFF26A69A),
  'insurance': Color(0xFF5C6BC0),
  'shopping': Color(0xFFFFA726),
  'subscriptions': Color(0xFFEC407A),
  'education': Color(0xFF66BB6A),
  'other': Color(0xFF78909C),
};

Color _colorFor(String category) =>
    _categoryColors[category] ?? const Color(0xFF9E9E9E);

String _formatEuro(double value) => '${value.toStringAsFixed(2)} €';

class AnalyticsScreen extends StatelessWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Where your money goes')),
      body: Consumer<ExpenseProvider>(
        builder: (context, provider, _) {
          if (provider.expenses.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No data to analyze yet.\nAdd a few expenses to see where your money goes.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _SectionCard(
                title: 'By category',
                child: _CategoryBreakdown(provider: provider),
              ),
              const SizedBox(height: 16),
              _SectionCard(
                title: 'Spending over time',
                child: _MonthlyTrend(provider: provider),
              ),
              const SizedBox(height: 16),
              _SummaryGrid(provider: provider),
              const SizedBox(height: 16),
              _ComparisonCard(provider: provider),
              const SizedBox(height: 16),
              _SectionCard(
                title: 'Total per subcategory',
                child: _TotalsList(totals: provider.spendBySubcategory),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({required this.provider});

  final ExpenseProvider provider;

  @override
  Widget build(BuildContext context) {
    final topCategory = provider.topCategory;
    final tiles = <Widget>[
      _StatTile(
        label: 'This month',
        value: _formatEuro(provider.currentMonthTotal()),
        icon: Icons.calendar_month,
      ),
      _StatTile(
        label: 'Avg / expense',
        value: _formatEuro(provider.averageExpense),
        icon: Icons.receipt_long,
      ),
      _StatTile(
        label: 'This month count',
        value: '${provider.currentMonthCount()}',
        icon: Icons.format_list_numbered,
      ),
      _StatTile(
        label: 'Top category',
        value: topCategory ?? '—',
        icon: Icons.emoji_events,
        color: topCategory == null ? null : _colorFor(topCategory),
      ),
    ];

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 2.2,
      children: tiles,
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.icon,
    this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(icon, color: color ?? Theme.of(context).colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    style: Theme.of(context).textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ComparisonCard extends StatelessWidget {
  const _ComparisonCard({required this.provider});

  final ExpenseProvider provider;

  @override
  Widget build(BuildContext context) {
    final change = provider.monthOverMonthChange();
    final current = provider.currentMonthTotal();
    final last = provider.lastMonthTotal();

    final IconData icon;
    final Color color;
    final String headline;

    if (change == null) {
      icon = Icons.trending_flat;
      color = Theme.of(context).colorScheme.outline;
      headline = last == 0 && current == 0
          ? 'No spending recorded this month or last month.'
          : 'No spending last month to compare against.';
    } else if (change > 0) {
      icon = Icons.trending_up;
      color = Colors.red.shade600;
      headline =
          'You are spending ${(change * 100).toStringAsFixed(0)}% more than last month.';
    } else if (change < 0) {
      icon = Icons.trending_down;
      color = Colors.green.shade600;
      headline =
          'You are saving ${(change.abs() * 100).toStringAsFixed(0)}% compared to last month.';
    } else {
      icon = Icons.trending_flat;
      color = Theme.of(context).colorScheme.outline;
      headline = 'Your spending is flat versus last month.';
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, color: color, size: 40),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    headline,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(color: color, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'This month ${_formatEuro(current)} · '
                    'Last month ${_formatEuro(last)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryBreakdown extends StatelessWidget {
  const _CategoryBreakdown({required this.provider});

  final ExpenseProvider provider;

  @override
  Widget build(BuildContext context) {
    final byCategory = provider.spendByCategory;
    final total = byCategory.values.fold<double>(0, (sum, v) => sum + v);
    if (total == 0) {
      return const Text('No spending to break down yet.');
    }

    final entries = byCategory.entries.toList();

    return Column(
      children: [
        SizedBox(
          height: 180,
          child: PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 40,
              sections: [
                for (final entry in entries)
                  PieChartSectionData(
                    value: entry.value,
                    color: _colorFor(entry.key),
                    title: '${(entry.value / total * 100).toStringAsFixed(0)}%',
                    radius: 55,
                    titleStyle: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        ...entries.map(
          (entry) => _LegendRow(
            label: entry.key,
            amount: entry.value,
            percent: entry.value / total,
            color: _colorFor(entry.key),
          ),
        ),
      ],
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({
    required this.label,
    required this.amount,
    required this.percent,
    required this.color,
  });

  final String label;
  final double amount;
  final double percent;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(label)),
          Text(
            '${_formatEuro(amount)}  (${(percent * 100).toStringAsFixed(0)}%)',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _TotalsList extends StatelessWidget {
  const _TotalsList({required this.totals});

  final Map<String, double> totals;

  @override
  Widget build(BuildContext context) {
    final grandTotal = totals.values.fold<double>(0, (sum, v) => sum + v);
    if (grandTotal == 0) {
      return const Text('No spending to break down yet.');
    }

    return Column(
      children: [
        for (final entry in totals.entries)
          _LegendRow(
            label: entry.key,
            amount: entry.value,
            percent: entry.value / grandTotal,
            color: _colorFor(entry.key),
          ),
        const Divider(height: 24),
        Row(
          children: [
            const Expanded(
              child: Text('Total', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            Text(
              _formatEuro(grandTotal),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ],
    );
  }
}

class _MonthlyTrend extends StatelessWidget {
  const _MonthlyTrend({required this.provider});

  final ExpenseProvider provider;

  static const _monthLabels = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  @override
  Widget build(BuildContext context) {
    final byMonth = provider.spendByMonth();
    final keys = byMonth.keys.toList();
    final values = keys.map((k) => byMonth[k]!).toList();
    final maxValue = values.fold<double>(0, (max, v) => v > max ? v : max);

    if (maxValue == 0) {
      return const Text('No spending in the last months yet.');
    }

    return SizedBox(
      height: 200,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxValue * 1.2,
          borderData: FlBorderData(show: false),
          gridData: const FlGridData(show: true, drawVerticalLine: false),
          titlesData: FlTitlesData(
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: true, reservedSize: 40),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index < 0 || index >= keys.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      _labelFor(keys[index]),
                      style: const TextStyle(fontSize: 11),
                    ),
                  );
                },
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < values.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: values[i],
                    color: Theme.of(context).colorScheme.primary,
                    width: 18,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(4),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  String _labelFor(String monthKey) {
    final parts = monthKey.split('-');
    if (parts.length != 2) return monthKey;
    final month = int.tryParse(parts[1]);
    if (month == null || month < 1 || month > 12) return monthKey;
    return _monthLabels[month - 1];
  }
}
