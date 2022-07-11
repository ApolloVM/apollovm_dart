import 'package:apollovm/apollovm.dart';

import 'apollovm_languages_test_definition.dart';

Future<void> main() async {
  print('BASIC TESTS DEFINITIONS');

  var definitions = <TestDefinition>[
    TestDefinition('dart_basic_main_2.test.xml', '''
<?xml version="1.0" encoding="UTF-8"?>
<test title="Basic main(List<String>) 2">
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
    TestDefinition('java11_basic_main_2.test.xml', '''
<?xml version="1.0" encoding="UTF-8"?>
<test title="Basic main(Object[]) 2">
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
  ];

  await runTestDefinitions(definitions);
}
