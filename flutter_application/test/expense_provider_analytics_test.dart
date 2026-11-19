import 'package:flutter_application_1/providers/expense_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openapi/api.dart';

/// Minimal fake that lets us feed a fixed expense list into the provider
/// without any running server or database.
class _FakeDefaultApi extends DefaultApi {
  _FakeDefaultApi(this._expenses);

  final List<Expense> _expenses;

  @override
  Future<List<Expense>?> listExpenses() async => _expenses;
}

Expense _expense({
  required int id,
  required String category,
  required double amount,
  required DateTime timestamp,
  String title = 'x',
  String? subcategory,
}) {
  return Expense(
    id: id,
    title: title,
    category: category,
    amount: amount,
    timestamp: timestamp,
    subcategory: subcategory,
  );
}

void main() {
  // Anchor "now" to a fixed date so all month math is deterministic.
  final now = DateTime(2026, 3, 15);

  Future<ExpenseProvider> providerWith(List<Expense> expenses) async {
    final provider = ExpenseProvider(_FakeDefaultApi(expenses));
    await provider.loadExpenses();
    return provider;
  }

  group('ExpenseProvider analytics', () {
    test('spendByCategory sums per category and sorts descending', () async {
      final provider = await providerWith([
        _expense(id: 1, category: 'food', amount: 10, timestamp: now),
        _expense(id: 2, category: 'food', amount: 5, timestamp: now),
        _expense(id: 3, category: 'transport', amount: 20, timestamp: now),
      ]);

      final byCategory = provider.spendByCategory;

      expect(byCategory, {'transport': 20.0, 'food': 15.0});
      expect(byCategory.keys.first, 'transport');
    });

    test('spendBySubcategory groups by subcategory, missing under "(none)"',
        () async {
      final provider = await providerWith([
        _expense(
            id: 1,
            category: 'insurance',
            amount: 30,
            timestamp: now,
            subcategory: 'pet'),
        _expense(
            id: 2,
            category: 'shopping',
            amount: 70,
            timestamp: now,
            subcategory: 'pet'),
        _expense(id: 3, category: 'food', amount: 10, timestamp: now),
        _expense(
            id: 4,
            category: 'food',
            amount: 5,
            timestamp: now,
            subcategory: '   '),
      ]);

      final bySub = provider.spendBySubcategory;

      expect(bySub, {'pet': 100.0, '(none)': 15.0});
      expect(bySub.keys.first, 'pet');
    });

    test('topCategory returns the highest-spending category', () async {
      final provider = await providerWith([
        _expense(id: 1, category: 'food', amount: 10, timestamp: now),
        _expense(id: 2, category: 'housing', amount: 99, timestamp: now),
      ]);

      expect(provider.topCategory, 'housing');
    });

    test('topCategory is null and averageExpense is 0 with no data', () async {
      final provider = await providerWith([]);

      expect(provider.topCategory, isNull);
      expect(provider.averageExpense, 0);
    });

    test('averageExpense is the mean across all expenses', () async {
      final provider = await providerWith([
        _expense(id: 1, category: 'food', amount: 10, timestamp: now),
        _expense(id: 2, category: 'food', amount: 20, timestamp: now),
        _expense(id: 3, category: 'food', amount: 30, timestamp: now),
      ]);

      expect(provider.averageExpense, 20);
    });

    test('currentMonthTotal only counts the current calendar month', () async {
      final provider = await providerWith([
        _expense(id: 1, category: 'food', amount: 10, timestamp: now),
        _expense(
            id: 2,
            category: 'food',
            amount: 5,
            timestamp: DateTime(2026, 3, 1)),
        _expense(
            id: 3,
            category: 'food',
            amount: 100,
            timestamp: DateTime(2026, 2, 28)),
      ]);

      expect(provider.currentMonthTotal(now: now), 15);
      expect(provider.lastMonthTotal(now: now), 100);
    });

    test('currentMonthCount counts only this month\'s expenses', () async {
      final provider = await providerWith([
        _expense(id: 1, category: 'food', amount: 10, timestamp: now),
        _expense(id: 2, category: 'food', amount: 5, timestamp: now),
        _expense(
            id: 3,
            category: 'food',
            amount: 100,
            timestamp: DateTime(2026, 1, 10)),
      ]);

      expect(provider.currentMonthCount(now: now), 2);
    });

    test('monthOverMonthChange is positive when spending grew', () async {
      final provider = await providerWith([
        _expense(id: 1, category: 'food', amount: 120, timestamp: now),
        _expense(
            id: 2,
            category: 'food',
            amount: 100,
            timestamp: DateTime(2026, 2, 10)),
      ]);

      expect(provider.monthOverMonthChange(now: now), closeTo(0.2, 1e-9));
    });

    test('monthOverMonthChange is negative when spending shrank', () async {
      final provider = await providerWith([
        _expense(id: 1, category: 'food', amount: 50, timestamp: now),
        _expense(
            id: 2,
            category: 'food',
            amount: 100,
            timestamp: DateTime(2026, 2, 10)),
      ]);

      expect(provider.monthOverMonthChange(now: now), closeTo(-0.5, 1e-9));
    });

    test('monthOverMonthChange is null when last month had no spend', () async {
      final provider = await providerWith([
        _expense(id: 1, category: 'food', amount: 50, timestamp: now),
      ]);

      expect(provider.monthOverMonthChange(now: now), isNull);
    });

    test('spendByMonth returns continuous oldest-first buckets', () async {
      final provider = await providerWith([
        _expense(id: 1, category: 'food', amount: 10, timestamp: now),
        _expense(
            id: 2,
            category: 'food',
            amount: 30,
            timestamp: DateTime(2026, 1, 5)),
      ]);

      final byMonth = provider.spendByMonth(months: 6, now: now);

      expect(byMonth.keys.toList(), [
        '2025-10',
        '2025-11',
        '2025-12',
        '2026-01',
        '2026-02',
        '2026-03',
      ]);
      expect(byMonth['2026-03'], 10);
      expect(byMonth['2026-01'], 30);
      expect(byMonth['2025-11'], 0);
    });

    test('spendByMonth ignores expenses outside the window', () async {
      final provider = await providerWith([
        _expense(
            id: 1,
            category: 'food',
            amount: 999,
            timestamp: DateTime(2025, 1, 1)),
      ]);

      final byMonth = provider.spendByMonth(months: 6, now: now);

      expect(byMonth.values.every((v) => v == 0), isTrue);
    });
  });
}
