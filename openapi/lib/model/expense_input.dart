//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class ExpenseInput {
  /// Returns a new [ExpenseInput] instance.
  ExpenseInput({
    required this.title,
    required this.category,
    required this.amount,
    this.description,
    this.subcategory,
  });

  String title;

  ExpenseInputCategoryEnum category;

  double amount;

  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  String? description;

  /// Optional free-text secondary tag for expenses that span two categories (e.g. \"Hundehaftpflichtversicherung\" is insurance but also pet-related). Not enum-constrained on purpose — revisit if this needs structure later. 
  ///
  /// Please note: This property should have been non-nullable! Since the specification file
  /// does not include a default value (using the "default:" property), however, the generated
  /// source code must fall back to having a nullable type.
  /// Consider adding a "default:" property in the specification file to hide this note.
  ///
  String? subcategory;

  @override
  bool operator ==(Object other) => identical(this, other) || other is ExpenseInput &&
    other.title == title &&
    other.category == category &&
    other.amount == amount &&
    other.description == description &&
    other.subcategory == subcategory;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (title.hashCode) +
    (category.hashCode) +
    (amount.hashCode) +
    (description == null ? 0 : description!.hashCode) +
    (subcategory == null ? 0 : subcategory!.hashCode);

  @override
  String toString() => 'ExpenseInput[title=$title, category=$category, amount=$amount, description=$description, subcategory=$subcategory]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'title'] = this.title;
      json[r'category'] = this.category;
      json[r'amount'] = this.amount;
    if (this.description != null) {
      json[r'description'] = this.description;
    } else {
      json[r'description'] = null;
    }
    if (this.subcategory != null) {
      json[r'subcategory'] = this.subcategory;
    } else {
      json[r'subcategory'] = null;
    }
    return json;
  }

  /// Returns a new [ExpenseInput] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static ExpenseInput? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        requiredKeys.forEach((key) {
          assert(json.containsKey(key), 'Required key "ExpenseInput[$key]" is missing from JSON.');
          assert(json[key] != null, 'Required key "ExpenseInput[$key]" has a null value in JSON.');
        });
        return true;
      }());

      return ExpenseInput(
        title: mapValueOfType<String>(json, r'title')!,
        category: ExpenseInputCategoryEnum.fromJson(json[r'category'])!,
        amount: mapValueOfType<double>(json, r'amount')!,
        description: mapValueOfType<String>(json, r'description'),
        subcategory: mapValueOfType<String>(json, r'subcategory'),
      );
    }
    return null;
  }

  static List<ExpenseInput> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <ExpenseInput>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = ExpenseInput.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, ExpenseInput> mapFromJson(dynamic json) {
    final map = <String, ExpenseInput>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = ExpenseInput.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of ExpenseInput-objects as value to a dart map
  static Map<String, List<ExpenseInput>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<ExpenseInput>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = ExpenseInput.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'title',
    'category',
    'amount',
  };
}


class ExpenseInputCategoryEnum {
  /// Instantiate a new enum with the provided [value].
  const ExpenseInputCategoryEnum._(this.value);

  /// The underlying value of this enum member.
  final String value;

  @override
  String toString() => value;

  String toJson() => value;

  static const food = ExpenseInputCategoryEnum._(r'food');
  static const transport = ExpenseInputCategoryEnum._(r'transport');
  static const entertainment = ExpenseInputCategoryEnum._(r'entertainment');
  static const housing = ExpenseInputCategoryEnum._(r'housing');
  static const health = ExpenseInputCategoryEnum._(r'health');
  static const insurance = ExpenseInputCategoryEnum._(r'insurance');
  static const shopping = ExpenseInputCategoryEnum._(r'shopping');
  static const subscriptions = ExpenseInputCategoryEnum._(r'subscriptions');
  static const education = ExpenseInputCategoryEnum._(r'education');
  static const other = ExpenseInputCategoryEnum._(r'other');

  /// List of all possible values in this [enum][ExpenseInputCategoryEnum].
  static const values = <ExpenseInputCategoryEnum>[
    food,
    transport,
    entertainment,
    housing,
    health,
    insurance,
    shopping,
    subscriptions,
    education,
    other,
  ];

  static ExpenseInputCategoryEnum? fromJson(dynamic value) => ExpenseInputCategoryEnumTypeTransformer().decode(value);

  static List<ExpenseInputCategoryEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <ExpenseInputCategoryEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = ExpenseInputCategoryEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [ExpenseInputCategoryEnum] to String,
/// and [decode] dynamic data back to [ExpenseInputCategoryEnum].
class ExpenseInputCategoryEnumTypeTransformer {
  factory ExpenseInputCategoryEnumTypeTransformer() => _instance ??= const ExpenseInputCategoryEnumTypeTransformer._();

  const ExpenseInputCategoryEnumTypeTransformer._();

  String encode(ExpenseInputCategoryEnum data) => data.value;

  /// Decodes a [dynamic value][data] to a ExpenseInputCategoryEnum.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  ExpenseInputCategoryEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data != null) {
      switch (data) {
        case r'food': return ExpenseInputCategoryEnum.food;
        case r'transport': return ExpenseInputCategoryEnum.transport;
        case r'entertainment': return ExpenseInputCategoryEnum.entertainment;
        case r'housing': return ExpenseInputCategoryEnum.housing;
        case r'health': return ExpenseInputCategoryEnum.health;
        case r'insurance': return ExpenseInputCategoryEnum.insurance;
        case r'shopping': return ExpenseInputCategoryEnum.shopping;
        case r'subscriptions': return ExpenseInputCategoryEnum.subscriptions;
        case r'education': return ExpenseInputCategoryEnum.education;
        case r'other': return ExpenseInputCategoryEnum.other;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  /// Singleton [ExpenseInputCategoryEnumTypeTransformer] instance.
  static ExpenseInputCategoryEnumTypeTransformer? _instance;
}


