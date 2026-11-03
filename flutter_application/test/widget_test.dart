import 'package:flutter_test/flutter_test.dart';
import 'package:openapi/api.dart';

import 'package:flutter_application_1/providers/expense_provider.dart';

class FakeDefaultApi extends DefaultApi {
  FakeDefaultApi() : super(ApiClient());

  final List<Expense> store = <Expense>[];
  int _nextId = 1;
  bool throwOnNext = false;

  Expense _toExpense(int id, ExpenseInput input) => Expense(
        id: id,
        title: input.title,
        category: ExpenseCategoryEnum.fromJson(input.category.value)!,
        amount: input.amount,
        description: input.description,
        subcategory: input.subcategory,
        timestamp: DateTime.utc(2026, 1, 1),
      );

  void _maybeThrow() {
    if (throwOnNext) {
      throwOnNext = false;
      throw ApiException(500, 'boom');
    }
  }

  @override
  Future<List<Expense>?> listExpenses() async {
    _maybeThrow();
    return List<Expense>.from(store);
  }

  @override
  Future<Expense?> createExpense(ExpenseInput expenseInput) async {
    _maybeThrow();
    final expense = _toExpense(_nextId++, expenseInput);
    store.add(expense);
    return expense;
  }

  @override
  Future<Expense?> updateExpense(int id, ExpenseInput expenseInput) async {
    _maybeThrow();
    final updated = _toExpense(id, expenseInput);
    final index = store.indexWhere((e) => e.id == id);
    if (index != -1) store[index] = updated;
    return updated;
  }

  @override
  Future<void> deleteExpense(int id) async {
    _maybeThrow();
    store.removeWhere((e) => e.id == id);
  }
}

ExpenseInput _input({String title = 'Coffee', double amount = 3.5}) =>
    ExpenseInput(
      title: title,
      category: ExpenseInputCategoryEnum.food,
      amount: amount,
    );

void main() {
  group('ExpenseProvider', () {
    late FakeDefaultApi api;
    late ExpenseProvider provider;

    setUp(() {
      api = FakeDefaultApi();
      provider = ExpenseProvider(api);
    });

    test('loadExpenses populates list and toggles loading', () async {
      await api.createExpense(_input());
      var notified = 0;
      provider.addListener(() => notified++);

      await provider.loadExpenses();

      expect(provider.expenses, hasLength(1));
      expect(provider.isLoading, isFalse);
      expect(provider.error, isNull);
      expect(notified, greaterThanOrEqualTo(2));
    });

    test('addExpense appends and notifies', () async {
      var notified = 0;
      provider.addListener(() => notified++);

      final ok = await provider.addExpense(_input(title: 'Lunch'));

      expect(ok, isTrue);
      expect(provider.expenses, hasLength(1));
      expect(provider.expenses.first.title, 'Lunch');
      expect(notified, greaterThanOrEqualTo(1));
    });

    test('editExpense replaces matching item', () async {
      await provider.addExpense(_input(title: 'Old'));
      final id = provider.expenses.first.id;

      final ok = await provider.editExpense(id, _input(title: 'New'));

      expect(ok, isTrue);
      expect(provider.expenses, hasLength(1));
      expect(provider.expenses.first.title, 'New');
    });

    test('removeExpense drops matching item', () async {
      await provider.addExpense(_input());
      final id = provider.expenses.first.id;

      final ok = await provider.removeExpense(id);

      expect(ok, isTrue);
      expect(provider.expenses, isEmpty);
    });

    test('total sums all amounts', () async {
      await provider.addExpense(_input(amount: 2.0));
      await provider.addExpense(_input(amount: 3.5));

      expect(provider.total, 5.5);
    });

    test('addExpense sets error on failure', () async {
      api.throwOnNext = true;

      final ok = await provider.addExpense(_input());

      expect(ok, isFalse);
      expect(provider.error, isNotNull);
      expect(provider.expenses, isEmpty);
    });
  });
}
