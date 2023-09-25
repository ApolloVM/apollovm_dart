import 'package:apollovm/apollovm.dart';

import 'apollovm_languages_test_definition.dart';

Future<void> main() async {
  print('BASIC TESTS DEFINITIONS');

  var definitions = <TestDefinition>[
    TestDefinition('dart_basic_main_1.test.xml', '''
<?xml version="1.0" encoding="UTF-8"?>
<test title="Basic main(List<String>) 1">
    <source language="dart">
        <![CDATA[
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
        ]]>
    </source>
    <call function="main">
        [
          ["Strings:", "A", "B", "C"]
        ]
    </call>
    <output>
        ["Strings:", "AB", "ABC"]
    </output>
    <source-generated language="dart"><![CDATA[<<<< [SOURCES_BEGIN] >>>>
<<<< NAMESPACE="" >>>>
<<<< CODE_UNIT_START="/test" >>>>
  void main(List<String> args) {
    var title = args[0];
    var a = args[1];
    var b = args[2];
    var c = args[3];
    var sumAB = a + b;
    var sumABC = a + b + c;
    print(title);
    print(sumAB);
    print(sumABC);
  }

<<<< CODE_UNIT_END="/test" >>>>
<<<< [SOURCES_END] >>>>
]]></source-generated>
</test>
    '''),
    TestDefinition('java11_basic_main_1.test.xml', '''
<?xml version="1.0" encoding="UTF-8"?>
<test title="Basic main(Object[]) 1">
    <source language="java11">
        <![CDATA[

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

        ]]>
    </source>
    <call class="Foo" function="main">
        [
          ["Strings:", "A", "B", "C"]
        ]
    </call>
    <output>
        ["Strings:", "AB", "ABC"]
    </output>
    <source-generated language="dart"><![CDATA[<<<< [SOURCES_BEGIN] >>>>
<<<< NAMESPACE="" >>>>
<<<< CODE_UNIT_START="/test" >>>>
class Foo {

  static void main(List<String> args) {
    var title = args[0];
    var a = args[1];
    var b = args[2];
    var c = args[3];
    var sumAB = a + b;
    var sumABC = a + b + c;
    print(title);
    print(sumAB);
    print(sumABC);
  }

}
<<<< CODE_UNIT_END="/test" >>>>
<<<< [SOURCES_END] >>>>
]]></source-generated>

    <source-generated language="java11"><![CDATA[<<<< [SOURCES_BEGIN] >>>>
<<<< NAMESPACE="" >>>>
<<<< CODE_UNIT_START="/test" >>>>
class Foo {

  static void main(String[] args) {
    var title = args[0];
    var a = args[1];
    var b = args[2];
    var c = args[3];
    var sumAB = a + b;
    var sumABC = a + b + c;
    print(title);
    print(sumAB);
    print(sumABC);
  }

}
<<<< CODE_UNIT_END="/test" >>>>
<<<< [SOURCES_END] >>>>
]]></source-generated>
</test>
  '''),
    TestDefinition('dart_basic_main_2.test.xml', '''
<?xml version="1.0" encoding="UTF-8"?>
<test title="Basic main(List<String>) 2">
    <source language="dart">
        <![CDATA[
            void main(List args) {
              var title = args[0];
              var a = args[1];
              var b = args[2];
              var c = args[3];
              var sumAB = a + b ;
              var sumABC = a + b + c;
              print(title);
              print(sumAB);
              print(sumABC);
              
              // List:
              var list = <int>[a, b, c];
              print(list);
              
              var listEmpty = <String>[];
              print(listEmpty);
            }
        ]]>
    </source>
    <call function="main">
        [
          ["Integers:", 10, 20, 30]
        ]
    </call>
    <output>
         ["Integers:", 30, 60, [10, 20, 30], []]
    </output>
    <source-generated language="dart"><![CDATA[<<<< [SOURCES_BEGIN] >>>>
<<<< NAMESPACE="" >>>>
<<<< CODE_UNIT_START="/test" >>>>
  void main(List<dynamic> args) {
    var title = args[0];
    var a = args[1];
    var b = args[2];
    var c = args[3];
    var sumAB = a + b;
    var sumABC = a + b + c;
    print(title);
    print(sumAB);
    print(sumABC);
    var list = <int>[a, b, c];
    print(list);
    var listEmpty = <String>[];
    print(listEmpty);
  }

<<<< CODE_UNIT_END="/test" >>>>
<<<< [SOURCES_END] >>>>
]]></source-generated>
</test>
    '''),
    TestDefinition('dart_basic_main_3.test.xml', r'''
<?xml version="1.0" encoding="UTF-8"?>
<test title="Basic main(List<String>) 3">
    <source language="dart">
        <![CDATA[
        
          class Foo {
          
            void main(List args) {
              var title = args[0];
              var a = args[1];
              var b = args[2];
              var c = args[3];
              var sumAB = a + b ;
              var sumABC = a + b + c;
              print(title);
              print(sumAB);
              print(sumABC);
              
              // List:
              var list = <String>["x",'y',title];
              print('List: $list');
              print('List[0]: ${list[0]}');
              print('List[2]: ${list[2]}');
              
              // Map:
              var map = <String,int>{
              'a': a,
              'b': b,
              'c': c,
              };
              
              print('Map: $map');
              print('Map `b`: ${map['b']}');
            }
          
          }
        ]]>
    </source>
    <call class="Foo" function="main">
        [
          ["Integers:", 10, 20, 30]
        ]
    </call>
    <output>
          ["Integers:", 30, 60, "List: [x, y, Integers:]", "List[0]: x", "List[2]: Integers:", "Map: {a: 10, b: 20, c: 30}", "Map `b`: 20"]
    </output>
    <source-generated language="dart"><![CDATA[<<<< [SOURCES_BEGIN] >>>>
<<<< NAMESPACE="" >>>>
<<<< CODE_UNIT_START="/test" >>>>
class Foo {

  void main(List<dynamic> args) {
    var title = args[0];
    var a = args[1];
    var b = args[2];
    var c = args[3];
    var sumAB = a + b;
    var sumABC = a + b + c;
    print(title);
    print(sumAB);
    print(sumABC);
    var list = <String>['x', 'y', title];
    print('List: $list');
    print('List[0]: ${list[0]}');
    print('List[2]: ${list[2]}');
    var map = <String,int>{'a': a, 'b': b, 'c': c};
    print('Map: $map');
    print('Map `b`: ${map['b']}');
  }

}
<<<< CODE_UNIT_END="/test" >>>>
<<<< [SOURCES_END] >>>>
]]></source-generated>
    <source-generated language="java11"><![CDATA[<<<< [SOURCES_BEGIN] >>>>
<<<< NAMESPACE="" >>>>
<<<< CODE_UNIT_START="/test" >>>>
class Foo {

  void main(Object[] args) {
    var title = args[0];
    var a = args[1];
    var b = args[2];
    var c = args[3];
    var sumAB = a + b;
    var sumABC = a + b + c;
    print(title);
    print(sumAB);
    print(sumABC);
    var list = new ArrayList<String>(){{
      add("x");
      add("y");
      add(title);
    }};
    print("List: " + list);
    print("List[0]: " + String.valueOf( list[0] ));
    print("List[2]: " + String.valueOf( list[2] ));
    var map = new HashMap<String,int>(){{
      put("a", a);
      put("b", b);
      put("c", c);
    }};
    print("Map: " + map);
    print("Map `b`: " + String.valueOf( map["b"] ));
  }

}
<<<< CODE_UNIT_END="/test" >>>>
<<<< [SOURCES_END] >>>>
]]></source-generated>
</test>
    '''),
  ];

  await runTestDefinitions(definitions);
}
