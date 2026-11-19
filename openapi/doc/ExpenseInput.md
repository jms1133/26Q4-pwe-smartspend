# openapi.model.ExpenseInput

## Load the model package
```dart
import 'package:openapi/api.dart';
```

## Properties
Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**title** | **String** |  | 
**category** | **String** | The expense category as free text. No longer enum-constrained: categories are managed as data (see the /categories endpoints) so the AI (or user) can introduce new ones. On create/update the server find-or-creates the matching category (case-insensitive).  | 
**amount** | **double** |  | 
**description** | **String** |  | [optional] 
**subcategory** | **String** | Optional free-text secondary tag for expenses that span two categories (e.g. \"Hundehaftpflichtversicherung\" is insurance but also pet-related). Not enum-constrained on purpose — revisit if this needs structure later.  | [optional] 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


