//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of openapi.api;

class Expense {
  /// Returns a new [Expense] instance.
  Expense({
    required this.title,
    required this.category,
    required this.amount,
    this.description,
    this.subcategory,
    required this.id,
    required this.timestamp,
  });

  String title;

  ExpenseCategoryEnum category;

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

  int id;

  DateTime timestamp;

  @override
  bool operator ==(Object other) => identical(this, other) || other is Expense &&
    other.title == title &&
    other.category == category &&
    other.amount == amount &&
    other.description == description &&
    other.subcategory == subcategory &&
    other.id == id &&
    other.timestamp == timestamp;

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (title.hashCode) +
    (category.hashCode) +
    (amount.hashCode) +
    (description == null ? 0 : description!.hashCode) +
    (subcategory == null ? 0 : subcategory!.hashCode) +
    (id.hashCode) +
    (timestamp.hashCode);

  @override
  String toString() => 'Expense[title=$title, category=$category, amount=$amount, description=$description, subcategory=$subcategory, id=$id, timestamp=$timestamp]';

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
      json[r'id'] = this.id;
      json[r'timestamp'] = this.timestamp.toUtc().toIso8601String();
    return json;
  }

  /// Returns a new [Expense] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static Expense? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        requiredKeys.forEach((key) {
          assert(json.containsKey(key), 'Required key "Expense[$key]" is missing from JSON.');
          assert(json[key] != null, 'Required key "Expense[$key]" has a null value in JSON.');
        });
        return true;
      }());

      return Expense(
        title: mapValueOfType<String>(json, r'title')!,
        category: ExpenseCategoryEnum.fromJson(json[r'category'])!,
        amount: mapValueOfType<double>(json, r'amount')!,
        description: mapValueOfType<String>(json, r'description'),
        subcategory: mapValueOfType<String>(json, r'subcategory'),
        id: mapValueOfType<int>(json, r'id')!,
        timestamp: mapDateTime(json, r'timestamp', r'')!,
      );
    }
    return null;
  }

  static List<Expense> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <Expense>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = Expense.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, Expense> mapFromJson(dynamic json) {
    final map = <String, Expense>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = Expense.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of Expense-objects as value to a dart map
  static Map<String, List<Expense>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<Expense>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = Expense.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'title',
    'category',
    'amount',
    'id',
    'timestamp',
  };
}


class ExpenseCategoryEnum {
  /// Instantiate a new enum with the provided [value].
  const ExpenseCategoryEnum._(this.value);

  /// The underlying value of this enum member.
  final String value;

  @override
  String toString() => value;

  String toJson() => value;

  static const food = ExpenseCategoryEnum._(r'food');
  static const transport = ExpenseCategoryEnum._(r'transport');
  static const entertainment = ExpenseCategoryEnum._(r'entertainment');
  static const housing = ExpenseCategoryEnum._(r'housing');
  static const health = ExpenseCategoryEnum._(r'health');
  static const insurance = ExpenseCategoryEnum._(r'insurance');
  static const shopping = ExpenseCategoryEnum._(r'shopping');
  static const subscriptions = ExpenseCategoryEnum._(r'subscriptions');
  static const education = ExpenseCategoryEnum._(r'education');
  static const other = ExpenseCategoryEnum._(r'other');

  /// List of all possible values in this [enum][ExpenseCategoryEnum].
  static const values = <ExpenseCategoryEnum>[
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

  static ExpenseCategoryEnum? fromJson(dynamic value) => ExpenseCategoryEnumTypeTransformer().decode(value);

  static List<ExpenseCategoryEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <ExpenseCategoryEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = ExpenseCategoryEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [ExpenseCategoryEnum] to String,
/// and [decode] dynamic data back to [ExpenseCategoryEnum].
class ExpenseCategoryEnumTypeTransformer {
  factory ExpenseCategoryEnumTypeTransformer() => _instance ??= const ExpenseCategoryEnumTypeTransformer._();

  const ExpenseCategoryEnumTypeTransformer._();

  String encode(ExpenseCategoryEnum data) => data.value;

  /// Decodes a [dynamic value][data] to a ExpenseCategoryEnum.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  ExpenseCategoryEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data != null) {
      switch (data) {
        case r'food': return ExpenseCategoryEnum.food;
        case r'transport': return ExpenseCategoryEnum.transport;
        case r'entertainment': return ExpenseCategoryEnum.entertainment;
        case r'housing': return ExpenseCategoryEnum.housing;
        case r'health': return ExpenseCategoryEnum.health;
        case r'insurance': return ExpenseCategoryEnum.insurance;
        case r'shopping': return ExpenseCategoryEnum.shopping;
        case r'subscriptions': return ExpenseCategoryEnum.subscriptions;
        case r'education': return ExpenseCategoryEnum.education;
        case r'other': return ExpenseCategoryEnum.other;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  /// Singleton [ExpenseCategoryEnumTypeTransformer] instance.
  static ExpenseCategoryEnumTypeTransformer? _instance;
}


