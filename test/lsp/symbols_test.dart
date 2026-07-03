import 'package:apollovm/apollovm_lsp.dart';
import 'package:test/test.dart';

const _src = '''
abstract class Animal {
  int legs;
}
class Dog extends Animal implements Comparable {
  int age;
  Dog(int age) { this.age = age; }
  int bark(int n) { return n; }
}
enum Color { red, green, blue }
int makeAge(int seed) { return seed; }
''';

void main() {
  test(
    'collectSymbols captures classes, members, enum and functions',
    () async {
      final unit = await Analyzer().analyze('file:///s.dart', _src);
      expect(unit.ast, isNotNull);
      final byName = {
        for (final s in unit.symbols) '${s.container}:${s.name}': s,
      };

      SymbolInfo sym(String key) => byName[key]!;

      expect(sym('null:makeAge').category, SymbolCategory.function);
      expect(sym('null:makeAge').signature, 'int makeAge(int seed)');

      final animal = sym('null:Animal');
      expect(animal.category, SymbolCategory.classSym);
      expect(animal.signature, 'abstract class Animal');
      expect(animal.modifiers, contains('abstract'));

      expect(sym('Animal:legs').category, SymbolCategory.field);
      expect(sym('Animal:legs').signature, 'int legs');

      expect(
        sym('null:Dog').signature,
        'class Dog extends Animal implements Comparable',
      );

      expect(sym('Dog:bark').category, SymbolCategory.method);
      expect(sym('Dog:bark').signature, 'int bark(int n)');

      // Constructor (ApolloVM models its name as empty).
      expect(
        unit.symbols.any(
          (s) =>
              s.category == SymbolCategory.constructor && s.container == 'Dog',
        ),
        isTrue,
      );

      expect(sym('null:Color').category, SymbolCategory.enumSym);
      expect(sym('null:Color').signature, 'enum Color');
      expect(sym('Color:green').category, SymbolCategory.enumMember);
      expect(sym('Color:green').signature, 'Color.green');
    },
  );

  test('symbolFor prefers a member within its container', () async {
    final unit = await Analyzer().analyze('file:///s.dart', _src);
    expect(
      unit.symbolFor('age', container: 'Dog')?.category,
      SymbolCategory.field,
    );
    // Unknown name resolves to null.
    expect(unit.symbolFor('doesNotExist'), isNull);
  });
}
