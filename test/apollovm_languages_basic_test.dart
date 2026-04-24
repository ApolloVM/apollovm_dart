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
    TestDefinition('dart_basic_exchange_rates.test.xml', r'''
<?xml version="1.0" encoding="UTF-8"?>
<test title="Basic main()">
    <source language="dart">
        <![CDATA[
 void main() {
  // --- Populated Data from FX Calls (BTC Rates for 31 Days: March 23 to April 22, 2026) ---

  // BTC/USD Rates (Index corresponds to the date)
  List<double> btcUsdRates = [
    71428.571429, // 2026-03-23
    71428.571429, // 2026-03-24
    71428.571429, // 2026-03-25
    66666.666667, // 2026-03-26
    66666.666667, // 2026-03-27
    66666.666667, // 2026-03-28
    66666.666667, // 2026-03-29
    66666.666667, // 2026-03-30
    66666.666667, // 2026-03-31
    66666.666667, // 2026-04-01
    66666.666667, // 2026-04-02
    66666.666667, // 2026-04-03
    66666.666667, // 2026-04-04
    66666.666667, // 2026-04-05
    66666.666667, // 2026-04-06
    71428.571429, // 2026-04-07
    71428.571429, // 2026-04-08
    71428.571429, // 2026-04-09
    71428.571429, // 2026-04-10
    71428.571429, // 2026-04-11
    71428.571429, // 2026-04-12
    76923.076923, // 2026-04-13
    76923.076923, // 2026-04-14
    76923.076923, // 2026-04-15
    76923.076923, // 2026-04-16
    76923.076923, // 2026-04-17
    76923.076923, // 2026-04-18
    71428.571429, // 2026-04-19
    76923.076923, // 2026-04-20
    76923.076923, // 2026-04-21
    76923.076923, // 2026-04-22
  ];

  // BTC/EUR Rates (Index corresponds to the date)
  List<double> btcEurRates = [
    61667.50, // 2026-03-23
    61559.428571, // 2026-03-24
    61746.285714, // 2026-03-25
    57778.40, // 2026-03-26
    57743.266667, // 2026-03-27
    57774.066667, // 2026-03-28
    58014.60, // 2026-03-29
    58194.466667, // 2026-03-30
    57636.866667, // 2026-03-31
    57511.466667, // 2026-04-01
    57757.666667, // 2026-04-02
    57873.466667, // 2026-04-03
    57874.533333, // 2026-04-04
    57919.40, // 2026-04-05
    57766.533333, // 2026-04-06
    61151.785714, // 2026-04-07
    61260.357143, // 2026-04-08
    61081.928571, // 2026-04-09
    60923.50, // 2026-04-10
    60920.928571, // 2026-04-11
    61199.428571, // 2026-04-12
    65381.00, // 2026-04-13
    65198.769231, // 2026-04-14
    65156.538462, // 2026-04-15
    65273.384615, // 2026-04-16
    65240.00, // 2026-04-17
    65339.769231, // 2026-04-18
    60828.571429, // 2026-04-19
    65277.461538, // 2026-04-20
    65516.538462, // 2026-04-21
    65711.538462, // 2026-04-22
  ];

  // BTC/BRL Rates (Index corresponds to the date)
  List<double> btcBrlRates = [
    373796.642857, // 2026-03-23
    373876.214286, // 2026-03-24
    374064.214286, // 2026-03-25
    349252.066667, // 2026-03-26
    349463.4, // 2026-03-27
    349458.8, // 2026-03-28
    349274.0, // 2026-03-29
    350766.733333, // 2026-03-30
    346151.533333, // 2026-03-31
    343726.666667, // 2026-04-01
    343902.2, // 2026-04-02
    343910.2, // 2026-04-03
    344840.266667, // 2026-04-04
    343923.066667, // 2026-04-05
    342827.666667, // 2026-04-06
    368091.0, // 2026-04-07
    364361.857143, // 2026-04-08
    363221.357143, // 2026-04-09
    357680.214286, // 2026-04-10
    357534.214286, // 2026-04-11
    357649.857143, // 2026-04-12
    384353.846154, // 2026-04-13
    383614.076923, // 2026-04-14
    384123.692308, // 2026-04-15
    383965.461538, // 2026-04-16
    382975.615385, // 2026-04-17
    383204.153846, // 2026-04-18
    356644.428571, // 2026-04-19
    381191.230769, // 2026-04-20
    384182.846154, // 2026-04-21
    382959.923077, // 2026-04-22
  ];

  // --- Calculations ---
  List<double> usdChanges = [];
  List<double> eurChanges = [];
  List<double> brlChanges = [];

  for (int i = 1; i < btcUsdRates.length; i++) {
    usdChanges.add(btcUsdRates[i] - btcUsdRates[i - 1]);
    eurChanges.add(btcEurRates[i] - btcEurRates[i - 1]);
    brlChanges.add(btcBrlRates[i] - btcBrlRates[i - 1]);
  }

  // Calculate Averages
  double avgUsdChange = 0.0;
  double avgEurChange = 0.0;
  double avgBrlChange = 0.0;

  for (double change in usdChanges) {
    avgUsdChange += change;
  }
  if (usdChanges.isNotEmpty) {
    avgUsdChange = avgUsdChange / usdChanges.length;
  }

  for (double change in eurChanges) {
    avgEurChange += change;
  }
  if (eurChanges.isNotEmpty) {
    avgEurChange = avgEurChange / eurChanges.length;
  }

  for (double change in brlChanges) {
    avgBrlChange += change;
  }
  if (brlChanges.isNotEmpty) {
    avgBrlChange = avgBrlChange / brlChanges.length;
  }


  // --- Display Results ---
  print("=============================================");
  print("        BTC Daily Ratio Change Analysis       ");
  print("=============================================\n");

  print("--- 1. Daily Ratio Changes (USD) ---");
  for (int i = 0; i < usdChanges.length; i++) {
    print("Change from ${btcUsdRates[i].toString().padRight(15)} to ${btcUsdRates[i+1].toString().padRight(15)}: ${usdChanges[i].toStringAsFixed(2)}\n");
  }

  print("\n--- 2. Daily Ratio Changes (EUR) ---");
  for (int i = 0; i < eurChanges.length; i++) {
    print("Change from ${btcEurRates[i].toString().padRight(15)} to ${btcEurRates[i+1].toString().padRight(15)}: ${eurChanges[i].toStringAsFixed(2)}\n");
  }

  print("\n--- 3. Daily Ratio Changes (BRL) ---");
  for (int i = 0; i < brlChanges.length; i++) {
    print("Change from ${btcBrlRates[i].toString().padRight(15)} to ${btcBrlRates[i+1].toString().padRight(15)}: ${brlChanges[i].toStringAsFixed(2)}\n");
  }

  print("\n=============================================");
  print("        Average Ratio Changes (30 Days)      ");
  print("=============================================\n");

  print("Average BTC/USD Change over period: ${avgUsdChange.toStringAsFixed(2)}");
  print("Average BTC/EUR Change over period: ${avgEurChange.toStringAsFixed(2)}");
  print("Average BTC/BRL Change over period: ${avgBrlChange.toStringAsFixed(2)}\n");

  // Deviation Calculation (Comparing the final rate to the initial rate)
  print("--- 4. Final Rate Deviation (vs Start Date: 2026-03-23) ---");
  final startDateUsd = btcUsdRates[0];
  final endDateUsd = btcUsdRates.last;

  print("BTC/EUR: Started at ${btcEurRates[0].toStringAsFixed(2)}, Ended at ${btcEurRates.last.toStringAsFixed(2)}. Net Change: ${(btcEurRates.last - btcEurRates[0]).toStringAsFixed(2)}");
  print("BTC/EUR: Started at ${btcEurRates[0].toStringAsFixed(2)}, Ended at ${btcEurRates.last.toStringAsFixed(2)}. Net Change: ${(btcEurRates.last - btcEurRates[0]).toStringAsFixed(2)}");
  print("BTC/BRL: Started at ${btcBrlRates[0].toStringAsFixed(2)}, Ended at ${btcBrlRates.last.toStringAsFixed(2)}. Net Change: ${(btcBrlRates.last - btcBrlRates[0]).toStringAsFixed(2)}");
  
}

        ]]>
    </source>
    <call function="main">
        []
    </call>
    <output>
[
  "=============================================",
  "        BTC Daily Ratio Change Analysis       ",
  "=============================================\n",
  "--- 1. Daily Ratio Changes (USD) ---",
  "Change from 71428.571429    to 71428.571429   : 0.00\n",
  "Change from 71428.571429    to 71428.571429   : 0.00\n",
  "Change from 71428.571429    to 66666.666667   : -4761.90\n",
  "Change from 66666.666667    to 66666.666667   : 0.00\n",
  "Change from 66666.666667    to 66666.666667   : 0.00\n",
  "Change from 66666.666667    to 66666.666667   : 0.00\n",
  "Change from 66666.666667    to 66666.666667   : 0.00\n",
  "Change from 66666.666667    to 66666.666667   : 0.00\n",
  "Change from 66666.666667    to 66666.666667   : 0.00\n",
  "Change from 66666.666667    to 66666.666667   : 0.00\n",
  "Change from 66666.666667    to 66666.666667   : 0.00\n",
  "Change from 66666.666667    to 66666.666667   : 0.00\n",
  "Change from 66666.666667    to 66666.666667   : 0.00\n",
  "Change from 66666.666667    to 66666.666667   : 0.00\n",
  "Change from 66666.666667    to 71428.571429   : 4761.90\n",
  "Change from 71428.571429    to 71428.571429   : 0.00\n",
  "Change from 71428.571429    to 71428.571429   : 0.00\n",
  "Change from 71428.571429    to 71428.571429   : 0.00\n",
  "Change from 71428.571429    to 71428.571429   : 0.00\n",
  "Change from 71428.571429    to 71428.571429   : 0.00\n",
  "Change from 71428.571429    to 76923.076923   : 5494.51\n",
  "Change from 76923.076923    to 76923.076923   : 0.00\n",
  "Change from 76923.076923    to 76923.076923   : 0.00\n",
  "Change from 76923.076923    to 76923.076923   : 0.00\n",
  "Change from 76923.076923    to 76923.076923   : 0.00\n",
  "Change from 76923.076923    to 76923.076923   : 0.00\n",
  "Change from 76923.076923    to 71428.571429   : -5494.51\n",
  "Change from 71428.571429    to 76923.076923   : 5494.51\n",
  "Change from 76923.076923    to 76923.076923   : 0.00\n",
  "Change from 76923.076923    to 76923.076923   : 0.00\n",
  "\n--- 2. Daily Ratio Changes (EUR) ---",
  "Change from 61667.5         to 61559.428571   : -108.07\n",
  "Change from 61559.428571    to 61746.285714   : 186.86\n",
  "Change from 61746.285714    to 57778.4        : -3967.89\n",
  "Change from 57778.4         to 57743.266667   : -35.13\n",
  "Change from 57743.266667    to 57774.066667   : 30.80\n",
  "Change from 57774.066667    to 58014.6        : 240.53\n",
  "Change from 58014.6         to 58194.466667   : 179.87\n",
  "Change from 58194.466667    to 57636.866667   : -557.60\n",
  "Change from 57636.866667    to 57511.466667   : -125.40\n",
  "Change from 57511.466667    to 57757.666667   : 246.20\n",
  "Change from 57757.666667    to 57873.466667   : 115.80\n",
  "Change from 57873.466667    to 57874.533333   : 1.07\n",
  "Change from 57874.533333    to 57919.4        : 44.87\n",
  "Change from 57919.4         to 57766.533333   : -152.87\n",
  "Change from 57766.533333    to 61151.785714   : 3385.25\n",
  "Change from 61151.785714    to 61260.357143   : 108.57\n",
  "Change from 61260.357143    to 61081.928571   : -178.43\n",
  "Change from 61081.928571    to 60923.5        : -158.43\n",
  "Change from 60923.5         to 60920.928571   : -2.57\n",
  "Change from 60920.928571    to 61199.428571   : 278.50\n",
  "Change from 61199.428571    to 65381.0        : 4181.57\n",
  "Change from 65381.0         to 65198.769231   : -182.23\n",
  "Change from 65198.769231    to 65156.538462   : -42.23\n",
  "Change from 65156.538462    to 65273.384615   : 116.85\n",
  "Change from 65273.384615    to 65240.0        : -33.38\n",
  "Change from 65240.0         to 65339.769231   : 99.77\n",
  "Change from 65339.769231    to 60828.571429   : -4511.20\n",
  "Change from 60828.571429    to 65277.461538   : 4448.89\n",
  "Change from 65277.461538    to 65516.538462   : 239.08\n",
  "Change from 65516.538462    to 65711.538462   : 195.00\n",
  "\n--- 3. Daily Ratio Changes (BRL) ---",
  "Change from 373796.642857   to 373876.214286  : 79.57\n",
  "Change from 373876.214286   to 374064.214286  : 188.00\n",
  "Change from 374064.214286   to 349252.066667  : -24812.15\n",
  "Change from 349252.066667   to 349463.4       : 211.33\n",
  "Change from 349463.4        to 349458.8       : -4.60\n",
  "Change from 349458.8        to 349274.0       : -184.80\n",
  "Change from 349274.0        to 350766.733333  : 1492.73\n",
  "Change from 350766.733333   to 346151.533333  : -4615.20\n",
  "Change from 346151.533333   to 343726.666667  : -2424.87\n",
  "Change from 343726.666667   to 343902.2       : 175.53\n",
  "Change from 343902.2        to 343910.2       : 8.00\n",
  "Change from 343910.2        to 344840.266667  : 930.07\n",
  "Change from 344840.266667   to 343923.066667  : -917.20\n",
  "Change from 343923.066667   to 342827.666667  : -1095.40\n",
  "Change from 342827.666667   to 368091.0       : 25263.33\n",
  "Change from 368091.0        to 364361.857143  : -3729.14\n",
  "Change from 364361.857143   to 363221.357143  : -1140.50\n",
  "Change from 363221.357143   to 357680.214286  : -5541.14\n",
  "Change from 357680.214286   to 357534.214286  : -146.00\n",
  "Change from 357534.214286   to 357649.857143  : 115.64\n",
  "Change from 357649.857143   to 384353.846154  : 26703.99\n",
  "Change from 384353.846154   to 383614.076923  : -739.77\n",
  "Change from 383614.076923   to 384123.692308  : 509.62\n",
  "Change from 384123.692308   to 383965.461538  : -158.23\n",
  "Change from 383965.461538   to 382975.615385  : -989.85\n",
  "Change from 382975.615385   to 383204.153846  : 228.54\n",
  "Change from 383204.153846   to 356644.428571  : -26559.73\n",
  "Change from 356644.428571   to 381191.230769  : 24546.80\n",
  "Change from 381191.230769   to 384182.846154  : 2991.62\n",
  "Change from 384182.846154   to 382959.923077  : -1222.92\n",
  "\n=============================================",
  "        Average Ratio Changes (30 Days)      ",
  "=============================================\n",
  "Average BTC/USD Change over period: 183.15",
  "Average BTC/EUR Change over period: 134.80",
  "Average BTC/BRL Change over period: 305.44\n",
  "--- 4. Final Rate Deviation (vs Start Date: 2026-03-23) ---",
  "BTC/EUR: Started at 61667.50, Ended at 65711.54. Net Change: 4044.04",
  "BTC/EUR: Started at 61667.50, Ended at 65711.54. Net Change: 4044.04",
  "BTC/BRL: Started at 373796.64, Ended at 382959.92. Net Change: 9163.28"
]
    </output>
    <source-generated language="dart"><![CDATA[<<<< [SOURCES_BEGIN] >>>>
<<<< NAMESPACE="" >>>>
<<<< CODE_UNIT_START="/test" >>>>
  void main() {
    List<double> btcUsdRates = <double>[71428.571429, 71428.571429, 71428.571429, 66666.666667, 66666.666667, 66666.666667, 66666.666667, 66666.666667, 66666.666667, 66666.666667, 66666.666667, 66666.666667, 66666.666667, 66666.666667, 66666.666667, 71428.571429, 71428.571429, 71428.571429, 71428.571429, 71428.571429, 71428.571429, 76923.076923, 76923.076923, 76923.076923, 76923.076923, 76923.076923, 76923.076923, 71428.571429, 76923.076923, 76923.076923, 76923.076923];
    List<double> btcEurRates = <double>[61667.5, 61559.428571, 61746.285714, 57778.4, 57743.266667, 57774.066667, 58014.6, 58194.466667, 57636.866667, 57511.466667, 57757.666667, 57873.466667, 57874.533333, 57919.4, 57766.533333, 61151.785714, 61260.357143, 61081.928571, 60923.5, 60920.928571, 61199.428571, 65381.0, 65198.769231, 65156.538462, 65273.384615, 65240.0, 65339.769231, 60828.571429, 65277.461538, 65516.538462, 65711.538462];
    List<double> btcBrlRates = <double>[373796.642857, 373876.214286, 374064.214286, 349252.066667, 349463.4, 349458.8, 349274.0, 350766.733333, 346151.533333, 343726.666667, 343902.2, 343910.2, 344840.266667, 343923.066667, 342827.666667, 368091.0, 364361.857143, 363221.357143, 357680.214286, 357534.214286, 357649.857143, 384353.846154, 383614.076923, 384123.692308, 383965.461538, 382975.615385, 383204.153846, 356644.428571, 381191.230769, 384182.846154, 382959.923077];
    List<double> usdChanges = <double>[];
    List<double> eurChanges = <double>[];
    List<double> brlChanges = <double>[];
    for (int i = 1; i < btcUsdRates.length ; i++) {
      usdChanges.add(btcUsdRates[i] - btcUsdRates[i - 1]);
      eurChanges.add(btcEurRates[i] - btcEurRates[i - 1]);
      brlChanges.add(btcBrlRates[i] - btcBrlRates[i - 1]);
    }
    double avgUsdChange = 0.0;
    double avgEurChange = 0.0;
    double avgBrlChange = 0.0;
    for (var change in usdChanges) {
      avgUsdChange += change;
    }
    if (usdChanges.isNotEmpty) {
        avgUsdChange = avgUsdChange / usdChanges.length;
    }

    for (var change in eurChanges) {
      avgEurChange += change;
    }
    if (eurChanges.isNotEmpty) {
        avgEurChange = avgEurChange / eurChanges.length;
    }

    for (var change in brlChanges) {
      avgBrlChange += change;
    }
    if (brlChanges.isNotEmpty) {
        avgBrlChange = avgBrlChange / brlChanges.length;
    }

    print('=============================================');
    print('        BTC Daily Ratio Change Analysis       ');
    print('=============================================\n');
    print('--- 1. Daily Ratio Changes (USD) ---');
    for (int i = 0; i < usdChanges.length ; i++) {
      print('Change from ${btcUsdRates[i].toString().padRight(15)} to ${btcUsdRates[i + 1].toString().padRight(15)}: ${usdChanges[i].toStringAsFixed(2)}\n');
    }
    print('\n--- 2. Daily Ratio Changes (EUR) ---');
    for (int i = 0; i < eurChanges.length ; i++) {
      print('Change from ${btcEurRates[i].toString().padRight(15)} to ${btcEurRates[i + 1].toString().padRight(15)}: ${eurChanges[i].toStringAsFixed(2)}\n');
    }
    print('\n--- 3. Daily Ratio Changes (BRL) ---');
    for (int i = 0; i < brlChanges.length ; i++) {
      print('Change from ${btcBrlRates[i].toString().padRight(15)} to ${btcBrlRates[i + 1].toString().padRight(15)}: ${brlChanges[i].toStringAsFixed(2)}\n');
    }
    print('\n=============================================');
    print('        Average Ratio Changes (30 Days)      ');
    print('=============================================\n');
    print('Average BTC/USD Change over period: ${avgUsdChange.toStringAsFixed(2)}');
    print('Average BTC/EUR Change over period: ${avgEurChange.toStringAsFixed(2)}');
    print('Average BTC/BRL Change over period: ${avgBrlChange.toStringAsFixed(2)}\n');
    print('--- 4. Final Rate Deviation (vs Start Date: 2026-03-23) ---');
    final startDateUsd = btcUsdRates[0];
    final endDateUsd = btcUsdRates.last;
    print('BTC/EUR: Started at ${btcEurRates[0].toStringAsFixed(2)}, Ended at ${btcEurRates.last.toStringAsFixed(2)}. Net Change: ${(btcEurRates.last - btcEurRates[0]).toStringAsFixed(2)}');
    print('BTC/EUR: Started at ${btcEurRates[0].toStringAsFixed(2)}, Ended at ${btcEurRates.last.toStringAsFixed(2)}. Net Change: ${(btcEurRates.last - btcEurRates[0]).toStringAsFixed(2)}');
    print('BTC/BRL: Started at ${btcBrlRates[0].toStringAsFixed(2)}, Ended at ${btcBrlRates.last.toStringAsFixed(2)}. Net Change: ${(btcBrlRates.last - btcBrlRates[0]).toStringAsFixed(2)}');
  }

<<<< CODE_UNIT_END="/test" >>>>
<<<< [SOURCES_END] >>>>
]]></source-generated>
</test>
    '''),
    TestDefinition('dart_basic_exchange_rates.test.xml', r'''
<?xml version="1.0" encoding="UTF-8"?>
<test title="Basic main()">
    <source language="dart">
        <![CDATA[

 void main() {
  // --- Populated Data from FX Calls (BTC Rates for 31 Days: March 23 to April 22, 2026) ---

  // BTC/USD Rates (Index corresponds to the date)
  List<double> btcUsdRates = [
    71428.571429, // 2026-03-23
    71428.571429, // 2026-03-24
    71428.571429, // 2026-03-25
    66666.666667, // 2026-03-26
    66666.666667, // 2026-03-27
    66666.666667, // 2026-03-28
    66666.666667, // 2026-03-29
    66666.666667, // 2026-03-30
    66666.666667, // 2026-03-31
    66666.666667, // 2026-04-01
    66666.666667, // 2026-04-02
    66666.666667, // 2026-04-03
    66666.666667, // 2026-04-04
    66666.666667, // 2026-04-05
    66666.666667, // 2026-04-06
    71428.571429, // 2026-04-07
    71428.571429, // 2026-04-08
    71428.571429, // 2026-04-09
    71428.571429, // 2026-04-10
    71428.571429, // 2026-04-11
    71428.571429, // 2026-04-12
    76923.076923, // 2026-04-13
    76923.076923, // 2026-04-14
    76923.076923, // 2026-04-15
    76923.076923, // 2026-04-16
    76923.076923, // 2026-04-17
    76923.076923, // 2026-04-18
    71428.571429, // 2026-04-19
    76923.076923, // 2026-04-20
    76923.076923, // 2026-04-21
    76923.076923, // 2026-04-22
  ];

  // BTC/EUR Rates (Index corresponds to the date)
  List<double> btcEurRates = [
    61667.50, // 2026-03-23
    61559.428571, // 2026-03-24
    61746.285714, // 2026-03-25
    57778.40, // 2026-03-26
    57743.266667, // 2026-03-27
    57774.066667, // 2026-03-28
    58014.60, // 2026-03-29
    58194.466667, // 2026-03-30
    57636.866667, // 2026-03-31
    57511.466667, // 2026-04-01
    57757.666667, // 2026-04-02
    57873.466667, // 2026-04-03
    57874.533333, // 2026-04-04
    57919.40, // 2026-04-05
    57766.533333, // 2026-04-06
    61151.785714, // 2026-04-07
    61260.357143, // 2026-04-08
    61081.928571, // 2026-04-09
    60923.50, // 2026-04-10
    60920.928571, // 2026-04-11
    61199.428571, // 2026-04-12
    65381.00, // 2026-04-13
    65198.769231, // 2026-04-14
    65156.538462, // 2026-04-15
    65273.384615, // 2026-04-16
    65240.00, // 2026-04-17
    65339.769231, // 2026-04-18
    60828.571429, // 2026-04-19
    65277.461538, // 2026-04-20
    65516.538462, // 2026-04-21
    65711.538462, // 2026-04-22
  ];

  // BTC/BRL Rates (Index corresponds to the date)
  List<double> btcBrlRates = [
    373796.642857, // 2026-03-23
    373876.214286, // 2026-03-24
    374064.214286, // 2026-03-25
    349252.066667, // 2026-03-26
    349463.4, // 2026-03-27
    349458.8, // 2026-03-28
    349274.0, // 2026-03-29
    350766.733333, // 2026-03-30
    346151.533333, // 2026-03-31
    343726.666667, // 2026-04-01
    343902.2, // 2026-04-02
    343910.2, // 2026-04-03
    344840.266667, // 2026-04-04
    343923.066667, // 2026-04-05
    342827.666667, // 2026-04-06
    368091.0, // 2026-04-07
    364361.857143, // 2026-04-08
    363221.357143, // 2026-04-09
    357680.214286, // 2026-04-10
    357534.214286, // 2026-04-11
    357649.857143, // 2026-04-12
    384353.846154, // 2026-04-13
    383614.076923, // 2026-04-14
    384123.692308, // 2026-04-15
    383965.461538, // 2026-04-16
    382975.615385, // 2026-04-17
    383204.153846, // 2026-04-18
    356644.428571, // 2026-04-19
    381191.230769, // 2026-04-20
    384182.846154, // 2026-04-21
    382959.923077, // 2026-04-22
  ];

  // --- Calculations ---
  List<double> usdChanges = [];
  List<double> eurChanges = [];
  List<double> brlChanges = [];

  for (int i = 1; i < btcUsdRates.length; i++) {
    usdChanges.add(btcUsdRates[i] - btcUsdRates[i - 1]);
    eurChanges.add(btcEurRates[i] - btcEurRates[i - 1]);
    brlChanges.add(btcBrlRates[i] - btcBrlRates[i - 1]);
  }

  // Calculate Averages
  double avgUsdChange = 0.0;
  double avgEurChange = 0.0;
  double avgBrlChange = 0.0;

  for (double change in usdChanges) {
    avgUsdChange += change;
  }
  if (usdChanges.isNotEmpty) {
    avgUsdChange = avgUsdChange / usdChanges.length;
  }

  for (double change in eurChanges) {
    avgEurChange += change;
  }
  if (eurChanges.isNotEmpty) {
    avgEurChange = avgEurChange / eurChanges.length;
  }

  for (double change in brlChanges) {
    avgBrlChange += change;
  }
  if (brlChanges.isNotEmpty) {
    avgBrlChange = avgBrlChange / brlChanges.length;
  }


  // --- Display Results ---
  print("=============================================");
  print("        BTC Daily Ratio Change Analysis       ");
  print("=============================================\n");

  print("--- 1. Daily Ratio Changes (USD) ---");
  for (int i = 0; i < usdChanges.length; i++) {
    // The change is calculated between day i and day i+1 in the original data structure,
    // but here we are showing the change *from* day i to day i+1 based on how the loop ran.
    print("Change from ${btcUsdRates[i].toString().padRight(15)} to ${btcUsdRates[i+1].toString().padRight(15)}: ${usdChanges[i].toStringAsFixed(2)}\n");
  }

  print("\n--- 2. Daily Ratio Changes (EUR) ---");
  for (int i = 0; i < eurChanges.length; i++) {
    //print("Change from ${btcEurRates[i].toString().padRight(15)} to ${btcEurRates[i+1].toString().padRight(15)}: ${eurChanges[i].toStringAsFixed(2)}\n");
  }

  print("\n--- 3. Daily Ratio Changes (BRL) ---");
  for (int i = 0; i < brlChanges.length; i++) {
    //print("Change from ${btcBrlRates[i].toString().padRight(15)} to ${btcBrlRates[i+1].toString().padRight(15)}: ${brlChanges[i].toStringAsFixed(2)}\n");
  }

  print("\n=============================================");
  print("        Average Ratio Changes (30 Days)      ");
  print("=============================================\n");

  print("Average BTC/USD Change over period: ${avgUsdChange.toStringAsFixed(2)}");
  print("Average BTC/EUR Change over period: ${avgEurChange.toStringAsFixed(2)}");
  print("Average BTC/BRL Change over period: ${avgBrlChange.toStringAsFixed(2)}\n");
 
}

        ]]>
    </source>
    <call function="main">
        []
    </call>
    <output>
[
  "=============================================",
  "        BTC Daily Ratio Change Analysis       ",
  "=============================================\n",
  "--- 1. Daily Ratio Changes (USD) ---",
  "Change from 71428.571429    to 71428.571429   : 0.00\n",
  "Change from 71428.571429    to 71428.571429   : 0.00\n",
  "Change from 71428.571429    to 66666.666667   : -4761.90\n",
  "Change from 66666.666667    to 66666.666667   : 0.00\n",
  "Change from 66666.666667    to 66666.666667   : 0.00\n",
  "Change from 66666.666667    to 66666.666667   : 0.00\n",
  "Change from 66666.666667    to 66666.666667   : 0.00\n",
  "Change from 66666.666667    to 66666.666667   : 0.00\n",
  "Change from 66666.666667    to 66666.666667   : 0.00\n",
  "Change from 66666.666667    to 66666.666667   : 0.00\n",
  "Change from 66666.666667    to 66666.666667   : 0.00\n",
  "Change from 66666.666667    to 66666.666667   : 0.00\n",
  "Change from 66666.666667    to 66666.666667   : 0.00\n",
  "Change from 66666.666667    to 66666.666667   : 0.00\n",
  "Change from 66666.666667    to 71428.571429   : 4761.90\n",
  "Change from 71428.571429    to 71428.571429   : 0.00\n",
  "Change from 71428.571429    to 71428.571429   : 0.00\n",
  "Change from 71428.571429    to 71428.571429   : 0.00\n",
  "Change from 71428.571429    to 71428.571429   : 0.00\n",
  "Change from 71428.571429    to 71428.571429   : 0.00\n",
  "Change from 71428.571429    to 76923.076923   : 5494.51\n",
  "Change from 76923.076923    to 76923.076923   : 0.00\n",
  "Change from 76923.076923    to 76923.076923   : 0.00\n",
  "Change from 76923.076923    to 76923.076923   : 0.00\n",
  "Change from 76923.076923    to 76923.076923   : 0.00\n",
  "Change from 76923.076923    to 76923.076923   : 0.00\n",
  "Change from 76923.076923    to 71428.571429   : -5494.51\n",
  "Change from 71428.571429    to 76923.076923   : 5494.51\n",
  "Change from 76923.076923    to 76923.076923   : 0.00\n",
  "Change from 76923.076923    to 76923.076923   : 0.00\n",
  "\n--- 2. Daily Ratio Changes (EUR) ---",
  "\n--- 3. Daily Ratio Changes (BRL) ---",
  "\n=============================================",
  "        Average Ratio Changes (30 Days)      ",
  "=============================================\n",
  "Average BTC/USD Change over period: 183.15",
  "Average BTC/EUR Change over period: 134.80",
  "Average BTC/BRL Change over period: 305.44\n"
]

    </output>
    <source-generated language="dart"><![CDATA[<<<< [SOURCES_BEGIN] >>>>
<<<< NAMESPACE="" >>>>
<<<< CODE_UNIT_START="/test" >>>>
  void main() {
    List<double> btcUsdRates = <double>[71428.571429, 71428.571429, 71428.571429, 66666.666667, 66666.666667, 66666.666667, 66666.666667, 66666.666667, 66666.666667, 66666.666667, 66666.666667, 66666.666667, 66666.666667, 66666.666667, 66666.666667, 71428.571429, 71428.571429, 71428.571429, 71428.571429, 71428.571429, 71428.571429, 76923.076923, 76923.076923, 76923.076923, 76923.076923, 76923.076923, 76923.076923, 71428.571429, 76923.076923, 76923.076923, 76923.076923];
    List<double> btcEurRates = <double>[61667.5, 61559.428571, 61746.285714, 57778.4, 57743.266667, 57774.066667, 58014.6, 58194.466667, 57636.866667, 57511.466667, 57757.666667, 57873.466667, 57874.533333, 57919.4, 57766.533333, 61151.785714, 61260.357143, 61081.928571, 60923.5, 60920.928571, 61199.428571, 65381.0, 65198.769231, 65156.538462, 65273.384615, 65240.0, 65339.769231, 60828.571429, 65277.461538, 65516.538462, 65711.538462];
    List<double> btcBrlRates = <double>[373796.642857, 373876.214286, 374064.214286, 349252.066667, 349463.4, 349458.8, 349274.0, 350766.733333, 346151.533333, 343726.666667, 343902.2, 343910.2, 344840.266667, 343923.066667, 342827.666667, 368091.0, 364361.857143, 363221.357143, 357680.214286, 357534.214286, 357649.857143, 384353.846154, 383614.076923, 384123.692308, 383965.461538, 382975.615385, 383204.153846, 356644.428571, 381191.230769, 384182.846154, 382959.923077];
    List<double> usdChanges = <double>[];
    List<double> eurChanges = <double>[];
    List<double> brlChanges = <double>[];
    for (int i = 1; i < btcUsdRates.length ; i++) {
      usdChanges.add(btcUsdRates[i] - btcUsdRates[i - 1]);
      eurChanges.add(btcEurRates[i] - btcEurRates[i - 1]);
      brlChanges.add(btcBrlRates[i] - btcBrlRates[i - 1]);
    }
    double avgUsdChange = 0.0;
    double avgEurChange = 0.0;
    double avgBrlChange = 0.0;
    for (var change in usdChanges) {
      avgUsdChange += change;
    }
    if (usdChanges.isNotEmpty) {
        avgUsdChange = avgUsdChange / usdChanges.length;
    }

    for (var change in eurChanges) {
      avgEurChange += change;
    }
    if (eurChanges.isNotEmpty) {
        avgEurChange = avgEurChange / eurChanges.length;
    }

    for (var change in brlChanges) {
      avgBrlChange += change;
    }
    if (brlChanges.isNotEmpty) {
        avgBrlChange = avgBrlChange / brlChanges.length;
    }

    print('=============================================');
    print('        BTC Daily Ratio Change Analysis       ');
    print('=============================================\n');
    print('--- 1. Daily Ratio Changes (USD) ---');
    for (int i = 0; i < usdChanges.length ; i++) {
      print('Change from ${btcUsdRates[i].toString().padRight(15)} to ${btcUsdRates[i + 1].toString().padRight(15)}: ${usdChanges[i].toStringAsFixed(2)}\n');
    }
    print('\n--- 2. Daily Ratio Changes (EUR) ---');
    for (int i = 0; i < eurChanges.length ; i++) {
    }
    print('\n--- 3. Daily Ratio Changes (BRL) ---');
    for (int i = 0; i < brlChanges.length ; i++) {
    }
    print('\n=============================================');
    print('        Average Ratio Changes (30 Days)      ');
    print('=============================================\n');
    print('Average BTC/USD Change over period: ${avgUsdChange.toStringAsFixed(2)}');
    print('Average BTC/EUR Change over period: ${avgEurChange.toStringAsFixed(2)}');
    print('Average BTC/BRL Change over period: ${avgBrlChange.toStringAsFixed(2)}\n');
  }

<<<< CODE_UNIT_END="/test" >>>>
<<<< [SOURCES_END] >>>>
]]></source-generated>
</test>
    '''),
    TestDefinition('dart_basic_exchange_rates.test.xml', r'''
<?xml version="1.0" encoding="UTF-8"?>
<test title="Basic main()">
    <source language="dart">
        <![CDATA[

void main() {

  var d = 1.1;
  
  var s = d.toString();
  
  print('[$s]');
  print('s: '+ s.toString());

  var l = [2.2,3.3];
  print('[$l]');
  print('l: ' + l.toString());
}

        ]]>
    </source>
    <call function="main">
        []
    </call>
    <output>
[
"[1.1]",
"s: 1.1",
"[[2.2, 3.3]]",
"l: [2.2, 3.3]"
]
    </output>
    <source-generated language="dart"><![CDATA[<<<< [SOURCES_BEGIN] >>>>
<<<< NAMESPACE="" >>>>
<<<< CODE_UNIT_START="/test" >>>>
  void main() {
    var d = 1.1;
    var s = d.toString();
    print('[$s]');
    print('s: ' + s.toString());
    var l = <double>[2.2, 3.3];
    print('[$l]');
    print('l: ' + l.toString());
  }

<<<< CODE_UNIT_END="/test" >>>>
<<<< [SOURCES_END] >>>>
]]></source-generated>
</test>
    '''),
    TestDefinition('dart_basic_exchange_rates.test.xml', r'''
<?xml version="1.0" encoding="UTF-8"?>
<test title="Basic main()">
    <source language="dart">
        <![CDATA[

import 'dart:math';

// --- DADOS HISTÓRICOS (SUBSTITUA ESTES VALORES PELOS RESULTADOS REAIS DAS SUAS CONSULTAS) ---
List<double> usdData = [
  66666.67, 71428.57, 71428.57, 71428.57, 66666.67, 66666.67, 66666.67,
  66666.67, 66666.67, 66666.67, 66666.67, 66666.67, 66666.67, 66666.67,
  66666.67, 66666.67, 71428.57, 71428.57, 71428.57, 76923.08, 76923.08,
  76923.08
];

List<double> eurData = [
  57723.80, 61667.50, 61559.43, 61746.29, 57778.40, 57743.27, 57774.07,
  58014.60, 58194.47, 57636.87, 57511.47, 57757.67, 57873.47, 57874.53,
  57919.40, 57766.53, 61151.79, 61260.36, 61081.93, 60923.50, 60920.93,
  61199.43, 65381.00, 65198.77, 65156.54, 65273.38, 65240.00, 65339.77,
  60828.57, 65277.46, 65567.38
];

List<double> brlData = [
  354906.93, 373796.64, 373876.21, 374064.21, 349252.07, 349463.40,
  349458.80, 349274.00, 350766.73, 346151.53, 343726.67, 343902.20,
  343910.20, 344840.27, 343923.07, 342827.67, 368091.00, 364361.86,
  363221.36, 357680.21, 357534.21, 357649.86, 384353.85, 383614.08,
  384123.69, 383965.46, 382975.62, 383204.15, 356644.43, 381191.23,
  383085.31
];

// --- FUNÇÕES AUXILIARES ---

double calculateChange(List<double> data) {
  if (data.length < 2) return 0.0;
  double startValue = data[0];
  double endValue = data[data.length - 1];
  return ((endValue / startValue) - 1.0) * 100.0;
}

double calculateAverage(List<double> data) {
  double sum = 0.0;
  for (var v in data) {
    sum += v;
  }
  return sum / data.length;
}

void main() {
  print("=========================================================");
  print("ANÁLISE DE Variação e Desvio (30 Dias)");
  print("=========================================================\n");

  double usdChange = calculateChange(usdData);
  double eurChange = calculateChange(eurData);
  double brlChange = calculateChange(brlData);

  print("--- Variação Percentual (Início vs Fim do Período) ---");
  print("BTC/USD: ${usdChange.toStringAsFixed(2)}%");
  print("BTC/EUR: ${eurChange.toStringAsFixed(2)}%");
  print("BTC/BRL: ${brlChange.toStringAsFixed(2)}%");
  print("\n---------------------------------------------------------\n");

  double avgUsd = calculateAverage(usdData);
  double avgEur = calculateAverage(eurData);
  double avgBrl = calculateAverage(brlData);

  print("--- Médias das Oscilações no Período ---");
  print("Média USD: ${avgUsd.toStringAsFixed(2)}");
  print("Média EUR: ${avgEur.toStringAsFixed(2)}");
  print("Média BRL: ${avgBrl.toStringAsFixed(2)}");
  print("\n---------------------------------------------------------\n");

  print("--- Desvio em Relação à Média das Outras Moedas ---");

  double avgEurBrl = (avgEur + avgBrl) / 2.0;
  double usdDeviation = usdChange - avgEurBrl;
  print("Desvio USD vs (EUR+BRL): ${usdDeviation.toStringAsFixed(2)}%");

  double avgUsdBrl = (avgUsd + avgBrl) / 2.0;
  double eurDeviation = eurChange - avgUsdBrl;
  print("Desvio EUR vs (USD+BRL): ${eurDeviation.toStringAsFixed(2)}%");

  double avgUsdEur = (avgUsd + avgEur) / 2.0;
  double brlDeviation = brlChange - avgUsdEur;
  print("Desvio BRL vs (USD+EUR): ${brlDeviation.toStringAsFixed(2)}%");
}
        ]]>
    </source>
    <call function="main">
        []
    </call>
    <output>
[
  "=========================================================",
  "ANÁLISE DE Variação e Desvio (30 Dias)",
  "=========================================================\n",
  "--- Variação Percentual (Início vs Fim do Período) ---",
  "BTC/USD: 15.38%",
  "BTC/EUR: 13.59%",
  "BTC/BRL: 7.94%",
  "\n---------------------------------------------------------\n",
  "--- Médias das Oscilações no Período ---",
  "Média USD: 69363.97",
  "Média EUR: 60849.76",
  "Média BRL: 362123.77",
  "\n---------------------------------------------------------\n",
  "--- Desvio em Relação à Média das Outras Moedas ---",
  "Desvio USD vs (EUR+BRL): -211471.38%",
  "Desvio EUR vs (USD+BRL): -215730.28%",
  "Desvio BRL vs (USD+EUR): -65098.93%"
]
    </output>
    <source-generated language="dart"><![CDATA[<<<< [SOURCES_BEGIN] >>>>
<<<< NAMESPACE="" >>>>
<<<< CODE_UNIT_START="/test" >>>>
import 'dart:math';

  double calculateChange(List<double> data) {
    if (data.length < 2) return 0.0;

    double startValue = data[0];
    double endValue = data[data.length - 1];
    return ((endValue / startValue) - 1.0) * 100.0;
  }

  double calculateAverage(List<double> data) {
    double sum = 0.0;
    for (var v in data) {
      sum += v;
    }
    return sum / data.length;
  }

  void main() {
    print('=========================================================');
    print('ANÁLISE DE Variação e Desvio (30 Dias)');
    print('=========================================================\n');
    double usdChange = calculateChange(usdData);
    double eurChange = calculateChange(eurData);
    double brlChange = calculateChange(brlData);
    print('--- Variação Percentual (Início vs Fim do Período) ---');
    print('BTC/USD: ${usdChange.toStringAsFixed(2)}%');
    print('BTC/EUR: ${eurChange.toStringAsFixed(2)}%');
    print('BTC/BRL: ${brlChange.toStringAsFixed(2)}%');
    print('\n---------------------------------------------------------\n');
    double avgUsd = calculateAverage(usdData);
    double avgEur = calculateAverage(eurData);
    double avgBrl = calculateAverage(brlData);
    print('--- Médias das Oscilações no Período ---');
    print('Média USD: ${avgUsd.toStringAsFixed(2)}');
    print('Média EUR: ${avgEur.toStringAsFixed(2)}');
    print('Média BRL: ${avgBrl.toStringAsFixed(2)}');
    print('\n---------------------------------------------------------\n');
    print('--- Desvio em Relação à Média das Outras Moedas ---');
    double avgEurBrl = (avgEur + avgBrl) / 2.0;
    double usdDeviation = usdChange - avgEurBrl;
    print('Desvio USD vs (EUR+BRL): ${usdDeviation.toStringAsFixed(2)}%');
    double avgUsdBrl = (avgUsd + avgBrl) / 2.0;
    double eurDeviation = eurChange - avgUsdBrl;
    print('Desvio EUR vs (USD+BRL): ${eurDeviation.toStringAsFixed(2)}%');
    double avgUsdEur = (avgUsd + avgEur) / 2.0;
    double brlDeviation = brlChange - avgUsdEur;
    print('Desvio BRL vs (USD+EUR): ${brlDeviation.toStringAsFixed(2)}%');
  }

  List<double> usdData = <double>[66666.67, 71428.57, 71428.57, 71428.57, 66666.67, 66666.67, 66666.67, 66666.67, 66666.67, 66666.67, 66666.67, 66666.67, 66666.67, 66666.67, 66666.67, 66666.67, 71428.57, 71428.57, 71428.57, 76923.08, 76923.08, 76923.08];
  List<double> eurData = <double>[57723.8, 61667.5, 61559.43, 61746.29, 57778.4, 57743.27, 57774.07, 58014.6, 58194.47, 57636.87, 57511.47, 57757.67, 57873.47, 57874.53, 57919.4, 57766.53, 61151.79, 61260.36, 61081.93, 60923.5, 60920.93, 61199.43, 65381.0, 65198.77, 65156.54, 65273.38, 65240.0, 65339.77, 60828.57, 65277.46, 65567.38];
  List<double> brlData = <double>[354906.93, 373796.64, 373876.21, 374064.21, 349252.07, 349463.4, 349458.8, 349274.0, 350766.73, 346151.53, 343726.67, 343902.2, 343910.2, 344840.27, 343923.07, 342827.67, 368091.0, 364361.86, 363221.36, 357680.21, 357534.21, 357649.86, 384353.85, 383614.08, 384123.69, 383965.46, 382975.62, 383204.15, 356644.43, 381191.23, 383085.31];
<<<< CODE_UNIT_END="/test" >>>>
<<<< [SOURCES_END] >>>>
]]></source-generated>
</test>
    '''),
    TestDefinition('dart_basic_exchange_rates.test.xml', r'''
<?xml version="1.0" encoding="UTF-8"?>
<test title="Basic main()">
    <source language="dart">
        <![CDATA[
import 'dart:math';

// --- DADOS HISTÓRICOS (SUBSTITUA ESTES VALORES PELOS RESULTADOS REAIS DAS SUAS CONSULTAS) ---

// Exemplo de estrutura de dados. Você deve preencher com os dados reais do período 2026-03-22 a 2026-04-21
List<double> usdData = [66666.67, 71428.57, 71428.57, 71428.57, 66666.67, 66666.67, 66666.67, 66666.67, 66666.67, 66666.67, 66666.67, 66666.67, 66666.67, 66666.67, 66666.67, 66666.67, 71428.57, 71428.57, 71428.57, 76923.08, 76923.08, 76923.08];
List<double> eurData = [57723.80, 61667.50, 61559.43, 61746.29, 57778.40, 57743.27, 57774.07, 58014.60, 58194.47, 57636.87, 57511.47, 57757.67, 57873.47, 57874.53, 57919.40, 57766.53, 61151.79, 61260.36, 61081.93, 60923.50, 60920.93, 61199.43, 65381.00, 65198.77, 65156.54, 65273.38, 65240.00, 65339.77, 60828.57, 65277.46, 65567.38];
List<double> brlData = [354906.93, 373796.64, 373876.21, 374064.21, 349252.07, 349463.40, 349458.80, 349274.00, 350766.73, 346151.53, 343726.67, 343902.20, 343910.20, 344840.27, 343923.07, 342827.67, 368091.00, 364361.86, 363221.36, 357680.21, 357534.21, 357649.86, 384353.85, 383614.08, 384123.69, 383965.46, 382975.62, 383204.15, 356644.43, 381191.23, 383085.31];

// --- FUNÇÃO PRINCIPAL DE ANÁLISE ---

void main() {
  // --- FUNÇÕES AUXILIARES ---

  // Função para calcular a variação percentual de uma moeda em relação ao seu primeiro valor
  double calculateChange(List<double> data) {
    if (data.length < 2) {
      return 0.0; // Não há dados suficientes para calcular a mudança
    }
    double startValue = data[0];
    double endValue = data[data.length - 1];
    // Fórmula: ((Valor Final / Valor Inicial) - 1) * 100
    return ((endValue / startValue) - 1.0) * 100.0;
  }

  // Função para calcular a média de um conjunto de dados
  double calculateAverage(List<double> data) {
    double sum = 0.0;
    for (int i = 0; i < data.length; i++) {
      sum = sum + data[i];
    }
    return sum / data.length;
  }

  // --- CÁLCULOS PRINCIPAIS ---

  print("=========================================================");
  print("ANÁLISE DE Variação e Desvio (30 Dias)");
  print("=========================================================\n");

  // 1. Calcular a variação percentual de cada moeda em relação ao seu ponto inicial
  double usdChange = calculateChange(usdData);
  double eurChange = calculateChange(eurData);
  double brlChange = calculateChange(brlData);

  print("--- Variação Percentual (Início vs Fim do Período) ---");
  print("BTC/USD: ${usdChange.toStringAsFixed(2)}%");
  print("BTC/EUR: ${eurChange.toStringAsFixed(2)}%");
  print("BTC/BRL: ${brlChange.toStringAsFixed(2)}%");
  print("\n---------------------------------------------------------\n");


  // 2. Calcular as médias de oscilação (usando os valores finais como referência para a comparação)
  double avgUsd = calculateAverage(usdData);
  double avgEur = calculateAverage(eurData);
  double avgBrl = calculateAverage(brlData);

  print("--- Médias das Oscilações no Período ---");
  print("Média de oscilação do USD (Baseado nos dados): ${avgUsd.toStringAsFixed(2)}");
  print("Média de oscilação do EUR (Baseado nos dados): ${avgEur.toStringAsFixed(2)}");
  print("Média de oscilação do BRL (Baseado nos dados): ${avgBrl.toStringAsFixed(2)}");
  print("\n---------------------------------------------------------\n");

  // 3. Comparar a variação final com a média das outras moedas
  print("--- Desvio em Relação à Média das Outras Moedas ---");

  // Comparação USD vs EUR e BRL
  double usdDeviation = usdChange - (eurChange + brlChange) / 2.0;
  print("Desvio do USD em relação à média de EUR/BRL: ${usdDeviation.toStringAsFixed(2)}%");

  double eurDeviation = eurChange - (usdChange + brlChange) / 2.0;
  print("Desvio do EUR em relação à média de USD/BRL: ${eurDeviation.toStringAsFixed(2)}%");

  double brlDeviation = brlChange - (usdChange + eurChange) / 2.0;
  print("Desvio do BRL em relação à média de USD/EUR: ${brlDeviation.toStringAsFixed(2)}%");
}


        ]]>
    </source>
    <call function="main">
        []
    </call>
    <output>
[
  "=========================================================",
  "ANÁLISE DE Variação e Desvio (30 Dias)",
  "=========================================================\n",
  "--- Variação Percentual (Início vs Fim do Período) ---",
  "BTC/USD: 15.38%",
  "BTC/EUR: 13.59%",
  "BTC/BRL: 7.94%",
  "\n---------------------------------------------------------\n",
  "--- Médias das Oscilações no Período ---",
  "Média de oscilação do USD (Baseado nos dados): 69363.97",
  "Média de oscilação do EUR (Baseado nos dados): 60849.76",
  "Média de oscilação do BRL (Baseado nos dados): 362123.77",
  "\n---------------------------------------------------------\n",
  "--- Desvio em Relação à Média das Outras Moedas ---",
  "Desvio do USD em relação à média de EUR/BRL: 4.62%",
  "Desvio do EUR em relação à média de USD/BRL: 1.93%",
  "Desvio do BRL em relação à média de USD/EUR: -6.55%"
]
    </output>
    <source-generated language="dart"><![CDATA[<<<< [SOURCES_BEGIN] >>>>
<<<< NAMESPACE="" >>>>
<<<< CODE_UNIT_START="/test" >>>>
import 'dart:math';

  void main() {
    double calculateChange(List<double> data) {
      if (data.length < 2) {
          return 0.0;
      }

      double startValue = data[0];
      double endValue = data[data.length - 1];
      return ((endValue / startValue) - 1.0) * 100.0;
    }

    double calculateAverage(List<double> data) {
      double sum = 0.0;
      for (int i = 0; i < data.length ; i++) {
        sum = sum + data[i];
      }
      return sum / data.length;
    }

        double calculateChange(List<double> data) {
      if (data.length < 2) {
          return 0.0;
      }

      double startValue = data[0];
      double endValue = data[data.length - 1];
      return ((endValue / startValue) - 1.0) * 100.0;
    }


        double calculateAverage(List<double> data) {
      double sum = 0.0;
      for (int i = 0; i < data.length ; i++) {
        sum = sum + data[i];
      }
      return sum / data.length;
    }


    print('=========================================================');
    print('ANÁLISE DE Variação e Desvio (30 Dias)');
    print('=========================================================\n');
    double usdChange = calculateChange(usdData);
    double eurChange = calculateChange(eurData);
    double brlChange = calculateChange(brlData);
    print('--- Variação Percentual (Início vs Fim do Período) ---');
    print('BTC/USD: ${usdChange.toStringAsFixed(2)}%');
    print('BTC/EUR: ${eurChange.toStringAsFixed(2)}%');
    print('BTC/BRL: ${brlChange.toStringAsFixed(2)}%');
    print('\n---------------------------------------------------------\n');
    double avgUsd = calculateAverage(usdData);
    double avgEur = calculateAverage(eurData);
    double avgBrl = calculateAverage(brlData);
    print('--- Médias das Oscilações no Período ---');
    print('Média de oscilação do USD (Baseado nos dados): ${avgUsd.toStringAsFixed(2)}');
    print('Média de oscilação do EUR (Baseado nos dados): ${avgEur.toStringAsFixed(2)}');
    print('Média de oscilação do BRL (Baseado nos dados): ${avgBrl.toStringAsFixed(2)}');
    print('\n---------------------------------------------------------\n');
    print('--- Desvio em Relação à Média das Outras Moedas ---');
    double usdDeviation = usdChange - ((eurChange + brlChange) / 2.0);
    print('Desvio do USD em relação à média de EUR/BRL: ${usdDeviation.toStringAsFixed(2)}%');
    double eurDeviation = eurChange - ((usdChange + brlChange) / 2.0);
    print('Desvio do EUR em relação à média de USD/BRL: ${eurDeviation.toStringAsFixed(2)}%');
    double brlDeviation = brlChange - ((usdChange + eurChange) / 2.0);
    print('Desvio do BRL em relação à média de USD/EUR: ${brlDeviation.toStringAsFixed(2)}%');
  }

  List<double> usdData = <double>[66666.67, 71428.57, 71428.57, 71428.57, 66666.67, 66666.67, 66666.67, 66666.67, 66666.67, 66666.67, 66666.67, 66666.67, 66666.67, 66666.67, 66666.67, 66666.67, 71428.57, 71428.57, 71428.57, 76923.08, 76923.08, 76923.08];
  List<double> eurData = <double>[57723.8, 61667.5, 61559.43, 61746.29, 57778.4, 57743.27, 57774.07, 58014.6, 58194.47, 57636.87, 57511.47, 57757.67, 57873.47, 57874.53, 57919.4, 57766.53, 61151.79, 61260.36, 61081.93, 60923.5, 60920.93, 61199.43, 65381.0, 65198.77, 65156.54, 65273.38, 65240.0, 65339.77, 60828.57, 65277.46, 65567.38];
  List<double> brlData = <double>[354906.93, 373796.64, 373876.21, 374064.21, 349252.07, 349463.4, 349458.8, 349274.0, 350766.73, 346151.53, 343726.67, 343902.2, 343910.2, 344840.27, 343923.07, 342827.67, 368091.0, 364361.86, 363221.36, 357680.21, 357534.21, 357649.86, 384353.85, 383614.08, 384123.69, 383965.46, 382975.62, 383204.15, 356644.43, 381191.23, 383085.31];
<<<< CODE_UNIT_END="/test" >>>>
<<<< [SOURCES_END] >>>>
]]></source-generated>
</test>
    '''),
    TestDefinition('dart_basic_exchange_rates.test.xml', r'''
<?xml version="1.0" encoding="UTF-8"?>
<test title="Basic main()">
    <source language="dart">
        <![CDATA[


import 'dart:math';

// Function to calculate the standard deviation of a list of numbers without using lambdas
double calculateStandardDeviation(List<double> numbers) {
  if (numbers.isEmpty) {
    return 0.0;
  }

  // 1. Calculate the mean (average)
  double sum = 0.0;
  for (var number in numbers) {
    sum = sum + number;
  }
  double mean = sum / numbers.length;

  // 2. Calculate the sum of the squared differences from the mean
  double sumOfSquaredDifferences = 0.0;
  for (var number in numbers) {
    double difference = number - mean;
    sumOfSquaredDifferences = sumOfSquaredDifferences + pow(difference, 2);
  }

  // 3. Calculate the variance (average of the squared differences)
  double variance = sumOfSquaredDifferences / numbers.length;

  // 4. Calculate the standard deviation (square root of the variance)
  return sqrt(variance);
}

void main() {
  // Data fetched from the API for BTC to USD over the last 30 days + 1 extra day (31 total points)
  // NOTE: These values are manually entered based on the previous API response.
  List<double> dailyRates = [
    66666.666667, // 2026-03-22
    71428.571429, // 2026-03-23
    71428.571429, // 2026-03-24
    71428.571429, // 2026-03-25
    66666.666667, // 2026-03-26
    66666.666667, // 2026-03-27
    66666.666667, // 2026-03-28
    66666.666667, // 2026-03-29
    66666.666667, // 2026-03-30
    66666.666667, // 2026-03-31
    66666.666667, // 2026-04-01
    66666.666667, // 2026-04-02
    66666.666667, // 2026-04-03
    66666.666667, // 2026-04-04
    66666.666667, // 2026-04-05
    66666.666667, // 2026-04-06
    71428.571429, // 2026-04-07
    71428.571429, // 2026-04-08
    71428.571429, // 2026-04-09
    71428.571429, // 2026-04-10
    71428.571429, // 2026-04-11
    71428.571429, // 2026-04-12
    76923.076923, // 2026-04-13
    76923.076923, // 2026-04-14
    76923.076923, // 2026-04-15
  ];

  print("--- BTC to USD Exchange Rates (Data for Calculation) ---");
  for (int i = 0; i < dailyRates.length; i++) {
    String dateStr = "Day ${i + 1} (Date: 2026-03-${22 + i})";
    print("$dateStr: ${dailyRates[i].toStringAsFixed(2)} USD");
  }

  print("\n--- Standard Deviation Calculation ---");
  double stdDev = calculateStandardDeviation(dailyRates);

  print("\nResult:");
  print("The calculated Standard Deviation for the recorded dates is: $stdDev");
}



        ]]>
    </source>
    <call function="main">
        []
    </call>
    <output>
[
  "--- BTC to USD Exchange Rates (Data for Calculation) ---",
  "Day 1 (Date: 2026-03-22): 66666.67 USD",
  "Day 2 (Date: 2026-03-23): 71428.57 USD",
  "Day 3 (Date: 2026-03-24): 71428.57 USD",
  "Day 4 (Date: 2026-03-25): 71428.57 USD",
  "Day 5 (Date: 2026-03-26): 66666.67 USD",
  "Day 6 (Date: 2026-03-27): 66666.67 USD",
  "Day 7 (Date: 2026-03-28): 66666.67 USD",
  "Day 8 (Date: 2026-03-29): 66666.67 USD",
  "Day 9 (Date: 2026-03-30): 66666.67 USD",
  "Day 10 (Date: 2026-03-31): 66666.67 USD",
  "Day 11 (Date: 2026-03-32): 66666.67 USD",
  "Day 12 (Date: 2026-03-33): 66666.67 USD",
  "Day 13 (Date: 2026-03-34): 66666.67 USD",
  "Day 14 (Date: 2026-03-35): 66666.67 USD",
  "Day 15 (Date: 2026-03-36): 66666.67 USD",
  "Day 16 (Date: 2026-03-37): 66666.67 USD",
  "Day 17 (Date: 2026-03-38): 71428.57 USD",
  "Day 18 (Date: 2026-03-39): 71428.57 USD",
  "Day 19 (Date: 2026-03-40): 71428.57 USD",
  "Day 20 (Date: 2026-03-41): 71428.57 USD",
  "Day 21 (Date: 2026-03-42): 71428.57 USD",
  "Day 22 (Date: 2026-03-43): 71428.57 USD",
  "Day 23 (Date: 2026-03-44): 76923.08 USD",
  "Day 24 (Date: 2026-03-45): 76923.08 USD",
  "Day 25 (Date: 2026-03-46): 76923.08 USD",
  "\n--- Standard Deviation Calculation ---",
  "\nResult:",
  "The calculated Standard Deviation for the recorded dates is: 3480.400959353717"
]
    </output>
    <source-generated language="dart"><![CDATA[<<<< [SOURCES_BEGIN] >>>>
<<<< NAMESPACE="" >>>>
<<<< CODE_UNIT_START="/test" >>>>
import 'dart:math';

  double calculateStandardDeviation(List<double> numbers) {
    if (numbers.isEmpty) {
        return 0.0;
    }

    double sum = 0.0;
    for (var number in numbers) {
      sum = sum + number;
    }
    double mean = sum / numbers.length;
    double sumOfSquaredDifferences = 0.0;
    for (var number in numbers) {
      double difference = number - mean;
      sumOfSquaredDifferences = sumOfSquaredDifferences + pow(difference, 2);
    }
    double variance = sumOfSquaredDifferences / numbers.length;
    return sqrt(variance);
  }

  void main() {
    List<double> dailyRates = <double>[66666.666667, 71428.571429, 71428.571429, 71428.571429, 66666.666667, 66666.666667, 66666.666667, 66666.666667, 66666.666667, 66666.666667, 66666.666667, 66666.666667, 66666.666667, 66666.666667, 66666.666667, 66666.666667, 71428.571429, 71428.571429, 71428.571429, 71428.571429, 71428.571429, 71428.571429, 76923.076923, 76923.076923, 76923.076923];
    print('--- BTC to USD Exchange Rates (Data for Calculation) ---');
    for (int i = 0; i < dailyRates.length ; i++) {
      String dateStr = 'Day ${i + 1} (Date: 2026-03-${22 + i})';
      print('$dateStr: ${dailyRates[i].toStringAsFixed(2)} USD');
    }
    print('\n--- Standard Deviation Calculation ---');
    double stdDev = calculateStandardDeviation(dailyRates);
    print('\nResult:');
    print('The calculated Standard Deviation for the recorded dates is: $stdDev');
  }

<<<< CODE_UNIT_END="/test" >>>>
<<<< [SOURCES_END] >>>>
]]></source-generated>
</test>
    '''),
    TestDefinition('dart_basic_exchange_rates.test.xml', r'''
<?xml version="1.0" encoding="UTF-8"?>
<test title="Basic main()">
    <source language="dart">
        <![CDATA[

void main() {
  var x = 10;
  var y = 20;
  
  {
    var z = x+y+10;
    print("z1: $z");
  }
  
  var z = x+y;
  
  print("z2: $z");
}

        ]]>
    </source>
    <call function="main">
        []
    </call>
    <output>
[
"z1: 40",
"z2: 30"
]
    </output>
    <source-generated language="dart"><![CDATA[<<<< [SOURCES_BEGIN] >>>>
<<<< NAMESPACE="" >>>>
<<<< CODE_UNIT_START="/test" >>>>
  void main() {
    var x = 10;
    var y = 20;
    {
      var z = x + (y + 10);
      print('z1: $z');
    }

    var z = x + y;
    print('z2: $z');
  }

<<<< CODE_UNIT_END="/test" >>>>
<<<< [SOURCES_END] >>>>
]]></source-generated>
</test>
    '''),
    TestDefinition('dart_basic_exchange_rates.test.xml', r'''
<?xml version="1.0" encoding="UTF-8"?>
<test title="Basic main()">
    <source language="dart">
        <![CDATA[
import 'dart:math';

double calculateStdDev(List<double> values) {        
  if (values == null || values.isEmpty) {
    return 0.0;
  }

  double sum = 0;
  for (var value in values) {
    sum += value;
  }
  double mean = sum / values.length;

  double sqDiffSum = 0;
  for (var value in values) {
    sqDiffSum += pow(value - mean, 2);
  }
  double variance = sqDiffSum / values.length;
  return sqrt(variance);
}

void main() {
  // Rates from the API response, excluding the first and last element which are the current/end date
  List<double> rates = [71428.571429, 66666.666667, 71428.571429, 71428.571429, 71428.571429, 66666.666667, 66666.666667, 66666.666667, 66666.666667, 66666.666667, 66666.666667, 66666.666667, 66666.666667, 66666.666667, 66666.666667, 66666.666667, 66666.666667, 71428.571429, 76923.076923];
  double stdDev = calculateStdDev(rates);
  print('Standard Deviation: $stdDev');
}

        ]]>
    </source>
    <call function="main">
        []
    </call>
    <output>
           ["Standard Deviation: 2879.092762172585"]
    </output>
    <source-generated language="dart"><![CDATA[<<<< [SOURCES_BEGIN] >>>>
<<<< NAMESPACE="" >>>>
<<<< CODE_UNIT_START="/test" >>>>
import 'dart:math';

  double calculateStdDev(List<double> values) {
    if ((values == null) || values.isEmpty) {
        return 0.0;
    }

    double sum = 0;
    for (var value in values) {
      sum += value;
    }
    double mean = sum / values.length;
    double sqDiffSum = 0;
    for (var value in values) {
      sqDiffSum += pow(value - mean, 2);
    }
    double variance = sqDiffSum / values.length;
    return sqrt(variance);
  }

  void main() {
    List<double> rates = <double>[71428.571429, 66666.666667, 71428.571429, 71428.571429, 71428.571429, 66666.666667, 66666.666667, 66666.666667, 66666.666667, 66666.666667, 66666.666667, 66666.666667, 66666.666667, 66666.666667, 66666.666667, 66666.666667, 66666.666667, 71428.571429, 76923.076923];
    double stdDev = calculateStdDev(rates);
    print('Standard Deviation: $stdDev');
  }

<<<< CODE_UNIT_END="/test" >>>>
<<<< [SOURCES_END] >>>>
]]></source-generated>
</test>
    '''),
    TestDefinition('dart_basic_exchange_rates.test.xml', r'''
<?xml version="1.0" encoding="UTF-8"?>
<test title="Basic main()">
    <source language="dart" auto-import-dart-math="true">
        <![CDATA[

void main() {
  // --- Parameters based on the conceptual formula ---

  // Initial State
  double T0 = 100.0; // Initial Trustworthiness (100%)

  // Model Constants (These are illustrative and must be calibrated for real-world use)
  double alpha = 0.5;      // Error Amplification Constant (Sensitivity to error compounding)
  double C = 2.0;          // Context/Complexity Factor (Complexity multiplier)
  int timeMonths = 6;      // Simulation duration: 6 months

  // --- Simulation Setup ---
  // We will simulate the accumulation of errors over time based on a hypothetical rate.
  // For this simulation, we assume an average monthly error introduction rate (E_monthly).
  // The team size (5 developers) influences the error rate and context factor implicitly.

  // Hypothetical Monthly Error Introduction Rate (This is the variable that changes each month)
  double monthlyErrorRate = 0.1; // Assume 10% of work introduces errors per month, adjusted by team size/complexity.

  double accumulatedErrors = 0.0;
  List<double> trustworthinessHistory = [];

  print("--- LLM Trustworthiness Simulation Over $timeMonths Months ---");
  print("Initial State: T0 = $T0\n");


  // --- Iterative Simulation Loop ---
  for (int t = 1; t <= timeMonths; t++) {
    // 1. Calculate the new error introduced in this period
    double monthlyErrors = monthlyErrorRate * C / 5.0; // Adjusting by team size for context factor

    // 2. Update the accumulated errors (E_acc)
    accumulatedErrors += monthlyErrors;

    // 3. Calculate the compounding risk term using the formula: e^(alpha * E_acc * t)
    // Note: We use 't' as the total time elapsed for this calculation step, reflecting cumulative history.
    double compoundingFactor = exp(alpha * accumulatedErrors * t);

    // 4. Calculate the Trustworthiness (T_t)
    double currentTrustworthiness = T0 - (accumulatedErrors * compoundingFactor);

    // Ensure trustworthiness does not fall below zero or become negative
    if (currentTrustworthiness < 0) {
      currentTrustworthiness = 0.0;
    }

    trustworthinessHistory.add(currentTrustworthiness);

    print("Month $t:");
    print("  Accumulated Errors (E_acc): ${accumulatedErrors.toStringAsFixed(3)}");
    print("  Compounding Factor: ${compoundingFactor.toStringAsFixed(2)}");
    print("  Current Trustworthiness (T_$t): ${currentTrustworthiness.toStringAsFixed(2)}%\n");
  }

  // --- Final Result ---
  double finalTrust = trustworthinessHistory.last;
  print("==================================================");
  print("SIMULATION COMPLETE");
  print("Final Trustworthiness after $timeMonths Months: ${finalTrust.toStringAsFixed(2)}%");
  print("==================================================");
}

        ]]>
    </source>
    <call function="main">
        []
    </call>
    <output>
          [
            "--- LLM Trustworthiness Simulation Over 6 Months ---",
            "Initial State: T0 = 100.0\n",
            "Month 1:",
            "  Accumulated Errors (E_acc): 0.040",
            "  Compounding Factor: 1.02",
            "  Current Trustworthiness (T_1): 99.96%\n",
            "Month 2:",
            "  Accumulated Errors (E_acc): 0.080",
            "  Compounding Factor: 1.08",
            "  Current Trustworthiness (T_2): 99.91%\n",
            "Month 3:",
            "  Accumulated Errors (E_acc): 0.120",
            "  Compounding Factor: 1.20",
            "  Current Trustworthiness (T_3): 99.86%\n",
            "Month 4:",
            "  Accumulated Errors (E_acc): 0.160",
            "  Compounding Factor: 1.38",
            "  Current Trustworthiness (T_4): 99.78%\n",
            "Month 5:",
            "  Accumulated Errors (E_acc): 0.200",
            "  Compounding Factor: 1.65",
            "  Current Trustworthiness (T_5): 99.67%\n",
            "Month 6:",
            "  Accumulated Errors (E_acc): 0.240",
            "  Compounding Factor: 2.05",
            "  Current Trustworthiness (T_6): 99.51%\n",
            "==================================================",
            "SIMULATION COMPLETE",
            "Final Trustworthiness after 6 Months: 99.51%",
            "=================================================="
          ]
    </output>
    <source-generated language="dart"><![CDATA[<<<< [SOURCES_BEGIN] >>>>
<<<< NAMESPACE="" >>>>
<<<< CODE_UNIT_START="/test" >>>>
  void main() {
    double T0 = 100.0;
    double alpha = 0.5;
    double C = 2.0;
    int timeMonths = 6;
    double monthlyErrorRate = 0.1;
    double accumulatedErrors = 0.0;
    List<double> trustworthinessHistory = <double>[];
    print('--- LLM Trustworthiness Simulation Over $timeMonths Months ---');
    print('Initial State: T0 = $T0\n');
    for (int t = 1; t <= timeMonths ; t++) {
      double monthlyErrors = monthlyErrorRate * (C / 5.0);
      accumulatedErrors += monthlyErrors;
      double compoundingFactor = exp(alpha * (accumulatedErrors * t));
      double currentTrustworthiness = T0 - (accumulatedErrors * compoundingFactor);
      if (currentTrustworthiness < 0) {
          currentTrustworthiness = 0.0;
      }

      trustworthinessHistory.add(currentTrustworthiness);
      print('Month $t:');
      print('  Accumulated Errors (E_acc): ${accumulatedErrors.toStringAsFixed(3)}');
      print('  Compounding Factor: ${compoundingFactor.toStringAsFixed(2)}');
      print('  Current Trustworthiness (T_$t): ${currentTrustworthiness.toStringAsFixed(2)}%\n');
    }
    double finalTrust = trustworthinessHistory.last;
    print('==================================================');
    print('SIMULATION COMPLETE');
    print('Final Trustworthiness after $timeMonths Months: ${finalTrust.toStringAsFixed(2)}%');
    print('==================================================');
  }

<<<< CODE_UNIT_END="/test" >>>>
<<<< [SOURCES_END] >>>>
]]></source-generated>
</test>
    '''),
    TestDefinition('dart_basic_exchange_rates.test.xml', r'''
<?xml version="1.0" encoding="UTF-8"?>
<test title="Basic main()">
    <source language="dart">
        <![CDATA[
void main() {
  // Exchange rates obtained from the API calls
  final double usdToEurRate = 0.84946;      // Rate: 1 USD = X EUR
  final double usdToBrlRate = 4.981878;     // Rate: 1 USD = X BRL
  final double eurToBrlRate = 5.864759;     // Rate: 1 EUR = X BRL

  print('--- Currency Exchange Rates ---');
  print('USD to EUR Rate: $usdToEurRate');
  print('USD to BRL Rate: $usdToBrlRate');
  print('EUR to BRL Rate: $eurToBrlRate');
  print('\n--- Arbitrage Calculation (USD -> EUR -> BRL) ---');

  // Calculate the implied rate for USD -> BRL via EUR
  // Implied Rate = (USD to EUR Rate) * (EUR to BRL Rate)
  final double impliedBrlRate = usdToEurRate * eurToBrlRate;
  print('Implied USD to BRL Rate (via EUR): $impliedBrlRate');

  // Calculate the discrepancy
  // Discrepancy = Implied Rate - Direct Rate
  final double discrepancy = impliedBrlRate - usdToBrlRate;

  print('\n--- Arbitrage Discrepancy ---');
  if (discrepancy > 0) {
    print('Arbitrage Opportunity: The indirect route is more profitable by: ${discrepancy.toStringAsFixed(8)} BRL per USD.');
  } else if (discrepancy < 0) {
    print('No Arbitrage Opportunity: The direct route is more profitable by: ${(-discrepancy).toStringAsFixed(8)} BRL per USD.');
  } else {
    print('Rates are perfectly aligned. No arbitrage opportunity found.');
  }
}

        ]]>
    </source>
    <call function="main">
        []
    </call>
    <output>
          [
            "--- Currency Exchange Rates ---",
            "USD to EUR Rate: 0.84946",
            "USD to BRL Rate: 4.981878",
            "EUR to BRL Rate: 5.864759",
            "\n--- Arbitrage Calculation (USD -> EUR -> BRL) ---",
            "Implied USD to BRL Rate (via EUR): 4.98187818014",
            "\n--- Arbitrage Discrepancy ---",
            "Arbitrage Opportunity: The indirect route is more profitable by: 0.00000018 BRL per USD."
          ]
    </output>
    <source-generated language="dart"><![CDATA[<<<< [SOURCES_BEGIN] >>>>
<<<< NAMESPACE="" >>>>
<<<< CODE_UNIT_START="/test" >>>>
  void main() {
    double usdToEurRate = 0.84946;
    double usdToBrlRate = 4.981878;
    double eurToBrlRate = 5.864759;
    print('--- Currency Exchange Rates ---');
    print('USD to EUR Rate: $usdToEurRate');
    print('USD to BRL Rate: $usdToBrlRate');
    print('EUR to BRL Rate: $eurToBrlRate');
    print('\n--- Arbitrage Calculation (USD -> EUR -> BRL) ---');
    double impliedBrlRate = usdToEurRate * eurToBrlRate;
    print('Implied USD to BRL Rate (via EUR): $impliedBrlRate');
    double discrepancy = impliedBrlRate - usdToBrlRate;
    print('\n--- Arbitrage Discrepancy ---');
    if (discrepancy > 0) {
        print('Arbitrage Opportunity: The indirect route is more profitable by: ${discrepancy.toStringAsFixed(8)} BRL per USD.');
    } else if (discrepancy < 0) {
        print('No Arbitrage Opportunity: The direct route is more profitable by: ${(-discrepancy).toStringAsFixed(8)} BRL per USD.');
    } else {
        print('Rates are perfectly aligned. No arbitrage opportunity found.');
    }

  }

<<<< CODE_UNIT_END="/test" >>>>
<<<< [SOURCES_END] >>>>
]]></source-generated>
</test>
    '''),
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
import "dart:math" ;

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
import 'dart:math';

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
