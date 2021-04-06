import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

void main() {
  group('Java11', () {
    test('Basic main(Object[])', () async {
      var vm = ApolloVM();

      var codeUnit = CodeUnit(
          'java11',
          r'''
            class Foo {
               static public void main(Object[] args) {
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
            }
          ''',
          'test');

      var loadOK = await vm.loadCodeUnit(codeUnit);

      expect(loadOK, isTrue, reason: "Can't load Java 11 code!");

      var javaRunner = vm.createRunner('java11')!;

      var output = [];
      javaRunner.externalPrintFunction = (o) => output.add(o);

      javaRunner.executeClassMethod('', 'Foo', 'main', [
        ['Sums:', 10, 20, 50]
      ]);

      expect(output, equals(['Sums:', 30, 80]));

      print('---------------------------------------');
      print('OUTPUT:');
      output.forEach((o) => print('>> $o'));

      print('---------------------------------------');
      // Regenerate code:
      var codeStorageDart = vm.generateAllCodeIn('dart');
      var allSourcesDart = codeStorageDart.writeAllSources().toString();
      print(allSourcesDart);

      print('---------------------------------------');
      // Regenerate code:
      var codeStorageJava = vm.generateAllCodeIn('java11');
      var allSourcesJava = codeStorageJava.writeAllSources().toString();
      print(allSourcesJava);

      expect(
          allSourcesDart,
          matches(RegExp(r'\s*'
              r'class\s+Foo\s*\{'
              r'\s*void\s+main\(List<Object> args\)\s*\{'
              r'\s*var\s+title\s+=\s+args\[0\]\s*;'
              r'\s*var\s+a\s+=\s+args\[1\]\s*;'
              r'\s*var\s+b\s+=\s+args\[2\]\s*;'
              r'\s*var\s+c\s+=\s+args\[3\]\s*;'
              r'\s*var\s+sumAB\s+=\s+a\s*\+\s*b\s*;'
              r'\s*var\s+sumABC\s+=\s+a\s*\+\s*b\s*\+\s*c\s*;'
              r'\s*print\(title\)\s*;'
              r'\s*print\(sumAB\)\s*;'
              r'\s*print\(sumABC\)\s*;'
              r'\s*\}'
              r'\s*\}\s*')));

      expect(allSourcesJava, contains('void main('));
    });

    test('Basic main(String[])', () async {
      var vm = ApolloVM();

      var codeUnit = CodeUnit(
          'java11',
          r'''
            class Foo {
               static public void main(String[] args) {
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
            }
          ''',
          'test');

      var loadOK = await vm.loadCodeUnit(codeUnit);

      expect(loadOK, isTrue, reason: "Can't load Java 11 code!");

      var javaRunner = vm.createRunner('java11')!;

      var output = [];
      javaRunner.externalPrintFunction = (o) => output.add(o);

      javaRunner.executeClassMethod('', 'Foo', 'main', [
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

      print('---------------------------------------');
      // Regenerate code:
      var codeStorageJava = vm.generateAllCodeIn('java11');
      var allSourcesJava = codeStorageJava.writeAllSources().toString();
      print(allSourcesJava);

      expect(
          allSourcesDart,
          matches(RegExp(r'\s*'
              r'class\s+Foo\s*\{'
              r'\s*void\s+main\(List<String> args\)\s*\{'
              r'\s*var\s+title\s+=\s+args\[0\]\s*;'
              r'\s*var\s+a\s+=\s+args\[1\]\s*;'
              r'\s*var\s+b\s+=\s+args\[2\]\s*;'
              r'\s*var\s+c\s+=\s+args\[3\]\s*;'
              r'\s*var\s+sumAB\s+=\s+a\s*\+\s*b\s*;'
              r'\s*var\s+sumABC\s+=\s+a\s*\+\s*b\s*\+\s*c\s*;'
              r'\s*print\(title\)\s*;'
              r'\s*print\(sumAB\)\s*;'
              r'\s*print\(sumABC\)\s*;'
              r'\s*\}'
              r'\s*\}\s*')));

      expect(allSourcesJava, contains('void main('));
    });

    test('Basic main(Object[]) with inline string', () async {
      var vm = ApolloVM();

      var codeUnit = CodeUnit(
          'java11',
          r'''
            class Foo {
               static public void main(Object[] args) {
                 var title = args[0];
                 var a = args[1];
                 var b = args[2];
                 var s1 = "inline";
                 var s2 = "string";
                 var c = s1 + " \t\t " + s2;
                 var sumAB = a + b ;
                 var sumABC = a + b + c;
                 print(title);
                 print(sumAB);
                 print(sumABC);
               }
            }
          ''',
          'test');

      var loadOK = await vm.loadCodeUnit(codeUnit);

      expect(loadOK, isTrue, reason: "Can't load Java 11 code!");

      var javaRunner = vm.createRunner('java11')!;

      var output = [];
      javaRunner.externalPrintFunction = (o) => output.add(o);

      javaRunner.executeClassMethod('', 'Foo', 'main', [
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

      print('---------------------------------------');
      // Regenerate code:
      var codeStorageJava = vm.generateAllCodeIn('java11');
      var allSourcesJava = codeStorageJava.writeAllSources().toString();
      print(allSourcesJava);

      expect(allSourcesJava, r'''<<<< [SOURCES_BEGIN] >>>>
<<<< NAMESPACE="" >>>>
<<<< CODE_UNIT_START="/test" >>>>
class Foo {
  void main(Object[] args) {
    var title = args[0];
    var a = args[1];
    var b = args[2];
    var s1 = "inline";
    var s2 = "string";
    var c = s1 + " \t\t " + s2;
    var sumAB = a + b;
    var sumABC = a + b + c;
    print(title);
    print(sumAB);
    print(sumABC);
  }
}
<<<< CODE_UNIT_END="/test" >>>>
<<<< [SOURCES_END] >>>>
''');
    });

    test('Basic main(String[]) with branches', () async {
      var vm = ApolloVM();

      var codeUnit = CodeUnit(
          'java11',
          r'''
          class Bar {
            static public void main(Object[] args) {
              var a = args[0] ;
              var b = args[1] ;
              var eq = a == b ;
              
              if (a == b) {
                print("if: a==b");
              }
              
              if (a != b) {
                print("if: a!=b");
              }
              else {
                print("else: a!=b");
              }
              
              if (a < b) {
                print("if: a<b");
              }
              else if (a > b) {
                print("else: a>b");
              }
              else {
                print("else: a==b");
              }
              
            }
          }
          ''',
          'test');

      var loadOK = await vm.loadCodeUnit(codeUnit);

      expect(loadOK, isTrue, reason: 'Error loading Java 11 code!');

      var javaRunner = vm.createRunner('java11')!;

      {
        var output = [];
        javaRunner.externalPrintFunction = (o) => output.add(o);

        javaRunner.executeClassMethod('', 'Bar', 'main', [
          [10, 20]
        ]);

        expect(output, equals(['if: a!=b', 'if: a<b']));

        print('---------------------------------------');
        print('OUTPUT 1:');
        output.forEach((o) => print('>> $o'));
      }

      {
        var output = [];
        javaRunner.externalPrintFunction = (o) => output.add(o);

        javaRunner.executeClassMethod('', 'Bar', 'main', [
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
  void main(List<Object> args) {
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
  void main(Object[] args) {
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
  });
}

//         class Point {
//           private int x ;
//           private int y ;
//
//           public Point(int x, int y) {
//             this.x = x ;
//             this.y = y ;
//           }
//
//           public int getX() {
//             return x ;
//           }
//
//           public int getY() {
//             return y ;
//           }
//
//           public String toString() {
//             return "("+x+";"+y+")" ;
//           }
//
//           static public void main(String[] args) {
//             Point p = new Point(10,20);
//             System.out.println("The Point: "+ p);
//           }
//
//         }
//
