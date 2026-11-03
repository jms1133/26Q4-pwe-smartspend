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
