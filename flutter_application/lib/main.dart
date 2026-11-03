import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:openapi/api.dart';

import 'providers/expense_provider.dart';

void main() {
  // Erzeugt ein Objekt vom Typ ApiClient mit der URL des lokalen Servers
  final apiClient = ApiClient(basePath: 'http://localhost:8082');

  runApp(
    MultiProvider(
      providers: [
        Provider<ApiClient>.value(value: apiClient),
        ChangeNotifierProvider<ExpenseProvider>(
          create: (_) => ExpenseProvider(DefaultApi(apiClient))..loadExpenses(),
        ),
      ],
      child: const SmartSpendApp(),
    ),
  );
}

class SmartSpendApp extends StatelessWidget {
  const SmartSpendApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Spend',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const DashboardScreen(),
    );
  }
}

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart Spend'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () =>
                context.read<ExpenseProvider>().loadExpenses(),
          ),
        ],
      ),
      body: Consumer<ExpenseProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (provider.error != null) {
            return _ErrorView(
              message: provider.error!,
              onRetry: provider.loadExpenses,
            );
          }

          if (provider.expenses.isEmpty) {
            return const Center(
              child: Text('No expenses yet. Tap + to add one.'),
            );
          }

          return RefreshIndicator(
            onRefresh: provider.loadExpenses,
            child: Column(
              children: [
                _TotalBanner(total: provider.total),
                Expanded(
                  child: ListView.separated(
                    itemCount: provider.expenses.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final expense = provider.expenses[index];
                      return _ExpenseTile(expense: expense);
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openForm(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _openForm(BuildContext context, {Expense? existing}) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ExpenseFormScreen(existing: existing),
      ),
    );
  }
}

class _TotalBanner extends StatelessWidget {
  const _TotalBanner({required this.total});

  final double total;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Text(
        'Total: ${total.toStringAsFixed(2)} €',
        style: Theme.of(context).textTheme.titleLarge,
      ),
    );
  }
}

class _ExpenseTile extends StatelessWidget {
  const _ExpenseTile({required this.expense});

  final Expense expense;

  @override
  Widget build(BuildContext context) {
    final provider = context.read<ExpenseProvider>();
    return ListTile(
      title: Text(expense.title),
      subtitle: Text(
        expense.subcategory == null || expense.subcategory!.isEmpty
            ? expense.category.value
            : '${expense.category.value} · ${expense.subcategory}',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${expense.amount.toStringAsFixed(2)} €',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit, size: 20),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ExpenseFormScreen(existing: expense),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Delete',
            icon: const Icon(Icons.delete_outline, size: 20),
            onPressed: () => provider.removeExpense(expense.id),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class ExpenseFormScreen extends StatefulWidget {
  const ExpenseFormScreen({super.key, this.existing});

  final Expense? existing;

  @override
  State<ExpenseFormScreen> createState() => _ExpenseFormScreenState();
}

class _ExpenseFormScreenState extends State<ExpenseFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _amountController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _subcategoryController;
  final _nlController = TextEditingController();
  late ExpenseInputCategoryEnum _category;
  bool _submitting = false;
  bool _classifying = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _titleController = TextEditingController(text: existing?.title ?? '');
    _amountController = TextEditingController(
      text: existing != null ? existing.amount.toString() : '',
    );
    _descriptionController =
        TextEditingController(text: existing?.description ?? '');
    _subcategoryController =
        TextEditingController(text: existing?.subcategory ?? '');
    _category = existing == null
        ? ExpenseInputCategoryEnum.other
        : ExpenseInputCategoryEnum.values.firstWhere(
            (c) => c.value == existing.category.value,
            orElse: () => ExpenseInputCategoryEnum.other,
          );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    _descriptionController.dispose();
    _subcategoryController.dispose();
    _nlController.dispose();
    super.dispose();
  }

  Future<void> _classify() async {
    final text = _nlController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Type what you spent first.')),
      );
      return;
    }

    setState(() => _classifying = true);

    final api = DefaultApi(context.read<ApiClient>());
    try {
      final parsed = await api.classifyText(ClassifyInput(text: text));
      if (!mounted) return;
      if (parsed == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not parse that expense.')),
        );
        return;
      }
      setState(() {
        _titleController.text = parsed.title;
        _amountController.text = parsed.amount.toString();
        _category = ExpenseInputCategoryEnum.values.firstWhere(
          (c) => c.value == parsed.category.value,
          orElse: () => ExpenseInputCategoryEnum.other,
        );
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Review the fields, then add.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('AI parsing failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _classifying = false);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _submitting = true);

    final description = _descriptionController.text.trim();
    final subcategory = _subcategoryController.text.trim();
    final input = ExpenseInput(
      title: _titleController.text.trim(),
      category: _category,
      amount: double.parse(_amountController.text.trim().replaceAll(',', '.')),
      description: description.isEmpty ? null : description,
      subcategory: subcategory.isEmpty ? null : subcategory,
    );

    final provider = context.read<ExpenseProvider>();
    final success = _isEditing
        ? await provider.editExpense(widget.existing!.id, input)
        : await provider.addExpense(input);

    if (!mounted) return;

    if (success) {
      Navigator.of(context).pop();
    } else {
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(provider.error ?? 'Something went wrong')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Expense' : 'New Expense'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              if (!_isEditing) ...[
                TextField(
                  controller: _nlController,
                  decoration: const InputDecoration(
                    labelText: 'Describe your expense',
                    hintText: 'e.g. I spent 15 euros on cinema tickets',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.auto_awesome),
                  ),
                  onSubmitted: (_) => _classifying ? null : _classify(),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _classifying ? null : _classify,
                  icon: _classifying
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_awesome),
                  label: Text(_classifying ? 'Parsing…' : 'Parse with AI'),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Divider(),
                ),
              ],
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  border: OutlineInputBorder(),
                ),
                validator: (value) =>
                    (value == null || value.trim().isEmpty)
                        ? 'Title is required'
                        : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _amountController,
                decoration: const InputDecoration(
                  labelText: 'Amount (€)',
                  border: OutlineInputBorder(),
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Amount is required';
                  }
                  final parsed =
                      double.tryParse(value.trim().replaceAll(',', '.'));
                  if (parsed == null) return 'Enter a valid number';
                  if (parsed <= 0) return 'Amount must be positive';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<ExpenseInputCategoryEnum>(
                initialValue: _category,
                decoration: const InputDecoration(
                  labelText: 'Category',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final category in ExpenseInputCategoryEnum.values)
                    DropdownMenuItem(
                      value: category,
                      child: Text(category.value),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _category = value);
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Description (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _subcategoryController,
                decoration: const InputDecoration(
                  labelText: 'Subcategory (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(_isEditing ? 'Save Changes' : 'Add Expense'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
