import 'package:flutter/foundation.dart' hide Category;
import 'package:openapi/api.dart';

import '../services/api_errors.dart';

class ExpenseProvider extends ChangeNotifier {
  ExpenseProvider(this._api, {this.onUnauthorized});

  final DefaultApi _api;

  /// Called when the server answers 401 (token missing, invalid or
  /// expired). `main.dart` wires it to `AuthProvider.logout`.
  VoidCallback? onUnauthorized;

  /// Incremented by [clear]. Each request remembers the value it started
  /// with; a response that arrives after a logout or user switch no longer
  /// matches and is dropped, so it can't fill the lists of the next user.
  int _session = 0;

  List<Expense> _expenses = <Expense>[];
  List<Category> _categories = <Category>[];
  bool _isLoading = false;
  String? _error;

  List<Expense> get expenses => List.unmodifiable(_expenses);
  List<Category> get categories => List.unmodifiable(_categories);
  List<String> get categoryNames =>
      _categories.map((category) => category.name).toList();
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
        expense.category,
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

  /// Empties all user data, e.g. on logout. Requests still in flight are
  /// ignored when they return (see [_session]).
  void clear() {
    _session++;
    _expenses = <Expense>[];
    _categories = <Category>[];
    _isLoading = false;
    _error = null;
    notifyListeners();
  }

  /// Loads the available categories so the form dropdown can offer the
  /// existing set. Failures are non-fatal: the form can still free-text a
  /// category, which the server find-or-creates on save.
  Future<void> loadCategories() async {
    final session = _session;
    try {
      final result = await _api.listCategories();
      if (session != _session) return;
      _categories = result ?? <Category>[];
      notifyListeners();
    } catch (e) {
      _handleError(e, session, 'Failed to load categories');
    }
  }

  Future<void> loadExpenses() async {
    final session = _session;
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _api.listExpenses();
      if (session != _session) return;
      _expenses = result ?? <Expense>[];
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      if (session != _session) return;
      _isLoading = false;
      _handleError(e, session, 'Failed to load expenses');
    }
  }

  Future<bool> addExpense(ExpenseInput input) async {
    final session = _session;
    try {
      final created = await _api.createExpense(input);
      if (session != _session) return false;
      if (created != null) {
        _expenses = [..._expenses, created];
      } else {
        await loadExpenses();
      }
      _error = null;
      notifyListeners();
      return true;
    } catch (e) {
      _handleError(e, session, 'Failed to create expense');
      return false;
    }
  }

  Future<bool> editExpense(int id, ExpenseInput input) async {
    final session = _session;
    try {
      final updated = await _api.updateExpense(id, input);
      if (session != _session) return false;
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
      _handleError(e, session, 'Failed to update expense');
      return false;
    }
  }

  Future<bool> addCategory(String name) async {
    final session = _session;
    try {
      final created = await _api.createCategory(CategoryInput(name: name));
      if (session != _session) return false;
      if (created != null &&
          !_categories.any((c) =>
              c.name.toLowerCase() == created.name.toLowerCase())) {
        _categories = [..._categories, created];
        notifyListeners();
      }
      _error = null;
      return true;
    } catch (e) {
      _handleError(e, session, 'Failed to create category');
      return false;
    }
  }

  Future<bool> removeExpense(int id) async {
    final session = _session;
    try {
      await _api.deleteExpense(id);
      if (session != _session) return false;
      _expenses = _expenses.where((expense) => expense.id != id).toList();
      _error = null;
      notifyListeners();
      return true;
    } catch (e) {
      _handleError(e, session, 'Failed to delete expense');
      return false;
    }
  }

  /// A 401 ends the session via [onUnauthorized] (which clears this
  /// provider) instead of showing an error. Errors from an older session
  /// are dropped like stale responses.
  void _handleError(Object error, int session, String action) {
    if (session != _session) return;
    final callback = onUnauthorized;
    if (isUnauthorized(error) && callback != null) {
      callback();
      return;
    }
    _error = describeApiError(error, action);
    notifyListeners();
  }
}
