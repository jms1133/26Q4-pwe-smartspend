# openapi.api.DefaultApi

## Load the API package
```dart
import 'package:openapi/api.dart';
```

All URIs are relative to *http://localhost*

Method | HTTP request | Description
------------- | ------------- | -------------
[**chat**](DefaultApi.md#chat) | **POST** /chat | Send a message to ChatGPT
[**createExpense**](DefaultApi.md#createexpense) | **POST** /expenses | Create a new expense
[**deleteExpense**](DefaultApi.md#deleteexpense) | **DELETE** /expenses/{id} | Delete an expense
[**listExpenses**](DefaultApi.md#listexpenses) | **GET** /expenses | List all expenses
[**updateExpense**](DefaultApi.md#updateexpense) | **PUT** /expenses/{id} | Update an existing expense


# **chat**
> Message chat(message)

Send a message to ChatGPT

### Example
```dart
import 'package:openapi/api.dart';

final api_instance = DefaultApi();
final message = Message(); // Message | 

try {
    final result = api_instance.chat(message);
    print(result);
} catch (e) {
    print('Exception when calling DefaultApi->chat: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **message** | [**Message**](Message.md)|  | 

### Return type

[**Message**](Message.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **createExpense**
> Expense createExpense(expenseInput)

Create a new expense

### Example
```dart
import 'package:openapi/api.dart';

final api_instance = DefaultApi();
final expenseInput = ExpenseInput(); // ExpenseInput | 

try {
    final result = api_instance.createExpense(expenseInput);
    print(result);
} catch (e) {
    print('Exception when calling DefaultApi->createExpense: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **expenseInput** | [**ExpenseInput**](ExpenseInput.md)|  | 

### Return type

[**Expense**](Expense.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **deleteExpense**
> deleteExpense(id)

Delete an expense

### Example
```dart
import 'package:openapi/api.dart';

final api_instance = DefaultApi();
final id = 56; // int | 

try {
    api_instance.deleteExpense(id);
} catch (e) {
    print('Exception when calling DefaultApi->deleteExpense: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **id** | **int**|  | 

### Return type

void (empty response body)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: Not defined

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **listExpenses**
> List<Expense> listExpenses()

List all expenses

### Example
```dart
import 'package:openapi/api.dart';

final api_instance = DefaultApi();

try {
    final result = api_instance.listExpenses();
    print(result);
} catch (e) {
    print('Exception when calling DefaultApi->listExpenses: $e\n');
}
```

### Parameters
This endpoint does not need any parameter.

### Return type

[**List<Expense>**](Expense.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **updateExpense**
> Expense updateExpense(id, expenseInput)

Update an existing expense

### Example
```dart
import 'package:openapi/api.dart';

final api_instance = DefaultApi();
final id = 56; // int | 
final expenseInput = ExpenseInput(); // ExpenseInput | 

try {
    final result = api_instance.updateExpense(id, expenseInput);
    print(result);
} catch (e) {
    print('Exception when calling DefaultApi->updateExpense: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **id** | **int**|  | 
 **expenseInput** | [**ExpenseInput**](ExpenseInput.md)|  | 

### Return type

[**Expense**](Expense.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

