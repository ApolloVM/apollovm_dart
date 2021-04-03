import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

void main() {
  group('Java8', () {
    test('Basic main()', () async {
      var vm = ApolloVM();

      var codeUnit = CodeUnit(
          'java8',
          r'''
        class Foo {
           static public void main(String[] args) {
             String s = args[0] ;
             print(s);
           }
        }
      ''',
          'test');

      var loadOK = await vm.loadCodeUnit(codeUnit);

      expect(loadOK, isTrue);

      var java8Runner = vm.getRunner('java8')!;
      java8Runner.executeClassMethod('', 'Foo', 'main', [
        ['foo!', 'abc']
      ]);

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

      expect(allSourcesDart, contains('void main('));
      expect(allSourcesJava8, contains('void main('));
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
