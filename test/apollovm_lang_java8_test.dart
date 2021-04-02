import 'package:apollovm/src/languages/java/java8/java8_parser.dart';
import 'package:test/test.dart';

void main() {
  group('Java8', () {
    test('Basic main()', () async {
      var parser = ApolloParserJava8();

      var root = await parser.parse(r'''
        class Foo {
           static public void main(String[] args) {
             String s = args[0] ;
             print(s);
           }
        }
      ''');

      //Point p = new Point(10,20);
      //System.out.println("The Point: "+ p);

      expect(root, isNotNull);

      print('<<<<<<<<<<<<<<<<<<<< REGENERATE PARSED JAVA CODE:');
      print(root!.generateCode());
      print('>>>>>>>>>>>>>>>>>>>>');

      root.getClass('Foo')!.execute('main', [
        ['foo!', 'abc']
      ]);
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
