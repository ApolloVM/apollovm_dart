import 'package:apollovm/apollovm.dart';

import 'apollovm_languages_test_definition.dart';

Future<void> main() async {
  print('BASIC TESTS DEFINITIONS');

  var definitions = <TestDefinition>[
    TestDefinition('dart_basic_sumOrDouble.test.xml', '''
<?xml version="1.0" encoding="UTF-8"?>
<test title="Basic sumOrDouble(int a, int b)">
    <source language="dart">
        <![CDATA[
            int sumOrDouble(int a, int b) {
  if (a > b) {
    print('if (a > b)');
    return a + b;
  } else {
    print("else");
    return (a + b) * 2;
  }
}
        ]]>
    </source>
    <call function="sumOrDouble" return="14">
        [3, 4]
    </call>
    <output>
        ["else"]
    </output>
    <call function="sumOrDouble" return="7">
        [4, 3]
    </call>
    <output>
        ["if (a > b)"]
    </output>
    <source-generated language="dart"><![CDATA[<<<< [SOURCES_BEGIN] >>>>
<<<< NAMESPACE="" >>>>
<<<< CODE_UNIT_START="/test" >>>>
  int sumOrDouble(int a, int b) {
    if (a > b) {
        print('if (a > b)');
        return a + b;
    } else {
        print('else');
        return (a + b) * 2;
    }

  }

<<<< CODE_UNIT_END="/test" >>>>
<<<< [SOURCES_END] >>>>
]]></source-generated>
</test>
    '''),
    TestDefinition('dart_basic_main_print_multi_line.test.xml', '''
<?xml version="1.0" encoding="UTF-8"?>
<test title="Basic sumOrDouble(int a, int b)">
    <source language="dart">
        <![CDATA[
void main() {
  print("-- single line.");
  print("-- multi lines:\\n  -- a.\\n  -- b.\\n");
}
        ]]>
    </source>
    <call function="main">
        []
    </call>
    <output>
        [
            "-- single line.",
            "-- multi lines:\\n  -- a.\\n  -- b.\\n"
        ]
    </output>
    <source-generated language="dart"><![CDATA[<<<< [SOURCES_BEGIN] >>>>
<<<< NAMESPACE="" >>>>
<<<< CODE_UNIT_START="/test" >>>>
  void main() {
    print('-- single line.');
    print('-- multi lines:\\n  -- a.\\n  -- b.\\n');
  }

<<<< CODE_UNIT_END="/test" >>>>
<<<< [SOURCES_END] >>>>
]]></source-generated>
</test>
    '''),
    TestDefinition('dart_basic_main_print_unnecessary_escape.test.xml', r'''
<?xml version="1.0" encoding="UTF-8"?>
<test title="Basic sumOrDouble(int a, int b)">
    <source language="dart">
        <![CDATA[
void main() {
  // Some comment!
  print("--- ASCII Art ---\n");
  print(" \\ / ");
  print(" | | ");
  print(" --- ");
  print(" \\ / ");
  print("  |\  \n");
}
        ]]>
    </source>
    <call function="main">
        []
    </call>
    <output>
        [
            "--- ASCII Art ---\n",
            " \\ / ",
            " | | ",
            " --- ",
            " \\ / ",
            "  |  \n"
          ]
    </output>
    <source-generated language="dart"><![CDATA[<<<< [SOURCES_BEGIN] >>>>
<<<< NAMESPACE="" >>>>
<<<< CODE_UNIT_START="/test" >>>>
  void main() {
    print('--- ASCII Art ---\n');
    print(r' \ / ');
    print(' | | ');
    print(' --- ');
    print(r' \ / ');
    print('  |  \n');
  }

<<<< CODE_UNIT_END="/test" >>>>
<<<< [SOURCES_END] >>>>
]]></source-generated>
</test>
    '''),
    TestDefinition('dart_basic_main_print_unnecessary_escape.test.xml', r'''
<?xml version="1.0" encoding="UTF-8"?>
<test title="Basic sumOrDouble(int a, int b)">
    <source language="dart">
        <![CDATA[
double calculateShippingCost(String destination, double weightKg) {
  // Normalize the destination string to ensure case-insensitivity
  final normalizedDest = destination.toLowerCase();

  // 1. Primary Reasoning: Check Destination Type
  if (normalizedDest == 'domestic') {
    // Logic for Domestic Shipping
    if (weightKg <= 5.0) {
      // Rule A: Light domestic package
      return 10.0;
    } else if (weightKg <= 20.0) {
      // Rule B: Medium domestic package
      return 15.0;
    } else {
      // Rule C: Heavy domestic package
      return 25.0;
    }
  } else if (normalizedDest == 'international') {
    // Logic for International Shipping
    if (weightKg <= 10.0) {
      // Rule D: Light international package
      return 40.0;
    } else {
      // Rule E: Heavy international package
      return 60.0;
    }
  } else {
    // Default/Fallback Reasoning: If the destination is unknown, return 0.0
    return 0.0; // Signifies an invalid or uncalculable route
  }
}

void main() {
  print("--- Shipping Cost Calculator (No Exceptions) ---");

  // Test Case 1: Light Domestic Package (Expected: 10.0)
  double cost1 = calculateShippingCost('Domestic', 3.5);
  print("Cost for a 3.5kg domestic package: \$${cost1.toStringAsFixed(2)}\n");

  // Test Case 2: Heavy Domestic Package (Expected: 25.0)
  double cost2 = calculateShippingCost('Domestic', 15.0);
  print("Cost for a 15.0kg domestic package: \$${cost2.toStringAsFixed(2)}\n");

  // Test Case 3: Light International Package (Expected: 40.0)
  double cost3 = calculateShippingCost('International', 8.0);
  print("Cost for an 8.0kg international package: \$${cost3.toStringAsFixed(2)}\n");

  // Test Case 4: Heavy International Package (Expected: 60.0)
  double cost4 = calculateShippingCost('International', 12.0);
  print("Cost for a 12.0kg international package: \$${cost4.toStringAsFixed(2)}\n");

  // Test Case 5: Invalid Destination (Reasoning returns 0.0)
  double cost5 = calculateShippingCost('Mars', 1.0);
  print("Cost for an invalid destination ('Mars'): \$${cost5.toStringAsFixed(2)}\n");
}
        ]]>
    </source>
    <call function="main">
        []
    </call>
    <output>
       [
        "--- Shipping Cost Calculator (No Exceptions) ---",
        "Cost for a 3.5kg domestic package: $10.00\n",
        "Cost for a 15.0kg domestic package: $15.00\n",
        "Cost for an 8.0kg international package: $40.00\n",
        "Cost for a 12.0kg international package: $60.00\n",
        "Cost for an invalid destination ('Mars'): $0.00\n"
      ]
    </output>
    <source-generated language="dart"><![CDATA[<<<< [SOURCES_BEGIN] >>>>
<<<< NAMESPACE="" >>>>
<<<< CODE_UNIT_START="/test" >>>>
  double calculateShippingCost(String destination, double weightKg) {
    final normalizedDest = destination.toLowerCase();
    if (normalizedDest == 'domestic') {
        if (weightKg <= 5.0) {
            return 10.0;
        } else if (weightKg <= 20.0) {
            return 15.0;
        } else {
            return 25.0;
        }

    } else if (normalizedDest == 'international') {
        if (weightKg <= 10.0) {
            return 40.0;
        } else {
            return 60.0;
        }

    } else {
        return 0.0;
    }

  }

  void main() {
    print('--- Shipping Cost Calculator (No Exceptions) ---');
    double cost1 = calculateShippingCost('Domestic', 3.5);
    print('Cost for a 3.5kg domestic package: \$${cost1.toStringAsFixed(2)}\n');
    double cost2 = calculateShippingCost('Domestic', 15.0);
    print('Cost for a 15.0kg domestic package: \$${cost2.toStringAsFixed(2)}\n');
    double cost3 = calculateShippingCost('International', 8.0);
    print('Cost for an 8.0kg international package: \$${cost3.toStringAsFixed(2)}\n');
    double cost4 = calculateShippingCost('International', 12.0);
    print('Cost for a 12.0kg international package: \$${cost4.toStringAsFixed(2)}\n');
    double cost5 = calculateShippingCost('Mars', 1.0);
    print("Cost for an invalid destination ('Mars'): "'\$${cost5.toStringAsFixed(2)}\n');
  }

<<<< CODE_UNIT_END="/test" >>>>
<<<< [SOURCES_END] >>>>
]]></source-generated>
</test>
    '''),
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
    var sumABC = a + (b + c);
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
    var sumABC = a + (b + c);
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
    var sumABC = a + (b + c);
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
              var sumABC = a + (b + c);
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
    var sumABC = a + (b + c);
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
    var sumABC = a + (b + c);
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
    var sumABC = a + (b + c);
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
    TestDefinition('dart_basic_class_function_with_multi_args.test.xml', r'''
<?xml version="1.0" encoding="UTF-8"?>
<test title="Basic Class function call with multiple parameters">
    <source language="dart">
        <![CDATA[

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

        ]]>
    </source>
    <call class="Foo" function="test">
        [123]
    </call>
    <output>
        ["Foo{x: int, y: int} > a: 123 ; x: 0 ; y: 10 ; z: 20 ; b: 600"]
    </output>
    <source-generated language="dart"><![CDATA[<<<< [SOURCES_BEGIN] >>>>
<<<< NAMESPACE="" >>>>
<<<< CODE_UNIT_START="/test" >>>>
class Foo {

  int x = 0;
  int y = 10;

  int getZ() {
    return y * 2;
  }

  int calcB(int b1, int b2) {
    return y * (b1 * b2);
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
]]></source-generated>

    <source-generated language="java11"><![CDATA[<<<< [SOURCES_BEGIN] >>>>
<<<< NAMESPACE="" >>>>
<<<< CODE_UNIT_START="/test" >>>>
class Foo {

  int x = 0;
  int y = 10;

  int getZ() {
    return y * 2;
  }

  int calcB(int b1, int b2) {
    return y * (b1 * b2);
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
]]></source-generated>
</test>
    '''),
  ];

  await runTestDefinitions([definitions[3]]);
}
