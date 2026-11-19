import 'package:server_app/services/ai_service.dart';
import 'package:test/test.dart';

void main() {
  group('AiService.parseExpenseJson', () {
    test('parses a clean JSON object', () {
      final input = AiService.parseExpenseJson(
        '{"title": "Cinema", "category": "entertainment", "amount": 15}',
      );
      expect(input.title, 'Cinema');
      expect(input.category, 'entertainment');
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
      expect(input.category, 'food');
      expect(input.amount, 42.5);
    });

    test('keeps a non-seed category as free text', () {
      final input = AiService.parseExpenseJson(
        '{"title": "Mystery", "category": "banana", "amount": 7}',
      );
      expect(input.category, 'banana');
    });

    test('parses an optional subcategory', () {
      final input = AiService.parseExpenseJson(
        '{"title": "Casino night", "category": "entertainment", '
        '"amount": 50, "subcategory": "gambling"}',
      );
      expect(input.category, 'entertainment');
      expect(input.subcategory, 'gambling');
    });

    test('leaves subcategory null when absent', () {
      final input = AiService.parseExpenseJson(
        '{"title": "Cinema", "category": "entertainment", "amount": 15}',
      );
      expect(input.subcategory, isNull);
    });

    test('normalizes an empty/whitespace subcategory to null', () {
      final input = AiService.parseExpenseJson(
        '{"title": "Cinema", "category": "entertainment", '
        '"amount": 15, "subcategory": "   "}',
      );
      expect(input.subcategory, isNull);
    });

    test('falls back to "other" when category is missing', () {
      final input = AiService.parseExpenseJson(
        '{"title": "Mystery", "amount": 7}',
      );
      expect(input.category, 'other');
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
