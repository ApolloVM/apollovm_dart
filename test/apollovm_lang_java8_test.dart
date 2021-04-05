import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

void main() {
  group('Java8', () {
    test('Basic main(Object[])', () async {
      var vm = ApolloVM();

      var codeUnit = CodeUnit(
          'java8',
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

      expect(loadOK, isTrue, reason: "Can't load Java8 code!");

      var java8Runner = vm.createRunner('java8')!;

      var output = [];
      java8Runner.externalPrintFunction = (o) => output.add(o);

      java8Runner.executeClassMethod('', 'Foo', 'main', [
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
      var codeStorageJava8 = vm.generateAllCodeIn('java8');
      var allSourcesJava8 = codeStorageJava8.writeAllSources().toString();
      print(allSourcesJava8);

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

      expect(allSourcesJava8, contains('void main('));
    });

    test('Basic main(String[])', () async {
      var vm = ApolloVM();

      var codeUnit = CodeUnit(
          'java8',
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

      expect(loadOK, isTrue, reason: "Can't load Java8 code!");

      var java8Runner = vm.createRunner('java8')!;

      var output = [];
      java8Runner.externalPrintFunction = (o) => output.add(o);

      java8Runner.executeClassMethod('', 'Foo', 'main', [
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
      var codeStorageJava8 = vm.generateAllCodeIn('java8');
      var allSourcesJava8 = codeStorageJava8.writeAllSources().toString();
      print(allSourcesJava8);

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

      expect(allSourcesJava8, contains('void main('));
    });

    test('Basic main(Object[]) with inline string', () async {
      var vm = ApolloVM();

      var codeUnit = CodeUnit(
          'java8',
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

      expect(loadOK, isTrue, reason: "Can't load Java8 code!");

      var java8Runner = vm.createRunner('java8')!;

      var output = [];
      java8Runner.externalPrintFunction = (o) => output.add(o);

      java8Runner.executeClassMethod('', 'Foo', 'main', [
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
      var codeStorageJava8 = vm.generateAllCodeIn('java8');
      var allSourcesJava8 = codeStorageJava8.writeAllSources().toString();
      print(allSourcesJava8);

      expect(allSourcesJava8, r'''<<<< [SOURCES_BEGIN] >>>>
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
