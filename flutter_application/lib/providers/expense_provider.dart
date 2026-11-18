import 'package:flutter/foundation.dart';
import 'package:openapi/api.dart';

class ExpenseProvider extends ChangeNotifier {
  ExpenseProvider(this._api);

  final DefaultApi _api;

  List<Expense> _expenses = <Expense>[];
  bool _isLoading = false;
  String? _error;

  List<Expense> get expenses => List.unmodifiable(_expenses);
  bool get isLoading => _isLoading;
  String? get error => _error;

  double get total =>
      _expenses.fold(0, (sum, expense) => sum + expense.amount);

  /// Total spend grouped by category value (e.g. "food" -> 42.0), sorted
  /// from highest to lowest. Categories with no expenses are omitted.
  Map<String, double> get spendByCategory {
    final totals = <String, double>{};
    for (final expense in _expenses) {
      totals.update(
        expense.category.value,
        (value) => value + expense.amount,
        ifAbsent: () => expense.amount,
      );
    }
    final sorted = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return {for (final entry in sorted) entry.key: entry.value};
  }

  /// Total spend grouped by subcategory, sorted from highest to lowest.
  /// Expenses without a subcategory (null or empty) are grouped under the
  /// key "(none)" so the total still reconciles with the overall spend.
  Map<String, double> get spendBySubcategory {
    final totals = <String, double>{};
    for (final expense in _expenses) {
      final sub = expense.subcategory;
      final key = (sub == null || sub.trim().isEmpty) ? '(none)' : sub.trim();
      totals.update(
        key,
        (value) => value + expense.amount,
        ifAbsent: () => expense.amount,
      );
    }
    final sorted = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return {for (final entry in sorted) entry.key: entry.value};
  }

  /// Total spend for the last [months] calendar months (including the current
  /// one), keyed by `YYYY-MM` and ordered oldest-first. Months with no
  /// expenses are still present with a value of 0 so the trend chart has a
  /// continuous x-axis.
  Map<String, double> spendByMonth({int months = 6, DateTime? now}) {
    final anchor = now ?? DateTime.now();
    final buckets = <String, double>{};
    for (var i = months - 1; i >= 0; i--) {
      final month = DateTime(anchor.year, anchor.month - i);
      buckets[_monthKey(month)] = 0;
    }
    for (final expense in _expenses) {
      final key = _monthKey(expense.timestamp);
      if (buckets.containsKey(key)) {
        buckets[key] = buckets[key]! + expense.amount;
      }
    }
    return buckets;
  }

  /// Total spend for the calendar month of [now] (defaults to the real now).
  double currentMonthTotal({DateTime? now}) {
    final anchor = now ?? DateTime.now();
    return _totalForMonth(anchor.year, anchor.month);
  }

  /// Total spend for the calendar month before [now].
  double lastMonthTotal({DateTime? now}) {
    final anchor = now ?? DateTime.now();
    final previous = DateTime(anchor.year, anchor.month - 1);
    return _totalForMonth(previous.year, previous.month);
  }

  /// Fractional change from last month to this month (0.2 == +20%).
  ///
  /// Returns `null` when last month had no spend (growth from zero is
  /// undefined), so the UI can show a neutral state instead of "∞%".
  double? monthOverMonthChange({DateTime? now}) {
    final last = lastMonthTotal(now: now);
    if (last == 0) return null;
    return (currentMonthTotal(now: now) - last) / last;
  }

  /// Number of expenses recorded in the current calendar month.
  int currentMonthCount({DateTime? now}) {
    final anchor = now ?? DateTime.now();
    return _expenses
        .where((e) =>
            e.timestamp.year == anchor.year &&
            e.timestamp.month == anchor.month)
        .length;
  }

  /// The highest-spending category value overall, or `null` when there are no
  /// expenses yet.
  String? get topCategory {
    final byCategory = spendByCategory;
    return byCategory.isEmpty ? null : byCategory.keys.first;
  }

  /// Mean amount across all recorded expenses, or 0 when there are none.
  double get averageExpense =>
      _expenses.isEmpty ? 0 : total / _expenses.length;

  double _totalForMonth(int year, int month) => _expenses
      .where((e) => e.timestamp.year == year && e.timestamp.month == month)
      .fold(0.0, (sum, e) => sum + e.amount);

  String _monthKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}';

  Future<void> loadExpenses() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _api.listExpenses();
      _expenses = result ?? <Expense>[];
    } catch (e) {
      _error = 'Failed to load expenses: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> addExpense(ExpenseInput input) async {
    try {
      final created = await _api.createExpense(input);
      if (created != null) {
        _expenses = [..._expenses, created];
      } else {
        await loadExpenses();
      }
      _error = null;
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Failed to create expense: $e';
      notifyListeners();
      return false;
    }
  }

  Future<bool> editExpense(int id, ExpenseInput input) async {
    try {
      final updated = await _api.updateExpense(id, input);
      if (updated != null) {
        _expenses = [
          for (final expense in _expenses)
            if (expense.id == id) updated else expense,
        ];
      } else {
        await loadExpenses();
      }
      _error = null;
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Failed to update expense: $e';
      notifyListeners();
      return false;
    }
  }

  Future<bool> removeExpense(int id) async {
    try {
      await _api.deleteExpense(id);
      _expenses = _expenses.where((expense) => expense.id != id).toList();
      _error = null;
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Failed to delete expense: $e';
      notifyListeners();
      return false;
    }
  }
}
