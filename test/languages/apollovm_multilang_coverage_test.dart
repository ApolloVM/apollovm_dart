// Copyright © 2020 Graciliano M. P. All rights reserved.
// This code is governed by the Apache License, Version 2.0.
// Please refer to the LICENSE and AUTHORS files for details.

@TestOn('vm')
@Tags([
  'java',
  'csharp',
  'go',
  'kotlin',
  'python',
  'lua',
  'javascript',
  'typescript',
])
library;

import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

/// Loads [source] in [language] and calls a top-level [function], returning the
/// resulting [ASTValue].
Future<ASTValue> _call(
  String language,
  String source,
  String function, {
  List positionalParameters = const [],
}) async {
  var vm = ApolloVM();
  var loaded = await vm.loadCodeUnit(
    SourceCodeUnit(language, source, id: 'test'),
  );
  expect(loaded, isTrue, reason: 'Failed to load $language code');
  var runner = vm.createRunner(language)!;
  return runner.executeFunction(
    '',
    function,
    positionalParameters: positionalParameters,
  );
}

/// Loads [source] in [language] and calls [className].[method], returning the
/// resulting [ASTValue]. Works for `static` methods and (field-less) instance
/// methods alike.
Future<ASTValue> _callMethod(
  String language,
  String source,
  String className,
  String method, {
  List positionalParameters = const [],
}) async {
  var vm = ApolloVM();
  var loaded = await vm.loadCodeUnit(
    SourceCodeUnit(language, source, id: 'test'),
  );
  expect(loaded, isTrue, reason: 'Failed to load $language code');
  var runner = vm.createRunner(language)!;
  return runner.executeClassMethod(
    '',
    className,
    method,
    positionalParameters: positionalParameters,
    classInstanceFields: const {},
  );
}

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
  var loaded = await vm.loadCodeUnit(
    SourceCodeUnit(language, source, id: 'test'),
  );
  expect(loaded, isTrue, reason: 'Failed to load $language code');
  var runner = vm.createRunner(language)!;

  var output = <Object?>[];
  runner.externalPrintFunction = output.add;

  if (className != null) {
    await runner.executeClassMethod(
      '',
      className,
      function,
      positionalParameters: positionalParameters,
      classInstanceFields: const {},
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

void main() {
  group('Java 11', () {
    test('static arithmetic method returns int', () async {
      var r = await _callMethod(
        'java11',
        r'''
class M {
  static int calc(int a, int b) {
    return (a + b) * 2 - a % b;
  }
}
''',
        'M',
        'calc',
        positionalParameters: [7, 3],
      );
      expect(r.getValueNoContext(), equals(19));
    });

    test('control flow: for / continue / break / do-while / switch', () async {
      var r = await _callMethod(
        'java11',
        r'''
class C {
  static int run(){
    int sum = 0;
    for (int i = 0; i < 10; i++) {
      if (i == 2) { continue; }
      if (i == 5) { break; }
      sum = sum + i;
    }
    int j = 0;
    do {
      sum = sum + 10;
      j++;
    } while (j < 3);
    switch (j) {
      case 3: { sum = sum + 100; break; }
      default: { sum = sum + 1; break; }
    }
    return sum;
  }
}
''',
        'C',
        'run',
      );
      expect(r.getValueNoContext(), equals(138));
    });

    test('recursion: factorial (static)', () async {
      var r = await _callMethod(
        'java11',
        r'''
class M {
  static int fact(int n) {
    if (n <= 1) { return 1; }
    return n * fact(n - 1);
  }
}
''',
        'M',
        'fact',
        positionalParameters: [5],
      );
      expect(r.getValueNoContext(), equals(120));
    });

    test('bitwise operators', () async {
      var r = await _callMethod(
        'java11',
        r'''
class M {
  static int f(int a, int b) {
    return ((a & b) | (a ^ b)) + (a << 1) + (a >> 1);
  }
}
''',
        'M',
        'f',
        positionalParameters: [6, 3],
      );
      expect(r.getValueNoContext(), equals(22));
    });

    test('this method + string concatenation prints', () async {
      var output = await _run(
        'java11',
        r'''
class Foo {
  int m10(int a) {
    return a * 10 ;
  }
  void test(int a) {
    var b = this.m10(a);
    var self = this ;
    var c = self.m10(b);
    var s = "a: "+ a +" ; b: "+ b +" ; c: "+ c ;
    print(s);
  }
}
''',
        function: 'test',
        className: 'Foo',
        positionalParameters: [123],
      );
      expect(output, equals(['a: 123 ; b: 1230 ; c: 12300']));
    });

    test('while loop accumulates', () async {
      var r = await _callMethod(
        'java11',
        r'''
class M {
  static int run(int n) {
    int i = 0;
    int total = 0;
    while (i < n) {
      total = total + i;
      i++;
    }
    return total;
  }
}
''',
        'M',
        'run',
        positionalParameters: [5],
      );
      expect(r.getValueNoContext(), equals(10));
    });

    test('pre-increment and decrement in for', () async {
      var r = await _callMethod(
        'java11',
        r'''
class M {
  static int run() {
    int total = 0;
    for (int i = 5; i > 0; --i) {
      total = total + i;
    }
    return total;
  }
}
''',
        'M',
        'run',
      );
      expect(r.getValueNoContext(), equals(15));
    });

    test('branches with logical operators print', () async {
      var output = await _run(
        'java11',
        r'''
class Foo {
  static void main(Object[] args) {
    var a = args[0];
    var b = args[1];
    var greater = a > b;
    if (greater && (a > 0)) {
      print("a > b");
    } else {
      print("a <= b");
    }
  }
}
''',
        function: 'main',
        className: 'Foo',
        positionalParameters: [
          [10, 3],
        ],
      );
      expect(output, equals(['a > b']));
    });
  });

  group('C#', () {
    test('static arithmetic method returns int', () async {
      var r = await _callMethod(
        'csharp',
        r'''
class M {
  static int calc(int a, int b) {
    return (a + b) * 2 - a % b;
  }
}
''',
        'M',
        'calc',
        positionalParameters: [7, 3],
      );
      expect(r.getValueNoContext(), equals(19));
    });

    test('control flow: for / continue / break / do-while / switch', () async {
      var r = await _callMethod(
        'csharp',
        r'''
class C {
  static int run(){
    int sum = 0;
    for (int i = 0; i < 10; i++) {
      if (i == 2) { continue; }
      if (i == 5) { break; }
      sum = sum + i;
    }
    int j = 0;
    do {
      sum = sum + 10;
      j++;
    } while (j < 3);
    switch (j) {
      case 3: { sum = sum + 100; break; }
      default: { sum = sum + 1; break; }
    }
    return sum;
  }
}
''',
        'C',
        'run',
      );
      expect(r.getValueNoContext(), equals(138));
    });

    test('foreach over a List', () async {
      var output = await _run(
        'csharp',
        r'''
class Foo {
  void test() {
    var list = new List<int>(){ 10, 20, 30 };
    int total = 0;
    foreach (int x in list) {
      total += x;
    }
    print(total);
  }
}
''',
        function: 'test',
        className: 'Foo',
      );
      expect(output, equals([60]));
    });

    test('while loop prints', () async {
      var output = await _run(
        'csharp',
        r'''
class Foo {
  void test(int n) {
    int i = 0;
    int total = 0;
    while (i < n) {
      total += i;
      i++;
    }
    print(total);
  }
}
''',
        function: 'test',
        className: 'Foo',
        positionalParameters: [4],
      );
      expect(output, equals([6]));
    });

    test('ternary conditional', () async {
      var output = await _run(
        'csharp',
        r'''
class Foo {
  void test(int a) {
    var s = a > 10 ? "big" : "small";
    print(s);
  }
}
''',
        function: 'test',
        className: 'Foo',
        positionalParameters: [3],
      );
      expect(output, equals(['small']));
    });

    test('bitwise operators', () async {
      var r = await _callMethod(
        'csharp',
        r'''
class M {
  static int f(int a, int b) {
    return ((a & b) | (a ^ b)) + (a << 1) + (a >> 1);
  }
}
''',
        'M',
        'f',
        positionalParameters: [6, 3],
      );
      expect(r.getValueNoContext(), equals(22));
    });

    test('this method + string concatenation prints', () async {
      var output = await _run(
        'csharp',
        r'''
class Foo {
  int m10(int a) {
    return a * 10 ;
  }
  void test(int a) {
    var b = this.m10(a);
    var self = this ;
    var c = self.m10(b);
    var s = "a: "+ a +" ; b: "+ b +" ; c: "+ c ;
    print(s);
  }
}
''',
        function: 'test',
        className: 'Foo',
        positionalParameters: [123],
      );
      expect(output, equals(['a: 123 ; b: 1230 ; c: 12300']));
    });

    test('recursion: factorial (static)', () async {
      var r = await _callMethod(
        'csharp',
        r'''
class M {
  static int fact(int n) {
    if (n <= 1) { return 1; }
    return n * fact(n - 1);
  }
}
''',
        'M',
        'fact',
        positionalParameters: [6],
      );
      expect(r.getValueNoContext(), equals(720));
    });
  });

  group('Python', () {
    test('top-level def returns sum', () async {
      var r = await _call(
        'python',
        'def add(a, b):\n    return a + b\n',
        'add',
        positionalParameters: [4, 6],
      );
      expect(r.getValueNoContext(), equals(10));
    });

    test('if / elif / else classify', () async {
      var output = await _run(
        'python',
        r'''
def classify(n):
    if n > 0:
        return 'positive'
    elif n < 0:
        return 'negative'
    else:
        return 'zero'

def main(n):
    print(classify(n))
''',
        function: 'main',
        positionalParameters: [-5],
      );
      expect(output, equals(['negative']));
    });

    test('while with break/continue + match', () async {
      var r = await _call('python', r'''
def run():
    total = 0
    i = 0
    while i < 10:
        i = i + 1
        if i == 3:
            continue
        if i == 6:
            break
        total = total + i
    match i:
        case 6:
            total = total + 100
        case _:
            total = total + 1
    return total
''', 'run');
      expect(r.getValueNoContext(), equals(112));
    });

    test('for-each over list + dict/list indexing', () async {
      var output = await _run(
        'python',
        r'''
def main(items):
    total = 0
    for x in items:
        total += x
    print(total)
    d = {'a': 1, 'b': 2}
    print(d['a'])
    nums = [10, 20, 30]
    print(nums[1])
''',
        function: 'main',
        positionalParameters: [
          [1, 2, 3],
        ],
      );
      expect(output, equals([6, 1, 20]));
    });

    test('ternary conditional expression', () async {
      var r = await _call(
        'python',
        "def classify(a):\n    return 1 if a > 0 else -1\n",
        'classify',
        positionalParameters: [5],
      );
      expect(r.getValueNoContext(), equals(1));
    });

    test('class with self method + f-string prints', () async {
      var output = await _run(
        'python',
        r'''
class Foo:
    def m10(self, a):
        return a * 10

    def test(self, a):
        b = self.m10(a)
        c = self.m10(b)
        s = f'a: {a} ; b: {b} ; c: {c}'
        print(s)
''',
        function: 'test',
        className: 'Foo',
        positionalParameters: [123],
      );
      expect(output, equals(['a: 123 ; b: 1230 ; c: 12300']));
    });

    test('recursion: factorial', () async {
      var r = await _call(
        'python',
        r'''
def fact(n):
    if n <= 1:
        return 1
    return n * fact(n - 1)
''',
        'fact',
        positionalParameters: [5],
      );
      expect(r.getValueNoContext(), equals(120));
    });
  });

  group('JavaScript', () {
    test('class for loop prints', () async {
      var output = await _run(
        'javascript',
        r'''
class M {
  run(n) {
    let total = 0;
    for (let i = 0; i < n; ++i) {
      total += i;
    }
    print(total);
  }
}
''',
        function: 'run',
        className: 'M',
        positionalParameters: [5],
      );
      expect(output, equals([10]));
    });

    test('class for-of over an array', () async {
      var output = await _run(
        'javascript',
        r'''
class Bar {
  sum(items) {
    let total = 0;
    for (const x of items) {
      total += x;
    }
    print(total);
  }
}
''',
        function: 'sum',
        className: 'Bar',
        positionalParameters: [
          [10, 20, 30],
        ],
      );
      expect(output, equals([60]));
    });

    test('class while loop prints', () async {
      var output = await _run(
        'javascript',
        r'''
class M {
  run(n) {
    let i = 0;
    let total = 0;
    while (i < n) {
      total += i;
      i += 1;
    }
    print(total);
  }
}
''',
        function: 'run',
        className: 'M',
        positionalParameters: [5],
      );
      expect(output, equals([10]));
    });

    test('top-level arrow function executes', () async {
      var output = await _run(
        'javascript',
        r'''
const show = (a, b) => {
  print(a + b);
};
''',
        function: 'show',
        positionalParameters: [10, 32],
      );
      expect(output, equals([42]));
    });

    test('template literal with this', () async {
      var output = await _run(
        'javascript',
        r'''
class Foo {
  test(a) {
    let s = `${this} > a: ${a}`;
    print(s);
  }
}
''',
        function: 'test',
        className: 'Foo',
        positionalParameters: [123],
      );
      expect(output, equals(['Foo{} > a: 123']));
    });
  });

  group('TypeScript', () {
    test('top-level typed function returns number', () async {
      var r = await _call(
        'typescript',
        r'''
function sum(a: number, b: number): number {
  return a + b;
}
''',
        'sum',
        positionalParameters: [4, 6],
      );
      expect(r.getValueNoContext(), equals(10));
    });

    test('typed class for loop returns number', () async {
      var r = await _callMethod(
        'typescript',
        r'''
class M {
  run(n: number): number {
    let total: number = 0;
    for (let i: number = 0; i < n; i++) {
      total = total + i;
    }
    return total;
  }
}
''',
        'M',
        'run',
        positionalParameters: [5],
      );
      expect(r.getValueNoContext(), equals(10));
    });

    test('typed for-of prints each item', () async {
      var output = await _run(
        'typescript',
        r'''
class M {
  run(items: string[]): void {
    for (const it of items) {
      print(it);
    }
  }
}
''',
        function: 'run',
        className: 'M',
        positionalParameters: [
          ['a', 'b', 'c'],
        ],
      );
      expect(output, equals(['a', 'b', 'c']));
    });

    test('typed while loop returns number', () async {
      var r = await _callMethod(
        'typescript',
        r'''
class M {
  run(n: number): number {
    let i: number = 0;
    let total: number = 0;
    while (i < n) {
      total = total + i;
      i++;
    }
    return total;
  }
}
''',
        'M',
        'run',
        positionalParameters: [5],
      );
      expect(r.getValueNoContext(), equals(10));
    });

    test('typed class method with template literal', () async {
      var output = await _run(
        'typescript',
        r'''
class Foo {
  test(a: number): void {
    let s: string = `a: ${a}`;
    print(s);
  }
}
''',
        function: 'test',
        className: 'Foo',
        positionalParameters: [123],
      );
      expect(output, equals(['a: 123']));
    });
  });

  group('Go', () {
    test('top-level func returns int', () async {
      var r = await _call(
        'go',
        r'''
func add(a int, b int) int {
  return a + b
}
''',
        'add',
        positionalParameters: [4, 6],
      );
      expect(r.getValueNoContext(), equals(10));
    });

    test('c-style for loop', () async {
      var r = await _call(
        'go',
        r'''
func run(n int) int {
  total := 0
  for i := 0; i < n; i = i + 1 {
    total = total + i
  }
  return total
}
''',
        'run',
        positionalParameters: [5],
      );
      expect(r.getValueNoContext(), equals(10));
    });

    test('switch without fall-through', () async {
      var r = await _call(
        'go',
        r'''
func f(x int) int {
  r := 0
  switch x {
  case 1:
    r = 10
  case 2:
    r = 20
  default:
    r = 99
  }
  return r
}
''',
        'f',
        positionalParameters: [2],
      );
      expect(r.getValueNoContext(), equals(20));
    });

    test('closure captured and invoked', () async {
      var r = await _call(
        'go',
        r'''
func f(a int) int {
  double := func(x int) int {
    return x * 2
  }
  return double(a) + 1
}
''',
        'f',
        positionalParameters: [20],
      );
      expect(r.getValueNoContext(), equals(41));
    });

    test('for-range over slice prints', () async {
      var output = await _run('go', r'''
func run() {
  items := []int{10, 20, 30}
  total := 0
  for _, x := range items {
    total = total + x
  }
  fmt.Println("total=" + total)
}
''', function: 'run');
      expect(output, equals(['total=60']));
    });
  });

  group('Kotlin', () {
    test('recursion: factorial returns int', () async {
      var r = await _call(
        'kotlin',
        r'''
fun fact(n: Int): Int {
  if (n <= 1) {
    return 1
  }
  return n * fact(n - 1)
}
''',
        'fact',
        positionalParameters: [5],
      );
      expect(r.getValueNoContext(), equals(120));
    });

    test('while + for-in over list prints', () async {
      var output = await _run('kotlin', r'''
fun main() {
  var sum = 0
  var i = 1
  while (i <= 5) {
    sum += i
    i += 1
  }
  println("sum=$sum")
  val items = mutableListOf(10, 20, 30)
  var total = 0
  for (x in items) {
    total += x
  }
  println("total=$total")
}
''');
      expect(output, equals(['sum=15', 'total=60']));
    });

    test('arithmetic + string templates prints', () async {
      var output = await _run('kotlin', r'''
fun main() {
  val a = 7
  val b = 3
  println("add=${a + b}")
  println("mul=${a * b}")
  println("mod=${a % b}")
}
''');
      expect(output, equals(['add=10', 'mul=21', 'mod=1']));
    });

    test('class method + nested call returns int', () async {
      var r = await _callMethod(
        'kotlin',
        r'''
class Calc {
  fun square(n: Int): Int {
    return n * n
  }
  fun cube(n: Int): Int {
    return n * square(n)
  }
}
''',
        'Calc',
        'cube',
        positionalParameters: [3],
      );
      expect(r.getValueNoContext(), equals(27));
    });
  });

  group('Lua', () {
    test('recursion: factorial returns number', () async {
      var r = await _call(
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
      expect(r.getValueNoContext(), equals(120));
    });

    test('numeric for with step prints', () async {
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

    test('while + generic-for over list prints', () async {
      var output = await _run('lua', r'''
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
''');
      expect(output, equals(['sum=15', 'total=60']));
    });

    test('if / elseif / else + logical operators prints', () async {
      var output = await _run('lua', r'''
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
  print(not true)
end
''');
      expect(output, equals(['neg', 'zero', 'pos', false]));
    });

    test('table-based class method returns number', () async {
      var r = await _callMethod(
        'lua',
        r'''
Calc = {}
Calc.__index = Calc

function Calc:square(n)
  return n * n
end

function Calc:cube(n)
  return n * self:square(n)
end
''',
        'Calc',
        'cube',
        positionalParameters: [3],
      );
      expect(r.getValueNoContext(), equals(27));
    });
  });
}
