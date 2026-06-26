// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

@Tags(['dart', 'kotlin', 'lua'])
library;

import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

/// Loads [source] in [language], runs an entry point and returns the captured
/// `print` output.
Future<List<Object?>> _run(
  String language,
  String source, {
  String function = 'main',
  String? className,
  List positionalParameters = const [],
}) async {
  var vm = ApolloVM();
  var codeUnit = SourceCodeUnit(language, source, id: 'test');

  var loaded = await vm.loadCodeUnit(codeUnit);
  expect(loaded, isTrue, reason: "Failed to load $language code");

  var runner = vm.createRunner(language)!;

  var output = <Object?>[];
  runner.externalPrintFunction = (o) => output.add(o);

  if (className != null) {
    await runner.executeClassMethod(
      '',
      className,
      function,
      positionalParameters: positionalParameters,
    );
  } else {
    await runner.executeFunction(
      '',
      function,
      positionalParameters: positionalParameters,
    );
  }

  return output;
}

/// Loads [source] in [language] and returns the value of calling [function].
Future<ASTValue> _call(
  String language,
  String source,
  String function, {
  List positionalParameters = const [],
}) async {
  var vm = ApolloVM();
  await vm.loadCodeUnit(SourceCodeUnit(language, source, id: 'test'));
  var runner = vm.createRunner(language)!;
  return runner.executeFunction(
    '',
    function,
    positionalParameters: positionalParameters,
  );
}

/// Loads [source] in [language] and translates it to [targetLanguage] source.
Future<String> _translate(
  String language,
  String source,
  String targetLanguage,
) async {
  var vm = ApolloVM();
  await vm.loadCodeUnit(SourceCodeUnit(language, source, id: 'test'));
  var storage = vm.generateAllCodeIn(targetLanguage);
  return (await storage.writeAllSources()).toString();
}

/// Extracts the raw source of the single generated code unit from the
/// ApolloVM "sources" envelope produced by `writeAllSources`.
String _extractCodeUnit(String allSources) {
  var lines = allSources.split('\n');
  var start = lines.indexWhere((l) => l.startsWith('<<<< CODE_UNIT_START'));
  var end = lines.indexWhere((l) => l.startsWith('<<<< CODE_UNIT_END'));
  return lines.sublist(start + 1, end).join('\n');
}

/// A Lua program that is parsed, executed, and translated+re-executed in every
/// [translateTargets] language, asserting identical observable output.
class _LuaCase {
  final String name;
  final String source;
  final List<Object?> expectedOutput;
  final String? className;
  final List<String> translateTargets;

  const _LuaCase(
    this.name,
    this.source,
    this.expectedOutput, {
    this.className,
    this.translateTargets = const ['dart', 'lua'],
  });
}

