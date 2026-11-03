import 'package:openapi/api.dart';
import 'package:server_app/services/ai_service.dart';
import 'package:test/test.dart';

void main() {
  group('AiService.parseExpenseJson', () {
    test('parses a clean JSON object', () {
      final input = AiService.parseExpenseJson(
        '{"title": "Cinema", "category": "entertainment", "amount": 15}',
      );
      expect(input.title, 'Cinema');
      expect(input.category, ExpenseInputCategoryEnum.entertainment);
      expect(input.amount, 15.0);
    });

    test('extracts JSON embedded in prose / code fences', () {
      final raw = '''
Here is the parsed expense:
```json
{"title": "Groceries", "category": "food", "amount": 42.5}
```
Hope that helps!
''';
      final input = AiService.parseExpenseJson(raw);
      expect(input.title, 'Groceries');
      expect(input.category, ExpenseInputCategoryEnum.food);
      expect(input.amount, 42.5);
    });

    test('falls back to "other" for an unknown category', () {
      final input = AiService.parseExpenseJson(
        '{"title": "Mystery", "category": "banana", "amount": 7}',
      );
      expect(input.category, ExpenseInputCategoryEnum.other);
    });

    test('parses a string amount with a comma decimal separator', () {
      final input = AiService.parseExpenseJson(
        '{"title": "Bus", "category": "transport", "amount": "3,50"}',
      );
      expect(input.amount, 3.5);
    });

    test('throws when no JSON object is present', () {
      expect(
        () => AiService.parseExpenseJson('I have no idea, sorry.'),
        throwsA(isA<AiServiceException>()),
      );
    });

    test('throws when title is missing', () {
      expect(
        () => AiService.parseExpenseJson(
          '{"category": "food", "amount": 5}',
        ),
        throwsA(isA<AiServiceException>()),
      );
    });

    test('throws when amount is missing or non-positive', () {
      expect(
        () => AiService.parseExpenseJson(
          '{"title": "Free", "category": "food", "amount": 0}',
        ),
        throwsA(isA<AiServiceException>()),
      );
      expect(
        () => AiService.parseExpenseJson(
          '{"title": "No amount", "category": "food"}',
        ),
        throwsA(isA<AiServiceException>()),
      );
    });
  });
}
