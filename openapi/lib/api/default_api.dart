//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;


class DefaultApi {
  DefaultApi([ApiClient? apiClient]) : apiClient = apiClient ?? defaultApiClient;

  final ApiClient apiClient;

  /// Send a message to ChatGPT
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [Message] message (required):
  Future<Response> chatWithHttpInfo(Message message,) async {
    // ignore: prefer_const_declarations
    final path = r'/chat';

    // ignore: prefer_final_locals
    Object? postBody = message;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

    const contentTypes = <String>['application/json'];


    return apiClient.invokeAPI(
      path,
      'POST',
      queryParams,
      postBody,
      headerParams,
      formParams,
      contentTypes.isEmpty ? null : contentTypes.first,
    );
  }

  /// Send a message to ChatGPT
  ///
  /// Parameters:
  ///
  /// * [Message] message (required):
  Future<Message?> chat(Message message,) async {
    final response = await chatWithHttpInfo(message,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'Message',) as Message;
    
    }
    return null;
  }

  /// Classify raw expense text into a structured ExpenseInput
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [ClassifyInput] classifyInput (required):
  Future<Response> classifyTextWithHttpInfo(ClassifyInput classifyInput,) async {
    // ignore: prefer_const_declarations
    final path = r'/classify';

    // ignore: prefer_final_locals
    Object? postBody = classifyInput;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

    const contentTypes = <String>['application/json'];


    return apiClient.invokeAPI(
      path,
      'POST',
      queryParams,
      postBody,
      headerParams,
      formParams,
      contentTypes.isEmpty ? null : contentTypes.first,
    );
  }

  /// Classify raw expense text into a structured ExpenseInput
  ///
  /// Parameters:
  ///
  /// * [ClassifyInput] classifyInput (required):
  Future<ExpenseInput?> classifyText(ClassifyInput classifyInput,) async {
    final response = await classifyTextWithHttpInfo(classifyInput,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'ExpenseInput',) as ExpenseInput;
    
    }
    return null;
  }

  /// Create a new expense
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [ExpenseInput] expenseInput (required):
  Future<Response> createExpenseWithHttpInfo(ExpenseInput expenseInput,) async {
    // ignore: prefer_const_declarations
    final path = r'/expenses';

    // ignore: prefer_final_locals
    Object? postBody = expenseInput;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

    const contentTypes = <String>['application/json'];


    return apiClient.invokeAPI(
      path,
      'POST',
      queryParams,
      postBody,
      headerParams,
      formParams,
      contentTypes.isEmpty ? null : contentTypes.first,
    );
  }

  /// Create a new expense
  ///
  /// Parameters:
  ///
  /// * [ExpenseInput] expenseInput (required):
  Future<Expense?> createExpense(ExpenseInput expenseInput,) async {
    final response = await createExpenseWithHttpInfo(expenseInput,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'Expense',) as Expense;
    
    }
    return null;
  }

  /// Delete an expense
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [int] id (required):
  Future<Response> deleteExpenseWithHttpInfo(int id,) async {
    // ignore: prefer_const_declarations
    final path = r'/expenses/{id}'
      .replaceAll('{id}', id.toString());

    // ignore: prefer_final_locals
    Object? postBody;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

    const contentTypes = <String>[];


    return apiClient.invokeAPI(
      path,
      'DELETE',
      queryParams,
      postBody,
      headerParams,
      formParams,
      contentTypes.isEmpty ? null : contentTypes.first,
    );
  }

  /// Delete an expense
  ///
  /// Parameters:
  ///
  /// * [int] id (required):
  Future<void> deleteExpense(int id,) async {
    final response = await deleteExpenseWithHttpInfo(id,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
  }

  /// List all expenses
  ///
  /// Note: This method returns the HTTP [Response].
  Future<Response> listExpensesWithHttpInfo() async {
    // ignore: prefer_const_declarations
    final path = r'/expenses';

    // ignore: prefer_final_locals
    Object? postBody;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

    const contentTypes = <String>[];


    return apiClient.invokeAPI(
      path,
      'GET',
      queryParams,
      postBody,
      headerParams,
      formParams,
      contentTypes.isEmpty ? null : contentTypes.first,
    );
  }

  /// List all expenses
  Future<List<Expense>?> listExpenses() async {
    final response = await listExpensesWithHttpInfo();
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      final responseBody = await _decodeBodyBytes(response);
      return (await apiClient.deserializeAsync(responseBody, 'List<Expense>') as List)
        .cast<Expense>()
        .toList(growable: false);

    }
    return null;
  }

  /// Update an existing expense
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [int] id (required):
  ///
  /// * [ExpenseInput] expenseInput (required):
  Future<Response> updateExpenseWithHttpInfo(int id, ExpenseInput expenseInput,) async {
    // ignore: prefer_const_declarations
    final path = r'/expenses/{id}'
      .replaceAll('{id}', id.toString());

    // ignore: prefer_final_locals
    Object? postBody = expenseInput;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

    const contentTypes = <String>['application/json'];


    return apiClient.invokeAPI(
      path,
      'PUT',
      queryParams,
      postBody,
      headerParams,
      formParams,
      contentTypes.isEmpty ? null : contentTypes.first,
    );
  }

  /// Update an existing expense
  ///
  /// Parameters:
  ///
  /// * [int] id (required):
  ///
  /// * [ExpenseInput] expenseInput (required):
  Future<Expense?> updateExpense(int id, ExpenseInput expenseInput,) async {
    final response = await updateExpenseWithHttpInfo(id, expenseInput,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'Expense',) as Expense;
    
    }
    return null;
  }
}