// Portable programs: only use constructs whose semantics are identical across
// Lua, Dart, Java and Kotlin, so the translated source must produce exactly the
// same output. String concatenation uses `..`; logical operators are
// `and`/`or`/`not`.
const _portableCases = <_LuaCase>[
  _LuaCase(
    'control flow: if / elseif / logic',
    r'''
function classify(n)
  if n < 0 then
    return "neg"
  elseif n == 0 then
    return "zero"
  else
    return "pos"
  end
end

function main()
  print(classify(-3))
  print(classify(0))
  print(classify(8))
  local t = true
  local f = false
  print(t and f)
  print(t or f)
  print(not t)
end
''',
    ['neg', 'zero', 'pos', false, true, false],
  ),
  _LuaCase(
    'loops: while + generic-for over list',
    r'''
function main()
  local sum = 0
  local i = 1
  while i <= 5 do
    sum = sum + i
    i = i + 1
  end
  print("sum=" .. sum)

  local items = {10, 20, 30}
  local total = 0
  for _, x in ipairs(items) do
    total = total + x
  end
  print("total=" .. total)
end
''',
    ['sum=15', 'total=60'],
  ),
  _LuaCase(
    'strings: concatenation',
    r'''
function greet(name)
  return "Hello, " .. name .. "!"
end

function main()
  local who = "Lua"
  print(greet(who))
  local x = 42
  print("x is " .. x .. " and doubled is " .. (x * 2))
end
''',
    ['Hello, Lua!', 'x is 42 and doubled is 84'],
  ),
  _LuaCase(
    'recursion: factorial',
    r'''
function fact(n)
  if n <= 1 then
    return 1
  end
  return n * fact(n - 1)
end

function main()
  print("fact5=" .. fact(5))
end
''',
    ['fact5=120'],
  ),
  _LuaCase(
    'numeric for loop',
    r'''
function main()
  local sum = 0
  for i = 1, 5 do
    sum = sum + i
  end
  print("sum=" .. sum)
end
''',
    ['sum=15'],
  ),
  _LuaCase(
    'class: methods + nested self calls',
    r'''
Calc = {}
Calc.__index = Calc

function Calc:square(n)
  return n * n
end

function Calc:cube(n)
  return n * self:square(n)
end

function Calc:main()
  print("square=" .. self:square(9))
  print("cube=" .. self:cube(3))
end
''',
    ['square=81', 'cube=27'],
    className: 'Calc',
    translateTargets: ['dart', 'lua', 'kotlin'],
  ),
  _LuaCase(
    'class: field read in method',
    r'''
Greeter = { name = "World" }
Greeter.__index = Greeter

function Greeter:main()
  print("Hello " .. self.name)
end
''',
    ['Hello World'],
    className: 'Greeter',
    translateTargets: ['dart', 'lua', 'kotlin'],
  ),
];

