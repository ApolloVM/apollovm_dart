import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

void main() {
  group('Dart', () {
    test('Basic main(List<Object>)', () async {
      var vm = ApolloVM();

      var codeUnit = CodeUnit(
          'dart',
          r'''
            void main(List<Object> args) {
              var title = args[0];
              var a = args[1];
              var b = args[2];
              var c = args[3];
              var sumAB = a + b ;
              var sumABC = a + b + c;
              var greater = sumABC > sumAB ;
              print(title);
              print(sumAB);
              print(sumABC);
              if ( greater ) {
                var eq = greater == true ;
                print('sumABC > sumAB = $eq');
              }
            }
          ''',
          'test');

      var loadOK = await vm.loadCodeUnit(codeUnit);

      expect(loadOK, isTrue, reason: 'Error loading Dart code!');

      var dartRunner = vm.createRunner('dart')!;

      var output = [];
      dartRunner.externalPrintFunction = (o) => output.add(o);

      await dartRunner.executeFunction('', 'main', [
        ['Sums:', 10, 20, 50]
      ]);

      expect(output, equals(['Sums:', 30, 80, 'sumABC > sumAB = true']));

      print('---------------------------------------');
      print('OUTPUT:');
      output.forEach((o) => print('>> $o'));

      print('---------------------------------------');
      // Regenerate code:
      var codeStorageDart = vm.generateAllCodeIn('dart');
      var allSourcesDart = codeStorageDart.writeAllSources().toString();
      print(allSourcesDart);

      expect(allSourcesDart, equals(r'''<<<< [SOURCES_BEGIN] >>>>
<<<< NAMESPACE="" >>>>
<<<< CODE_UNIT_START="/test" >>>>
  void main(List<Object> args) {
    var title = args[0];
    var a = args[1];
    var b = args[2];
    var c = args[3];
    var sumAB = a + b;
    var sumABC = a + b + c;
    var greater = sumABC > sumAB;
    print(title);
    print(sumAB);
    print(sumABC);
    if (greater) {
        var eq = greater == true;
        print('sumABC > sumAB = $eq');
    }

  }

<<<< CODE_UNIT_END="/test" >>>>
<<<< [SOURCES_END] >>>>
'''));
    });

    test('Basic main(List<Object>) with division', () async {
      var vm = ApolloVM();

      var codeUnit = CodeUnit(
          'dart',
          r'''
          
          void main(List<Object> args) {
            var title = args[0];
            var a = args[1];
            var b = args[2] ~/ 2;
            var c = args[3] * 3;
            
            if (c > 120) {
              c = 120 ;
            }
            
            var str = 'variables> a: $a ; b: $b ; c: $c' ;
            var sumAB = a + b ;
            var sumABC = a + b + c;
            
            print(str);
            print(title);
            print(sumAB);
            print(sumABC);
          }
          
          ''',
          'test');

      var loadOK = await vm.loadCodeUnit(codeUnit);

      expect(loadOK, isTrue, reason: 'Error loading Dart code!');

      var dartRunner = vm.createRunner('dart')!;

      var output = [];
      dartRunner.externalPrintFunction = (o) => output.add(o);

      await dartRunner.executeFunction('', 'main', [
        ['Sums:', 10, 30, 50]
      ]);

      expect(output,
          equals(['variables> a: 10 ; b: 15 ; c: 120', 'Sums:', 25, 145]));

      print('---------------------------------------');
      print('OUTPUT:');
      output.forEach((o) => print('>> $o'));

      print('---------------------------------------');
      // Regenerate code:
      var codeStorageDart = vm.generateAllCodeIn('dart');
      var allSourcesDart = codeStorageDart.writeAllSources().toString();
      print(allSourcesDart);

      expect(allSourcesDart, equals(r'''<<<< [SOURCES_BEGIN] >>>>
<<<< NAMESPACE="" >>>>
<<<< CODE_UNIT_START="/test" >>>>
  void main(List<Object> args) {
    var title = args[0];
    var a = args[1];
    var b = args[2] ~/ 2;
    var c = args[3] * 3;
    if (c > 120) {
        c = 120;
    }

    var str = 'variables> a: $a ; b: $b ; c: $c';
    var sumAB = a + b;
    var sumABC = a + b + c;
    print(str);
    print(title);
    print(sumAB);
    print(sumABC);
  }

<<<< CODE_UNIT_END="/test" >>>>
<<<< [SOURCES_END] >>>>
'''));
    });

    test('Basic main(List<String>)', () async {
      var vm = ApolloVM();

      var codeUnit = CodeUnit(
          'dart',
          r'''
            void main(List<String> args) {
              var title = args[0];
              var a = args[1];
              var b = args[2];
              var c = args[3];
              var sumAB = a + b ;
              var sumABC = a + b + c;
              print(title);
              print(sumAB);
              print(sumABC);
            }
          ''',
          'test');

      var loadOK = await vm.loadCodeUnit(codeUnit);

      expect(loadOK, isTrue, reason: 'Error loading Dart code!');

      var dartRunner = vm.createRunner('dart')!;

      var output = [];
      dartRunner.externalPrintFunction = (o) => output.add(o);

      await dartRunner.executeFunction('', 'main', [
        ['Strings:', 'A', 'B', 'C']
      ]);

      expect(output, equals(['Strings:', 'AB', 'ABC']));

      print('---------------------------------------');
      print('OUTPUT:');
      output.forEach((o) => print('>> $o'));

      print('---------------------------------------');
      // Regenerate code:
      var codeStorageDart = vm.generateAllCodeIn('dart');
      var allSourcesDart = codeStorageDart.writeAllSources().toString();
      print(allSourcesDart);

      expect(
          allSourcesDart,
          matches(RegExp(r'\s*'
              r'void\s+main\(List<String> args\)\s*\{'
              r'\s*var\s+title\s+=\s+args\[0\]\s*;'
              r'\s*var\s+a\s+=\s+args\[1\]\s*;'
              r'\s*var\s+b\s+=\s+args\[2\]\s*;'
              r'\s*var\s+c\s+=\s+args\[3\]\s*;'
              r'\s*var\s+sumAB\s+=\s+a\s*\+\s*b\s*;'
              r'\s*var\s+sumABC\s+=\s+a\s*\+\s*b\s*\+\s*c\s*;'
              r'\s*print\(title\)\s*;'
              r'\s*print\(sumAB\)\s*;'
              r'\s*print\(sumABC\)\s*;'
              r'\s*\}\s*')));
    });

    test('Basic main(List<Object>) with inline String', () async {
      var vm = ApolloVM();

      var codeUnit = CodeUnit(
          'dart',
          r'''
            void main(List<Object> args) {
              var title = args[0];
              var a = args[1];
              var b = args[2];
              var s1 = 'inline';
              var s2 = r'string';
              var c = s1 + ' \t' +"\t " + s2 ;
              var sumAB = a + b ;
              var sumABC = a + b + c;
              print(title);
              print(sumAB);
              print(sumABC);
            }
          ''',
          'test');

      var loadOK = await vm.loadCodeUnit(codeUnit);

      expect(loadOK, isTrue, reason: 'Error loading Dart code!');

      var dartRunner = vm.createRunner('dart')!;

      var output = [];
      dartRunner.externalPrintFunction = (o) => output.add(o);

      await dartRunner.executeFunction('', 'main', [
        ['Operations:', 10, 20]
      ]);

      print('---------------------------------------');
      print('OUTPUT:');
      output.forEach((o) => print('>> $o'));

      expect(output, equals(['Operations:', 30, '1020inline \t\t string']));

      print('---------------------------------------');
      // Regenerate code:
      var codeStorageDart = vm.generateAllCodeIn('dart');
      var allSourcesDart = codeStorageDart.writeAllSources().toString();
      print(allSourcesDart);

      expect(allSourcesDart, equals(r'''<<<< [SOURCES_BEGIN] >>>>
<<<< NAMESPACE="" >>>>
<<<< CODE_UNIT_START="/test" >>>>
  void main(List<Object> args) {
    var title = args[0];
    var a = args[1];
    var b = args[2];
    var s1 = 'inline';
    var s2 = 'string';
    var c = '$s1 \t\t $s2';
    var sumAB = a + b;
    var sumABC = a + b + c;
    print(title);
    print(sumAB);
    print(sumABC);
  }

<<<< CODE_UNIT_END="/test" >>>>
<<<< [SOURCES_END] >>>>
'''));
    });

    test('Basic main(List<Object>) with multiline String', () async {
      var vm = ApolloVM();

      var codeUnit = CodeUnit(
          'dart',
          '''
            void main(List<Object> args) {
              var title = args[0];
              var a = args[1];
              var b = args[2];
              var l = \'''line1
line2
line3
\''';
              var s = a + '\\\\::' + l + b;
              print(title);
              print(s);
            }
          ''',
          'test');

      print(codeUnit.source);

      var loadOK = await vm.loadCodeUnit(codeUnit);

      expect(loadOK, isTrue, reason: 'Error loading Dart code!');

      var dartRunner = vm.createRunner('dart')!;

      var output = [];
      dartRunner.externalPrintFunction = (o) => output.add(o);

      await dartRunner.executeFunction('', 'main', [
        ['Multiline:', 10, 20]
      ]);

      print('---------------------------------------');
      print('OUTPUT:');
      output.forEach((o) => print('>> $o'));

      expect(output, equals(['Multiline:', '10\\::line1\nline2\nline3\n20']));

      print('---------------------------------------');
      // Regenerate code:
      var codeStorageDart = vm.generateAllCodeIn('dart');
      var allSourcesDart = codeStorageDart.writeAllSources().toString();
      print(allSourcesDart);

      expect(allSourcesDart, equals(r'''<<<< [SOURCES_BEGIN] >>>>
<<<< NAMESPACE="" >>>>
<<<< CODE_UNIT_START="/test" >>>>
  void main(List<Object> args) {
    var title = args[0];
    var a = args[1];
    var b = args[2];
    var l = 'line1\nline2\nline3\n';
    var s = a + r'\::' + l + b;
    print(title);
    print(s);
  }

<<<< CODE_UNIT_END="/test" >>>>
<<<< [SOURCES_END] >>>>
'''));
    });

    test('Basic main(List<String>) with raw strings', () async {
      var vm = ApolloVM();

      var codeUnit = CodeUnit(
          'dart',
          r'''
            void main(List<String> args) {
              var s1 = 'single \'quote\'';
              var s2 = "double \"quote\"";
              var r1 = r"single \'quote\'";
              var r2 = r'double \"quote\"'; 
              print(s1);
              print(s2);
              print(r1);
              print(r2);
            }
          ''',
          'test');

      var loadOK = await vm.loadCodeUnit(codeUnit);

      expect(loadOK, isTrue, reason: 'Error loading Dart code!');

      var dartRunner = vm.createRunner('dart')!;

      var output = [];
      dartRunner.externalPrintFunction = (o) => output.add(o);

      await dartRunner.executeFunction('', 'main', []);

      expect(
          output,
          equals([
            r"single 'quote'",
            r'double "quote"',
            r"single \'quote\'",
            r'double \"quote\"'
          ]));

      print('---------------------------------------');
      print('OUTPUT:');
      output.forEach((o) => print('>> $o'));

      print('---------------------------------------');
      // Regenerate code:
      var codeStorageDart = vm.generateAllCodeIn('dart');
      var allSourcesDart = codeStorageDart.writeAllSources().toString();
      print(allSourcesDart);

      expect(allSourcesDart, equals(r'''<<<< [SOURCES_BEGIN] >>>>
<<<< NAMESPACE="" >>>>
<<<< CODE_UNIT_START="/test" >>>>
  void main(List<String> args) {
    var s1 = "single 'quote'";
    var s2 = 'double "quote"';
    var r1 = r"single \'quote\'";
    var r2 = r'double \"quote\"';
    print(s1);
    print(s2);
    print(r1);
    print(r2);
  }

<<<< CODE_UNIT_END="/test" >>>>
<<<< [SOURCES_END] >>>>
'''));
    });

    test('Basic main(List<String>) with raw multiline strings', () async {
      var vm = ApolloVM();

      var codeUnit = CodeUnit(
          'dart',
          r"""
            void main(List<String> args) {
              var m1 = '''single \'quote\'''';
              var rm1 = r'''double \"quote\"''';"""
              r'''
              var m2 = """double \"quote\"""";
              var rm2 = r"""single \'quote\'""";
              print(m1);
              print(m2);
              print(rm1);
              print(rm2);
            }
          ''',
          'test');

      var loadOK = await vm.loadCodeUnit(codeUnit);

      expect(loadOK, isTrue, reason: 'Error loading Dart code!');

      var dartRunner = vm.createRunner('dart')!;

      var output = [];
      dartRunner.externalPrintFunction = (o) => output.add(o);

      await dartRunner.executeFunction('', 'main', []);

      expect(
          output,
          equals([
            "single \'quote\'",
            'double \"quote\"',
            r'double \"quote\"',
            r"single \'quote\'",
          ]));

      print('---------------------------------------');
      print('OUTPUT:');
      output.forEach((o) => print('>> $o'));

      print('---------------------------------------');
      // Regenerate code:
      var codeStorageDart = vm.generateAllCodeIn('dart');
      var allSourcesDart = codeStorageDart.writeAllSources().toString();
      print(allSourcesDart);

      expect(allSourcesDart, equals(r'''<<<< [SOURCES_BEGIN] >>>>
<<<< NAMESPACE="" >>>>
<<<< CODE_UNIT_START="/test" >>>>
  void main(List<String> args) {
    var m1 = "single 'quote'";
    var rm1 = r'double \"quote\"';
    var m2 = 'double "quote"';
    var rm2 = r"single \'quote\'";
    print(m1);
    print(m2);
    print(rm1);
    print(rm2);
  }

<<<< CODE_UNIT_END="/test" >>>>
<<<< [SOURCES_END] >>>>
'''));
    });

    test('Basic main(List<String>) with string variable', () async {
      var vm = ApolloVM();

      var codeUnit = CodeUnit(
          'dart',
          r"""
            class Foo {
              static void main(List<String> args) {
                var a = 123 ;
                var b = 123 * 2 ;
                var sv1 = 'a: <$a>;\t\$b->a*2: $b ;\ta*3: ${ a * 3 }!' ;
                print(sv1);
              }
            }
          """,
          'test');

      var loadOK = await vm.loadCodeUnit(codeUnit);

      expect(loadOK, isTrue, reason: 'Error loading Dart code!');

      var dartRunner = vm.createRunner('dart')!;

      var output = [];
      dartRunner.externalPrintFunction = (o) => output.add(o);

      await dartRunner.executeClassMethod('', 'Foo', 'main', []);

      expect(output, equals(['a: <123>;\t\$b->a*2: 246 ;\ta*3: 369!']));

      print('---------------------------------------');
      print('OUTPUT:');
      output.forEach((o) => print('>> $o'));

      print('---------------------------------------');
      // Regenerate code:
      var codeStorageDart = vm.generateAllCodeIn('dart');
      var allSourcesDart = codeStorageDart.writeAllSources().toString();
      print(allSourcesDart);

      expect(allSourcesDart, equals(r'''<<<< [SOURCES_BEGIN] >>>>
<<<< NAMESPACE="" >>>>
<<<< CODE_UNIT_START="/test" >>>>
class Foo {

  static void main(List<String> args) {
    var a = 123;
    var b = 123 * 2;
    var sv1 = 'a: <$a>;\t\$b->a*2: $b ;\ta*3: ${a * 3}!';
    print(sv1);
  }

}
<<<< CODE_UNIT_END="/test" >>>>
<<<< [SOURCES_END] >>>>
'''));

      print('---------------------------------------');
      // Regenerate code:
      var codeStorageJava = vm.generateAllCodeIn('java11');
      var allSourcesJava = codeStorageJava.writeAllSources().toString();
      print(allSourcesJava);

      expect(allSourcesJava, equals(r'''<<<< [SOURCES_BEGIN] >>>>
<<<< NAMESPACE="" >>>>
<<<< CODE_UNIT_START="/test" >>>>
class Foo {

  static void main(String[] args) {
    var a = 123;
    var b = 123 * 2;
    var sv1 = "a: <" + a + ">;\t$b->a*2: " + b + " ;\ta*3: " + String.valueOf( a * 3 ) + "!";
    print(sv1);
  }

}
<<<< CODE_UNIT_END="/test" >>>>
<<<< [SOURCES_END] >>>>
'''));
    });

    test('Basic main(List<String>) with comparisons', () async {
      var vm = ApolloVM();

      var codeUnit = CodeUnit(
          'dart',
          r'''
          class Bar {
            static void main(List<Object> args) {
              var a = args[0] ;
              var b = args[1] ;
              var eq = a == b ;
              var notEq = a != b ;
              var greater = a > b ;
              var lower = a < b ;
              var greaterOrEq = a >= b ;
              var lowerOrEq = a <= b ;
              print(eq);
              print(notEq);
              print(greater);
              print(lower);
              print(greaterOrEq);
              print(lowerOrEq);
            }
          }
          ''',
          'test');

      var loadOK = await vm.loadCodeUnit(codeUnit);

      expect(loadOK, isTrue, reason: 'Error loading Dart code!');

      var dartRunner = vm.createRunner('dart')!;

      var output = [];
      dartRunner.externalPrintFunction = (o) => output.add(o);

      await dartRunner.executeClassMethod('', 'Bar', 'main', [
        [10, 20]
      ]);

      expect(output, equals([false, true, false, true, false, true]));

      print('---------------------------------------');
      print('OUTPUT:');
      output.forEach((o) => print('>> $o'));

      print('---------------------------------------');
      // Regenerate code:
      var codeStorageDart = vm.generateAllCodeIn('dart');
      var allSourcesDart = codeStorageDart.writeAllSources().toString();
      print(allSourcesDart);

      expect(allSourcesDart, equals(r'''<<<< [SOURCES_BEGIN] >>>>
<<<< NAMESPACE="" >>>>
<<<< CODE_UNIT_START="/test" >>>>
class Bar {

  static void main(List<Object> args) {
    var a = args[0];
    var b = args[1];
    var eq = a == b;
    var notEq = a != b;
    var greater = a > b;
    var lower = a < b;
    var greaterOrEq = a >= b;
    var lowerOrEq = a <= b;
    print(eq);
    print(notEq);
    print(greater);
    print(lower);
    print(greaterOrEq);
    print(lowerOrEq);
  }

}
<<<< CODE_UNIT_END="/test" >>>>
<<<< [SOURCES_END] >>>>
'''));

      print('---------------------------------------');
      // Regenerate code:
      var codeStorageJava = vm.generateAllCodeIn('java11');
      var allSourcesJava = codeStorageJava.writeAllSources().toString();
      print(allSourcesJava);

      expect(allSourcesJava, equals(r'''<<<< [SOURCES_BEGIN] >>>>
<<<< NAMESPACE="" >>>>
<<<< CODE_UNIT_START="/test" >>>>
class Bar {

  static void main(Object[] args) {
    var a = args[0];
    var b = args[1];
    var eq = a == b;
    var notEq = a != b;
    var greater = a > b;
    var lower = a < b;
    var greaterOrEq = a >= b;
    var lowerOrEq = a <= b;
    print(eq);
    print(notEq);
    print(greater);
    print(lower);
    print(greaterOrEq);
    print(lowerOrEq);
  }

}
<<<< CODE_UNIT_END="/test" >>>>
<<<< [SOURCES_END] >>>>
'''));
    });

    test('Basic main(List<String>) with branches', () async {
      var vm = ApolloVM();

      var codeUnit = CodeUnit(
          'dart',
          r'''
          class Bar {
            static void main(List<Object> args) {
              var a = args[0] ;
              var b = args[1] ;
              var eq = a == b ;
              
              if (a == b) {
                print('if: a==b');
              }
              
              if (a != b) {
                print('if: a!=b');
              }
              else {
                print('else: a!=b');
              }
              
              if (a < b) {
                print('if: a<b');
              }
              else if (a > b) {
                print('else: a>b');
              }
              else {
                print('else: a==b');
              }
              
            }
          }
          ''',
          'test');

      var loadOK = await vm.loadCodeUnit(codeUnit);

      expect(loadOK, isTrue, reason: 'Error loading Dart code!');

      var dartRunner = vm.createRunner('dart')!;

      {
        var output = [];
        dartRunner.externalPrintFunction = (o) => output.add(o);

        await dartRunner.executeClassMethod('', 'Bar', 'main', [
          [10, 20]
        ]);

        expect(output, equals(['if: a!=b', 'if: a<b']));

        print('---------------------------------------');
        print('OUTPUT 1:');
        output.forEach((o) => print('>> $o'));
      }

      {
        var output = [];
        dartRunner.externalPrintFunction = (o) => output.add(o);

        await dartRunner.executeClassMethod('', 'Bar', 'main', [
          [20, 20]
        ]);

        expect(output, equals(['if: a==b', 'else: a!=b', 'else: a==b']));

        print('---------------------------------------');
        print('OUTPUT 1:');
        output.forEach((o) => print('>> $o'));
      }

      print('---------------------------------------');
      // Regenerate code:
      var codeStorageDart = vm.generateAllCodeIn('dart');
      var allSourcesDart = codeStorageDart.writeAllSources().toString();
      print(allSourcesDart);

      expect(allSourcesDart, equals(r'''<<<< [SOURCES_BEGIN] >>>>
<<<< NAMESPACE="" >>>>
<<<< CODE_UNIT_START="/test" >>>>
class Bar {

  static void main(List<Object> args) {
    var a = args[0];
    var b = args[1];
    var eq = a == b;
    if (a == b) {
        print('if: a==b');
    }

    if (a != b) {
        print('if: a!=b');
    } else {
        print('else: a!=b');
    }

    if (a < b) {
        print('if: a<b');
    } else if (      a > b) {
        print('else: a>b');
    } else {
        print('else: a==b');
    }

  }

}
<<<< CODE_UNIT_END="/test" >>>>
<<<< [SOURCES_END] >>>>
'''));

      print('---------------------------------------');
      // Regenerate code:
      var codeStorageJava = vm.generateAllCodeIn('java11');
      var allSourcesJava = codeStorageJava.writeAllSources().toString();
      print(allSourcesJava);

      expect(allSourcesJava, equals(r'''<<<< [SOURCES_BEGIN] >>>>
<<<< NAMESPACE="" >>>>
<<<< CODE_UNIT_START="/test" >>>>
class Bar {

  static void main(Object[] args) {
    var a = args[0];
    var b = args[1];
    var eq = a == b;
    if (a == b) {
        print("if: a==b");
    }

    if (a != b) {
        print("if: a!=b");
    } else {
        print("else: a!=b");
    }

    if (a < b) {
        print("if: a<b");
    } else if (      a > b) {
        print("else: a>b");
    } else {
        print("else: a==b");
    }

  }

}
<<<< CODE_UNIT_END="/test" >>>>
<<<< [SOURCES_END] >>>>
'''));
    });

    test('Basic Class function', () async {
      var vm = ApolloVM();

      var codeUnit = CodeUnit(
          'dart',
          r"""
            class Foo {
              void test(int a) {
                var s = '$this > a: $a' ;
                print(s);
              }
            }
          """,
          'test');

      var loadOK = await vm.loadCodeUnit(codeUnit);

      expect(loadOK, isTrue, reason: 'Error loading Dart code!');

      var dartRunner = vm.createRunner('dart')!;

      var output = [];
      dartRunner.externalPrintFunction = (o) => output.add(o);

      await dartRunner.executeClassMethod('', 'Foo', 'test', [123]);

      expect(output, equals(['Foo{} > a: 123']));

      print('---------------------------------------');
      print('OUTPUT:');
      output.forEach((o) => print('>> $o'));

      print('---------------------------------------');
      // Regenerate code:
      var codeStorageDart = vm.generateAllCodeIn('dart');
      var allSourcesDart = codeStorageDart.writeAllSources().toString();
      print(allSourcesDart);

      expect(allSourcesDart, equals(r'''<<<< [SOURCES_BEGIN] >>>>
<<<< NAMESPACE="" >>>>
<<<< CODE_UNIT_START="/test" >>>>
class Foo {

  void test(int a) {
    var s = '$this > a: $a';
    print(s);
  }

}
<<<< CODE_UNIT_END="/test" >>>>
<<<< [SOURCES_END] >>>>
'''));

      print('---------------------------------------');
      // Regenerate code:
      var codeStorageJava = vm.generateAllCodeIn('java11');
      var allSourcesJava = codeStorageJava.writeAllSources().toString();
      print(allSourcesJava);

      expect(allSourcesJava, equals(r'''<<<< [SOURCES_BEGIN] >>>>
<<<< NAMESPACE="" >>>>
<<<< CODE_UNIT_START="/test" >>>>
class Foo {

  void test(int a) {
    var s = String.valueOf( this ) + " > a: " + a;
    print(s);
  }

}
<<<< CODE_UNIT_END="/test" >>>>
<<<< [SOURCES_END] >>>>
'''));
    });

    test('Basic Class field', () async {
      var vm = ApolloVM();

      var codeUnit = CodeUnit(
          'dart',
          r"""
            class Foo {
              int x ;
              int y = 10 ;
              
              int getZ() {
                return y * 2 ;
              }
              
              void test(int a) {
                var z = getZ();
                var s = '$this > a: $a ; x: $x ; y: $y ; z: $z' ;
                print(s);
              }
            }
          """,
          'test');

      var loadOK = await vm.loadCodeUnit(codeUnit);

      expect(loadOK, isTrue, reason: 'Error loading Dart code!');

      var dartRunner = vm.createRunner('dart')!;

      var output = [];
      dartRunner.externalPrintFunction = (o) => output.add(o);

      await dartRunner.executeClassMethod('', 'Foo', 'test', [123]);

      expect(
          output,
          equals(
              ['Foo{x: int x, y: int y} > a: 123 ; x: null ; y: 10 ; z: 20']));

      print('---------------------------------------');
      print('OUTPUT:');
      output.forEach((o) => print('>> $o'));

      print('---------------------------------------');
      // Regenerate code:
      var codeStorageDart = vm.generateAllCodeIn('dart');
      var allSourcesDart = codeStorageDart.writeAllSources().toString();
      print(allSourcesDart);

      expect(allSourcesDart, equals(r'''<<<< [SOURCES_BEGIN] >>>>
<<<< NAMESPACE="" >>>>
<<<< CODE_UNIT_START="/test" >>>>
class Foo {

  int getZ() {
    return y * 2;
  }

  void test(int a) {
    var z = getZ();
    var s = '$this > a: $a ; x: $x ; y: $y ; z: $z';
    print(s);
  }

}
<<<< CODE_UNIT_END="/test" >>>>
<<<< [SOURCES_END] >>>>
'''));

      print('---------------------------------------');
      // Regenerate code:
      var codeStorageJava = vm.generateAllCodeIn('java11');
      var allSourcesJava = codeStorageJava.writeAllSources().toString();
      print(allSourcesJava);

      expect(allSourcesJava, equals(r'''<<<< [SOURCES_BEGIN] >>>>
<<<< NAMESPACE="" >>>>
<<<< CODE_UNIT_START="/test" >>>>
class Foo {

  int getZ() {
    return y * 2;
  }

  void test(int a) {
    var z = getZ();
    var s = String.valueOf( this ) + " > a: " + a + " ; x: " + x + " ; y: " + y + " ; z: " + z;
    print(s);
  }

}
<<<< CODE_UNIT_END="/test" >>>>
<<<< [SOURCES_END] >>>>
'''));
    });

    test('Basic Class function call with multiple parameters', () async {
      var vm = ApolloVM();

      var codeUnit = CodeUnit(
          'dart',
          r"""
            class Foo {
              int x = 0 ;
              int y = 10 ;
              
              int getZ() {
                return y * 2 ;
              }
              
              int calcB(int b1 , int b2) {
                return y * b1 * b2 ;
              }
              
              void test(int a) {
                var z = getZ();
                var b = calcB(z , 3);
                var s = '$this > a: $a ; x: $x ; y: $y ; z: $z ; b: $b' ;
                print(s);
              }
            }
          """,
          'test');

      var loadOK = await vm.loadCodeUnit(codeUnit);

      expect(loadOK, isTrue, reason: 'Error loading Dart code!');

      var dartRunner = vm.createRunner('dart')!;

      var output = [];
      dartRunner.externalPrintFunction = (o) => output.add(o);

      await dartRunner.executeClassMethod('', 'Foo', 'test', [123]);

      expect(
          output,
          equals([
            'Foo{x: int x, y: int y} > a: 123 ; x: 0 ; y: 10 ; z: 20 ; b: 600'
          ]));

      print('---------------------------------------');
      print('OUTPUT:');
      output.forEach((o) => print('>> $o'));

      print('---------------------------------------');
      // Regenerate code:
      var codeStorageDart = vm.generateAllCodeIn('dart');
      var allSourcesDart = codeStorageDart.writeAllSources().toString();
      print(allSourcesDart);

      expect(allSourcesDart, equals(r'''<<<< [SOURCES_BEGIN] >>>>
<<<< NAMESPACE="" >>>>
<<<< CODE_UNIT_START="/test" >>>>
class Foo {

  int getZ() {
    return y * 2;
  }

  int calcB(int b1, int b2) {
    return y * b1 * b2;
  }

  void test(int a) {
    var z = getZ();
    var b = calcB(z, 3);
    var s = '$this > a: $a ; x: $x ; y: $y ; z: $z ; b: $b';
    print(s);
  }

}
<<<< CODE_UNIT_END="/test" >>>>
<<<< [SOURCES_END] >>>>
'''));

      print('---------------------------------------');
      // Regenerate code:
      var codeStorageJava = vm.generateAllCodeIn('java11');
      var allSourcesJava = codeStorageJava.writeAllSources().toString();
      print(allSourcesJava);

      expect(allSourcesJava, equals(r'''<<<< [SOURCES_BEGIN] >>>>
<<<< NAMESPACE="" >>>>
<<<< CODE_UNIT_START="/test" >>>>
class Foo {

  int getZ() {
    return y * 2;
  }

  int calcB(int b1, int b2) {
    return y * b1 * b2;
  }

  void test(int a) {
    var z = getZ();
    var b = calcB(z, 3);
    var s = String.valueOf( this ) + " > a: " + a + " ; x: " + x + " ; y: " + y + " ; z: " + z + " ; b: " + b;
    print(s);
  }

}
<<<< CODE_UNIT_END="/test" >>>>
<<<< [SOURCES_END] >>>>
'''));
    });
  });
}
