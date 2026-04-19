import 'package:apollovm/apollovm.dart';

import 'apollovm_languages_test_definition.dart';

Future<void> main() async {
  await _tests();
}

/*
Future<void> _benchmark() async {
  for (var i = 0; i < 100; ++i) {
    await _tests();
  }

  tearDownAll(() async {
    await Future.delayed(Duration(hours: 10));
  });
}
 */

Future<void> _tests() async {
  print('BASIC TESTS DEFINITIONS');

  var definitions = <TestDefinition>[
    TestDefinition('dart_basic_printFibonacci.test.xml', r'''
<?xml version="1.0" encoding="UTF-8"?>
<test title="Basic printFibonacci(int n)">
    <source language="dart">
        <![CDATA[
void printFibonacci(int n) {
  if (n <= 0) {
    print("Input must be a positive integer.");
    return;
  }

  if (n == 1) {
    print("Fibonacci sequence up to $n: 1");
    print("Sum: 1");
    return;
  }

  int a = 0;
  int b = 1;
  var sequence = <int>[];
  int sum = 0;

  while (a < n) {
    sequence.add(a);
    sum += a;

    int next = a + b;
    a = b;
    b = next;

    print("Fibonacci sequence up to $n (sum: $sum): $sequence");
  }
}

        ]]>
    </source>
    <call function="printFibonacci">
        [3]
    </call>
    <output>
          [
            "Fibonacci sequence up to 3 (sum: 0): [0]",
            "Fibonacci sequence up to 3 (sum: 1): [0, 1]",
            "Fibonacci sequence up to 3 (sum: 2): [0, 1, 1]",
            "Fibonacci sequence up to 3 (sum: 4): [0, 1, 1, 2]"
          ]
    </output>
    <source-generated language="dart"><![CDATA[<<<< [SOURCES_BEGIN] >>>>
<<<< NAMESPACE="" >>>>
<<<< CODE_UNIT_START="/test" >>>>
  void printFibonacci(int n) {
    if (n <= 0) {
        print('Input must be a positive integer.');
        return;
    }

    if (n == 1) {
        print('Fibonacci sequence up to $n: 1');
        print('Sum: 1');
        return;
    }

    int a = 0;
    int b = 1;
    var sequence = <int>[];
    int sum = 0;
    while( a < n ) {
      sequence.add(a);
      sum += a;
      int next = a + b;
      a = b;
      b = next;
      print('Fibonacci sequence up to $n (sum: $sum): $sequence');
    }
  }

<<<< CODE_UNIT_END="/test" >>>>
<<<< [SOURCES_END] >>>>
]]></source-generated>
</test>
    '''),
    TestDefinition('dart_basic_linearRegression.test.xml', r'''
<?xml version="1.0" encoding="UTF-8"?>
<test title="Basic linearRegression(List<double> x, List<double> y)">
    <source language="dart">
        <![CDATA[
class LinearModel {
   final double m;
   final double b;

   LinearModel(this.m, this.b);
}

LinearModel linearRegression(List<int> x, List<double> y) {
  if (x.length != y.length || x.length < 2) {
    // Input lists must have same length and >= 2 points:
    return null;
  }

  final n = x.length;

  double sumX = 0;
  double sumY = 0;

  for (int i = 0; i < n; i++) {
    sumX += x[i];
    sumY += y[i];
  }

  final meanX = sumX / n;
  final meanY = sumY / n;

  double num = 0;
  double den = 0;

  for (int i = 0; i < n; i++) {
    final dx = x[i] - meanX;
    final dy = y[i] - meanY;
    num += dx * dy;
    den += dx * dx;
  }

  if (den == 0) {
    // Cannot compute regression: zero variance in X:
    return null;
  }

  final m = num / den;
  final b = meanY - m * meanX;

  return LinearModel(m, b);
}

void forecast(int startX, LinearModel model) {
  final int days = 10;
  for (int i = 1; i <= days; i++) {
    final x = startX + i;
    final y = model.m * x + model.b;
    print('Forecast for Day $x: ${y.toStringAsFixed(2)}');
  }
}

void main() {
  // Historical BTC/USD rates
  final rates = [
    71428.571429, 71428.571429, 71428.571429, 66666.666667, 71428.571429,
    71428.571429, 71428.571429, 66666.666667, 66666.666667, 66666.666667,
    66666.666667, 66666.666667, 66666.666667, 66666.666667, 66666.666667,
    66666.666667, 71428.571429, 71428.571429, 71428.571429, 76923.076923
  ];

  // X axis: day index starting at 1
  final x = <int>[];
  for (int i = 0; i < rates.length; i++) {
    x.add(i + 1);
  }

  print('--- Linear Regression ---');

  final model = linearRegression(x, rates);

  print('Slope (m): ${model.m}');
  print('Intercept (b): ${model.b}');

  print('\n--- Forecast Next 10 Days ---');

  forecast(x.last, model);
}

        ]]>
    </source>
    <call function="main">
        []
    </call>
    <output>
         [
          "--- Linear Regression ---",
          "Slope (m): 28.367622344360782",
          "Intercept (b): 69024.48428808422",
          "\n--- Forecast Next 10 Days ---",
          "Forecast for Day 21: 1958656.22",
          "Forecast for Day 22: 1958684.59",
          "Forecast for Day 23: 1958712.96",
          "Forecast for Day 24: 1958741.33",
          "Forecast for Day 25: 1958769.69",
          "Forecast for Day 26: 1958798.06",
          "Forecast for Day 27: 1958826.43",
          "Forecast for Day 28: 1958854.80",
          "Forecast for Day 29: 1958883.16",
          "Forecast for Day 30: 1958911.53"
         ]
    </output>
    <source-generated language="dart"><![CDATA[<<<< [SOURCES_BEGIN] >>>>
<<<< NAMESPACE="" >>>>
<<<< CODE_UNIT_START="/test" >>>>
  LinearModel linearRegression(List<int> x, List<double> y) {
    if ((x.length != y.length) || (x.length < 2)) {
        return null;
    }

    final n = x.length;
    double sumX = 0;
    double sumY = 0;
    for (int i = 0; i < n ; i++) {
      sumX += x[i];
      sumY += y[i];
    }
    final meanX = sumX / n;
    final meanY = sumY / n;
    double num = 0;
    double den = 0;
    for (int i = 0; i < n ; i++) {
      final dx = x[i] - meanX;
      final dy = y[i] - meanY;
      num += dx * dy;
      den += dx * dx;
    }
    if (den == 0) {
        return null;
    }

    final m = num / den;
    final b = meanY - (m * meanX);
    return LinearModel(m, b);
  }

  void forecast(int startX, LinearModel model) {
    int days = 10;
    for (int i = 1; i <= days ; i++) {
      final x = startX + i;
      final y = model.m * (x + model.b);
      print('Forecast for Day $x: ${y.toStringAsFixed(2)}');
    }
  }

  void main() {
    final rates = <double>[71428.571429, 71428.571429, 71428.571429, 66666.666667, 71428.571429, 71428.571429, 71428.571429, 66666.666667, 66666.666667, 66666.666667, 66666.666667, 66666.666667, 66666.666667, 66666.666667, 66666.666667, 66666.666667, 71428.571429, 71428.571429, 71428.571429, 76923.076923];
    final x = <int>[];
    for (int i = 0; i < rates.length ; i++) {
      x.add(i + 1);
    }
    print('--- Linear Regression ---');
    final model = linearRegression(x, rates);
    print('Slope (m): ${model.m}');
    print('Intercept (b): ${model.b}');
    print('\n--- Forecast Next 10 Days ---');
    forecast(x.last, model);
  }

class LinearModel {

  final double m;
  final double b;

  LinearModel(this.m, this.b);

}
<<<< CODE_UNIT_END="/test" >>>>
<<<< [SOURCES_END] >>>>
]]></source-generated>
</test>
    '''),
    TestDefinition('dart_basic_stdv.test.xml', r'''
<?xml version="1.0" encoding="UTF-8"?>
<test title="Basic calculateStandardDeviation(List<double> numbers)">
    <source language="dart">
        <![CDATA[
double calculateStandardDeviation(List<double> numbers) {
  if (numbers == null || numbers.length < 2) {
    return 0.0; // Cannot calculate std dev for less than 2 points
  }

  // Calculate the mean
  double sum = 0;
  for (var x in numbers) {
    sum += x;
  }
  double mean = sum / numbers.length;

  // Calculate the sum of squared differences from the mean
  double squaredDifferencesSum = 0;
  for (var x in numbers) {
    squaredDifferencesSum += pow(x - mean, 2);
  }

  // Calculate the sample variance and then the standard deviation
  double variance = squaredDifferencesSum / (numbers.length - 1);
  return sqrt(variance);
}

void main() {
  // Example usage:
  List<double> data = [2.2, 0.001, 4.01, 4.10, 4.4, 5.5, 5.5, 7.7, 9.9];
  double stdDev = calculateStandardDeviation(data);

  print('The data set is: $data');
  print('The standard deviation is: $stdDev');
}

        ]]>
    </source>
    <call function="main">
        []
    </call>
    <output>
         [
          "The data set is: [2.2, 0.001, 4.01, 4.1, 4.4, 5.5, 5.5, 7.7, 9.9]",
          "The standard deviation is: 2.882341322605635"
         ]
    </output>
    <source-generated language="dart"><![CDATA[<<<< [SOURCES_BEGIN] >>>>
<<<< NAMESPACE="" >>>>
<<<< CODE_UNIT_START="/test" >>>>
  double calculateStandardDeviation(List<double> numbers) {
    if ((numbers == null) || (numbers.length < 2)) {
        return 0.0;
    }

    double sum = 0;
    for (var x in numbers) {
      sum += x;
    }
    double mean = sum / numbers.length;
    double squaredDifferencesSum = 0;
    for (var x in numbers) {
      squaredDifferencesSum += pow(x - mean, 2);
    }
    double variance = squaredDifferencesSum / (numbers.length - 1);
    return sqrt(variance);
  }

  void main() {
    List<double> data = <double>[2.2, 0.001, 4.01, 4.1, 4.4, 5.5, 5.5, 7.7, 9.9];
    double stdDev = calculateStandardDeviation(data);
    print('The data set is: $data');
    print('The standard deviation is: $stdDev');
  }

<<<< CODE_UNIT_END="/test" >>>>
<<<< [SOURCES_END] >>>>
]]></source-generated>
</test>
    '''),
    TestDefinition('dart_basic_factorial.test.xml', r'''
<?xml version="1.0" encoding="UTF-8"?>
<test title="Basic factorial(int n)">
    <source language="dart">
        <![CDATA[
int factorial(int n) {
  if (n < 0) {
    return 0; // Simplified handling for negative numbers instead of throwing an error
  }
  if (n == 0 || n == 1) {
    return 1;
  }
  int result = 1;
  for (int i = 2; i <= n; i++) {
    result *= i;
  }
  return result;
}

void main() {
  int number = 6;
  int fact = factorial(number);
  print('The factorial of $number is: $fact');
}

        ]]>
    </source>
    <call function="main">
        []
    </call>
    <output>
         ["The factorial of 6 is: 720"]
    </output>
    <call function="factorial" return="40320">
        [8]
    </call>
    <output>
         []
    </output>
    <source-generated language="dart"><![CDATA[<<<< [SOURCES_BEGIN] >>>>
<<<< NAMESPACE="" >>>>
<<<< CODE_UNIT_START="/test" >>>>
  int factorial(int n) {
    if (n < 0) {
        return 0;
    }

    if ((n == 0) || (n == 1)) {
        return 1;
    }

    int result = 1;
    for (int i = 2; i <= n ; i++) {
      result *= i;
    }
    return result;
  }

  void main() {
    int number = 6;
    int fact = factorial(number);
    print('The factorial of $number is: $fact');
  }

<<<< CODE_UNIT_END="/test" >>>>
<<<< [SOURCES_END] >>>>
]]></source-generated>
</test>
    '''),
    TestDefinition('dart_basic_findMax.test.xml', r'''
<?xml version="1.0" encoding="UTF-8"?>
<test title="Basic findMax(List<int> numbers)">
    <source language="dart">
        <![CDATA[
 void findMax(List<int> numbers) {
  if (numbers.isEmpty) {
    print("The list is empty.");
    return;
  }

  // Start by assuming the first element is the maximum
  var max = numbers[0];

  // Iterate through the rest of the list to find the actual maximum
  for (var number in numbers) {
    if (number > max) {
      max = number;
    }
  }

  print('The list is: $numbers');
  print('The maximum number in the list is: $max');
}

void main() {
  // Test Case 1: Positive and negative numbers
  List<int> data1 = [10, 5, 22, 8, 30, 9];
  findMax(data1);
  print('---');
   
  // Test Case 2: List with only one element
  List<int> data2 = [42];
  findMax(data2);
  print('---');
  
  // Test Case 3: Empty list (edge case handling)
  List<int> data3 = <int>[];
  findMax(data3);
  
  // Test Case 4: Empty list (not typed)
  List<int> data4 = [];
  findMax(data4);  
}

        ]]>
    </source>
    <call function="main">
        []
    </call>
    <output>
        [
          "The list is: [10, 5, 22, 8, 30, 9]",
          "The maximum number in the list is: 30",
          "---",
          "The list is: [42]",
          "The maximum number in the list is: 42",
          "---",
          "The list is empty.",
          "The list is empty."
        ]
    </output>
    <source-generated language="dart"><![CDATA[<<<< [SOURCES_BEGIN] >>>>
<<<< NAMESPACE="" >>>>
<<<< CODE_UNIT_START="/test" >>>>
  void findMax(List<int> numbers) {
    if (numbers.isEmpty) {
        print('The list is empty.');
        return;
    }

    var max = numbers[0];
    for (var number in numbers) {
      if (number > max) {
          max = number;
      }

    }
    print('The list is: $numbers');
    print('The maximum number in the list is: $max');
  }

  void main() {
    List<int> data1 = <int>[10, 5, 22, 8, 30, 9];
    findMax(data1);
    print('---');
    List<int> data2 = <int>[42];
    findMax(data2);
    print('---');
    List<int> data3 = <int>[];
    findMax(data3);
    List<int> data4 = <int>[];
    findMax(data4);
  }

<<<< CODE_UNIT_END="/test" >>>>
<<<< [SOURCES_END] >>>>
]]></source-generated>
</test>
    '''),
    TestDefinition('dart_basic_findMax.test.xml', r'''
<?xml version="1.0" encoding="UTF-8"?>
<test title="Basic findMax(List<int> numbers)">
    <source language="dart">
        <![CDATA[
int findMax(List<int> numbers) {
  if (numbers.isEmpty) {
    print("The list is empty.");
    return;
  }

  // Start by assuming the first element is the maximum
  int max = numbers[0];

  // Iterate through the rest of the list to find the actual maximum
  for (var number in numbers) {
    if (number > max) {
      max = number;
    }
  }

  print('The list is: $numbers');
  print('The maximum number in the list is: $max');
  return max;
}

        ]]>
    </source>
    <call function="findMax" return="30">
        [[10, 5, 22, 8, 30, 9]]
    </call>
    <output>
        [
          "The list is: [10, 5, 22, 8, 30, 9]",
          "The maximum number in the list is: 30"
        ]
    </output>
    <source-generated language="dart"><![CDATA[<<<< [SOURCES_BEGIN] >>>>
<<<< NAMESPACE="" >>>>
<<<< CODE_UNIT_START="/test" >>>>
  int findMax(List<int> numbers) {
    if (numbers.isEmpty) {
        print('The list is empty.');
        return;
    }

    int max = numbers[0];
    for (var number in numbers) {
      if (number > max) {
          max = number;
      }

    }
    print('The list is: $numbers');
    print('The maximum number in the list is: $max');
    return max;
  }

<<<< CODE_UNIT_END="/test" >>>>
<<<< [SOURCES_END] >>>>
]]></source-generated>
</test>
    '''),
    TestDefinition('dart_basic_sumOfEvens.test.xml', r'''
<?xml version="1.0" encoding="UTF-8"?>
<test title="Basic sumOfEvens(List<int> numbers)">
    <source language="dart">
        <![CDATA[
int sumOfEvens(List<int> numbers) {
  int sum = 0;
  for (var i = 0 ; i < numbers.length ; ++i) {
    var number = numbers[i] ;
    if (number % 2 == 0) {
      sum += number;
      print('[$i] $number -> $sum');
    }
  }
  return sum;
}

        ]]>
    </source>
    <call function="sumOfEvens" return="12">
        [[1, 2, 3, 4, 5, 6]]
    </call>
    <output>
        [
          "[1] 2 -> 2",
          "[3] 4 -> 6",
          "[5] 6 -> 12"
        ]
    </output>
    <source-generated language="dart"><![CDATA[<<<< [SOURCES_BEGIN] >>>>
<<<< NAMESPACE="" >>>>
<<<< CODE_UNIT_START="/test" >>>>
  int sumOfEvens(List<int> numbers) {
    int sum = 0;
    for (var i = 0; i < numbers.length ; ++i) {
      var number = numbers[i];
      if ((number % 2) == 0) {
          sum += number;
          print('[$i] $number -> $sum');
      }

    }
    return sum;
  }

<<<< CODE_UNIT_END="/test" >>>>
<<<< [SOURCES_END] >>>>
]]></source-generated>
</test>
    '''),
    TestDefinition('dart_basic_fizzBuzz.test.xml', r'''
<?xml version="1.0" encoding="UTF-8"?>
<test title="Basic fizzBuzz(int n)">
    <source language="dart">
        <![CDATA[
void fizzBuzz(int n) {
  for (var i = 1; i <= n; i++) {
    if (i % 3 == 0 && i % 5 == 0) {
      print('$i is a multiple of both 3 and 5');
    } else if (i % 3 == 0) {
      print('$i is a multiple of 3');
    } else if (i % 5 == 0) {
      print('$i is a multiple of 5');
    } else {
      print('$i');
    }
  }
}
        ]]>
    </source>
    <call function="fizzBuzz" return="null">
        [15]
    </call>
    <output>
        [
          "1",
          "2",
          "3 is a multiple of 3",
          "4",
          "5 is a multiple of 5",
          "6 is a multiple of 3",
          "7",
          "8",
          "9 is a multiple of 3",
          "10 is a multiple of 5",
          "11",
          "12 is a multiple of 3",
          "13",
          "14",
          "15 is a multiple of both 3 and 5"
        ]
    </output>
    <source-generated language="dart"><![CDATA[<<<< [SOURCES_BEGIN] >>>>
<<<< NAMESPACE="" >>>>
<<<< CODE_UNIT_START="/test" >>>>
  void fizzBuzz(int n) {
    for (var i = 1; i <= n ; i++) {
      if (((i % 3) == 0) && ((i % 5) == 0)) {
          print('$i is a multiple of both 3 and 5');
      } else if ((i % 3) == 0) {
          print('$i is a multiple of 3');
      } else if ((i % 5) == 0) {
          print('$i is a multiple of 5');
      } else {
          print('$i');
      }

    }
  }

<<<< CODE_UNIT_END="/test" >>>>
<<<< [SOURCES_END] >>>>
]]></source-generated>
</test>
    '''),
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
    TestDefinition('dart_basic_calculateShippingCost.test.xml', r'''
<?xml version="1.0" encoding="UTF-8"?>
<test title="Basic calculateShippingCost(String destination, double weightKg)">
    <source language="dart">
        <![CDATA[
double calculateShippingCost(String destination, double weightKg) {
  // Normalize the destination string to ensure case-insensitivity
  final normalizedDest = destination.toLowerCase();

  // 1. Primary Reasoning: Check Destination Type
  if (normalizedDest == 'domestic') {
    // Logic for Domestic Shipping
    if (weightKg <= 5) {
      // Rule A: Light domestic package
      return 10;
    } else if (weightKg <= 20) {
      // Rule B: Medium domestic package
      return 15;
    } else {
      // Rule C: Heavy domestic package
      return 25;
    }
  } else if (normalizedDest == 'international') {
    // Logic for International Shipping
    if (weightKg <= 10) {
      // Rule D: Light international package
      return 40;
    } else {
      // Rule E: Heavy international package
      return 60;
    }
  } else {
    // Default/Fallback Reasoning: If the destination is unknown, return 0.0
    return 0; // Signifies an invalid or uncalculable route
  }
}

void main() {
  print("--- Shipping Cost Calculator (No Exceptions) ---");

  // Test Case 1: Light Domestic Package (Expected: 10.0)
  double cost1 = calculateShippingCost('Domestic', 3.5);
  print("Cost for a 3.5kg domestic package: \$${cost1.toStringAsFixed(2)}\n");

  // Test Case 2: Heavy Domestic Package (Expected: 25.0)
  double cost2 = calculateShippingCost('Domestic', 15);
  print("Cost for a 15.0kg domestic package: \$${cost2.toStringAsFixed(2)}\n");

  // Test Case 3: Light International Package (Expected: 40.0)
  double cost3 = calculateShippingCost('International', 8);
  print("Cost for an 8.0kg international package: \$${cost3.toStringAsFixed(2)}\n");

  // Test Case 4: Heavy International Package (Expected: 60.0)
  double cost4 = calculateShippingCost('International', 12);
  print("Cost for a 12.0kg international package: \$${cost4.toStringAsFixed(2)}\n");

  // Test Case 5: Invalid Destination (Reasoning returns 0.0)
  double cost5 = calculateShippingCost('Mars', 1);
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
        if (weightKg <= 5) {
            return 10;
        } else if (weightKg <= 20) {
            return 15;
        } else {
            return 25;
        }

    } else if (normalizedDest == 'international') {
        if (weightKg <= 10) {
            return 40;
        } else {
            return 60;
        }

    } else {
        return 0;
    }

  }

  void main() {
    print('--- Shipping Cost Calculator (No Exceptions) ---');
    double cost1 = calculateShippingCost('Domestic', 3.5);
    print('Cost for a 3.5kg domestic package: \$${cost1.toStringAsFixed(2)}\n');
    double cost2 = calculateShippingCost('Domestic', 15);
    print('Cost for a 15.0kg domestic package: \$${cost2.toStringAsFixed(2)}\n');
    double cost3 = calculateShippingCost('International', 8);
    print('Cost for an 8.0kg international package: \$${cost3.toStringAsFixed(2)}\n');
    double cost4 = calculateShippingCost('International', 12);
    print('Cost for a 12.0kg international package: \$${cost4.toStringAsFixed(2)}\n');
    double cost5 = calculateShippingCost('Mars', 1);
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

  await runTestDefinitions(
    // [definitions[0]],
    // definitions.sublist(1),
    // definitions
    //     .where((e) => e.fileName.contains('dart_basic_linearRegression'))
    //     .toList(),
    definitions,
  );
}