void main() {
  group('Lua parse + execute', () {
    for (var c in _portableCases) {
      test(c.name, () async {
        var output = await _run('lua', c.source, className: c.className);
        expect(output, equals(c.expectedOutput));
      });
    }

    test('arithmetic operators (VM int/double semantics)', () async {
      var output = await _run('lua', r'''
function main()
  local a = 7
  local b = 3
  print("add=" .. (a + b))
  print("sub=" .. (a - b))
  print("mul=" .. (a * b))
  print("div=" .. (a / b))
  print("mod=" .. (a % b))
  print("dbl=" .. (7.0 / 2.0))
end
''');
      expect(
        output,
        equals(['add=10', 'sub=4', 'mul=21', 'div=2', 'mod=1', 'dbl=3.5']),
      );
    });

    test('unary minus and logical negation', () async {
      var output = await _run('lua', r'''
function main()
  local a = -5
  print("neg=" .. (-a))
  local b = true
  print(not b)
end
''');
      expect(output, equals(['neg=5', false]));
    });

    test('single-quoted and escaped strings', () async {
      var output = await _run('lua', r'''
function main()
  local a = 'single'
  print(a .. "/" .. "tab\tend")
end
''');
      expect(output, equals(['single/tab\tend']));
    });

    test('function return value (number)', () async {
      var ret = await _call(
        'lua',
        r'''
function fact(n)
  if n <= 1 then
    return 1
  end
  return n * fact(n - 1)
end
''',
        'fact',
        positionalParameters: [5],
      );

      expect(ret.getValueNoContext(), equals(120));
    });

    test('function return value (string)', () async {
      var ret = await _call(
        'lua',
        r'''
function greet(name)
  return "Hi " .. name
end
''',
        'greet',
        positionalParameters: ['Lua'],
      );

      expect(ret.getValueNoContext(), equals('Hi Lua'));
    });
  });

  group('Lua translate + re-execute', () {
    for (var c in _portableCases) {
      for (var target in c.translateTargets) {
        test('${c.name} -> $target', () async {
          var generated = await _translate('lua', c.source, target);
          var code = _extractCodeUnit(generated);

          var output = await _run(target, code, className: c.className);
          expect(
            output,
            equals(c.expectedOutput),
            reason: 'Translated $target output mismatch',
          );
        });
      }
    }

    test('Lua -> Lua round-trip emits idiomatic Lua', () async {
      var lua = await _translate(
        'lua',
        _portableCases[3].source, // recursion
        'lua',
      );
      expect(lua, contains('function fact(n)'));
      expect(lua, contains('return n * fact(n - 1)'));
      expect(lua, contains('fact(5)'));
      expect(lua, contains(' .. '));
    });

    test('Lua -> Dart emits idiomatic Dart', () async {
      var dart = await _translate('lua', _portableCases[3].source, 'dart');
      expect(dart, contains('fact('));
      expect(dart, contains('return n * fact(n - 1);'));
    });

    test('Lua class -> Lua emits table-based class', () async {
      var lua = await _translate('lua', _portableCases[5].source, 'lua');
      expect(lua, contains('Calc = {}'));
      expect(lua, contains('Calc.__index = Calc'));
      expect(lua, contains('function Calc:square(n)'));
      expect(lua, contains('self:square(9)'));
    });

    test('Lua class -> Kotlin emits a class with methods', () async {
      var kotlin = await _translate('lua', _portableCases[5].source, 'kotlin');
      expect(kotlin, contains('class Calc'));
      expect(kotlin, contains('fun square'));
    });
  });

  // The table-based class convention is bidirectional: a class written in
  // another language translates to idiomatic Lua and re-executes identically.
  group('Lua cross-language classes', () {
    const kotlinClass = r'''
class Calc {
  fun square(n: Int): Int {
    return n * n
  }
  fun cube(n: Int): Int {
    return n * square(n)
  }
  fun main() {
    println("square=" + square(9))
    println("cube=" + cube(3))
  }
}
''';

    test('Kotlin class -> Lua emits table-based class', () async {
      var lua = await _translate('kotlin', kotlinClass, 'lua');
      expect(lua, contains('Calc = {}'));
      expect(lua, contains('Calc.__index = Calc'));
      expect(lua, contains('function Calc:square(n)'));
      expect(lua, contains('function Calc:cube(n)'));
      expect(lua, contains('self:square(9)'));
    });

    test('Kotlin class -> Lua re-executes', () async {
      var lua = await _translate('kotlin', kotlinClass, 'lua');
      var code = _extractCodeUnit(lua);
      var output = await _run('lua', code, className: 'Calc');
      expect(output, equals(['square=81', 'cube=27']));
    });
  });

  // Map literals parse and translate; runtime map support is a separate,
  // pre-existing VM concern, so these only assert parsing + code generation.
  group('Lua tables (parse + translate)', () {
    const mapSource = r'''
function build()
  return { ["a"] = 1, ["b"] = 2 }
end
''';

    test('translate map literal -> Dart', () async {
      var dart = await _translate('lua', mapSource, 'dart');
      expect(dart, contains('build()'));
      expect(dart, contains("'a': 1"));
      expect(dart, contains("'b': 2"));
    });

    test('translate map literal -> Lua', () async {
      var lua = await _translate('lua', mapSource, 'lua');
      expect(lua, contains('["a"] = 1'));
      expect(lua, contains('["b"] = 2'));
    });
  });

  group('Lua language features', () {
    test('numeric for with explicit step', () async {
      var output = await _run('lua', r'''
function main()
  local s = 0
  for i = 1, 10, 2 do
    s = s + i
  end
  print(s)
end
''');
      expect(output, equals([25]));
    });

    test('operator precedence and grouping', () async {
      var output = await _run('lua', r'''
function main()
  print(2 + 3 * 4)
  print((2 + 3) * 4)
  print(20 - 4 - 3)
end
''');
      expect(output, equals([14, 20, 13]));
    });

    test('comparison operators', () async {
      var output = await _run('lua', r'''
function main()
  print(3 > 2)
  print(3 < 2)
  print(3 >= 3)
  print(2 <= 1)
  print(3 ~= 4)
  print(3 == 3)
end
''');
      expect(output, equals([true, false, true, false, true, true]));
    });

    test('line and block comments are ignored', () async {
      var output = await _run('lua', r'''
-- a leading line comment
function main()
  --[[ a block
       comment ]]
  local x = 5 -- a trailing comment
  print(x)
end
''');
      expect(output, equals([5]));
    });

    test('identifiers may start with reserved-word prefixes', () async {
      var output = await _run('lua', r'''
function main()
  local index = 1
  local android = 2
  local endValue = 3
  print(index + android + endValue)
end
''');
      expect(output, equals([6]));
    });

    test('long bracket string literal', () async {
      var output = await _run('lua', r'''
function main()
  local s = [[hello
world]]
  print(s)
end
''');
      expect(output, equals(['hello\nworld']));
    });

    test('nested if / elseif chain', () async {
      var output = await _run('lua', r'''
function fizzbuzz(n)
  if n % 15 == 0 then
    return "fizzbuzz"
  elseif n % 3 == 0 then
    return "fizz"
  elseif n % 5 == 0 then
    return "buzz"
  else
    return "" .. n
  end
end

function main()
  print(fizzbuzz(15))
  print(fizzbuzz(9))
  print(fizzbuzz(10))
  print(fizzbuzz(7))
end
''');
      expect(output, equals(['fizzbuzz', 'fizz', 'buzz', '7']));
    });

    test('mutual recursion across top-level functions', () async {
      var output = await _run('lua', r'''
function isEven(n)
  if n == 0 then
    return true
  end
  return isOdd(n - 1)
end

function isOdd(n)
  if n == 0 then
    return false
  end
  return isEven(n - 1)
end

function main()
  print(isEven(10))
  print(isOdd(7))
end
''');
      expect(output, equals([true, true]));
    });

    test('nil literal and equality', () async {
      var output = await _run('lua', r'''
function main()
  local x = nil
  if x == nil then
    print("is nil")
  end
end
''');
      expect(output, equals(['is nil']));
    });

    test('nested loops over lists', () async {
      var output = await _run('lua', r'''
function main()
  local items = {1, 2, 3}
  local more = {10, 20}
  local total = 0
  for _, a in ipairs(items) do
    for _, b in ipairs(more) do
      total = total + a * b
    end
  end
  print(total)
end
''');
      expect(output, equals([180]));
    });

    test('local function declaration', () async {
      var output = await _run('lua', r'''
local function double(n)
  return n * 2
end

function main()
  print(double(21))
end
''');
      expect(output, equals([42]));
    });

    test('class with multiple fields', () async {
      var output = await _run('lua', r'''
Point = { x = 3, y = 4 }
Point.__index = Point

function Point:sum()
  return self.x + self.y
end

function Point:main()
  print("sum=" .. self:sum())
end
''', className: 'Point');
      expect(output, equals(['sum=7']));
    });
  });

  group('Lua more translations', () {
    test('numeric for -> Dart re-executes', () async {
      const src = r'''
function main()
  local s = 0
  for i = 1, 10, 2 do
    s = s + i
  end
  print(s)
end
''';
      var dart = _extractCodeUnit(await _translate('lua', src, 'dart'));
      expect(await _run('dart', dart), equals([25]));
    });

    test('nested if/elseif -> Lua round-trips and re-executes', () async {
      const src = r'''
function classify(n)
  if n < 0 then
    return "neg"
  elseif n == 0 then
    return "zero"
  else
    return "pos"
  end
end

function main()
  print(classify(-1))
  print(classify(0))
  print(classify(1))
end
''';
      var lua = await _translate('lua', src, 'lua');
      expect(lua, contains('elseif'));
      expect(lua, contains('end'));
      var code = _extractCodeUnit(lua);
      expect(await _run('lua', code), equals(['neg', 'zero', 'pos']));
    });

    test('multi-field class -> Dart re-executes', () async {
      const src = r'''
Point = { x = 3, y = 4 }
Point.__index = Point

function Point:sum()
  return self.x + self.y
end

function Point:main()
  print("sum=" .. self:sum())
end
''';
      var dart = _extractCodeUnit(await _translate('lua', src, 'dart'));
      expect(await _run('dart', dart, className: 'Point'), equals(['sum=7']));
    });
  });
}
