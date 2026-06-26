import 'dart:typed_data';

import 'package:apollovm/apollovm.dart';
import 'package:data_serializer/data_serializer.dart';
import 'package:test/test.dart';

void main() async {
  group('ApolloVM - Wasm Generator', () {
    test(
      'empty',
      () => _testWasm(
        language: 'dart',
        code: r'''
      
          void empty() {
            
          }
          
        ''',
        functionName: 'empty',
        executions: {[]: null},
        expecteWasm: {
          'test':
              '0061736D010000000104016000000302010007090105656D70747900000A040102000B',
        },
      ),
    );

    test(
      'add1',
      () => _testWasm(
        language: 'dart',
        code: r'''
      
          int add1(int a) {
            int x = a + 10;
            return x;
          }
          
        ''',
        functionName: 'add1',
        executions: {
          [101]: 111,
        },
        expecteWasm: {
          'test':
              '0061736D0100000001060160017E017E03020100070801046164643100000A10010E01017E2000420A7C210120010F0B',
        },
      ),
    );

    test(
      'add3',
      () => _testWasm(
        language: 'dart',
        code: r'''
      
          int add3(int a, int b) {
            int x = a + b + 10;
            return x;
          }
          
        ''',
        functionName: 'add3',
        executions: {
          [101, 50]: 161,
        },
        expecteWasm: {
          'test':
              '0061736D0100000001070160027E7E017E03020100070801046164643300000A13011101017E200020017C420A7C210220020F0B',
        },
      ),
    );

    test(
      'add4',
      () => _testWasm(
        language: 'dart',
        code: r'''
      
          int add4(int a, int b, int c) {
            int x = a + b + 10;
            int y = c ~/ 2;
            int z = x - y;
            return z;
          }
          
        ''',
        functionName: 'add4',
        executions: {
          [101, 50, 30]: 146,
        },
        expecteWasm: {
          'test':
              '0061736D0100000001080160037E7E7E017E03020100070801046164643400000A28012603017E017E017E200020017C420A7C21032002B94202B9A3B02104200320047D210520050F0B',
        },
      ),
    );

    test(
      'add5',
      () => _testWasm(
        language: 'dart',
        code: r'''
      
          int add5(int a, int b, int c) {
            int x = a + b + 10;
            int y = c ~/ 2;
            int z = x - y;
            return z * z;
          }
          
        ''',
        functionName: 'add5',
        executions: {
          [101, 50, 30]: 21316,
          [10, 50, 300]: 6400,
        },
        expecteWasm: {
          'test':
              '0061736D0100000001080160037E7E7E017E03020100070801046164643500000A2B012903017E017E017E200020017C420A7C21032002B94202B9A3B02104200320047D2105200520057E0F0B',
        },
      ),
    );

    test(
      'add6',
      () => _testWasm(
        language: 'dart',
        code: r'''
      
          int add6(int a) {
            if (a > 100) {
              return 1 ;
            } 
            return 0 ;
          }
          
        ''',
        functionName: 'add6',
        executions: {
          [101]: 1,
          [10]: 0,
        },
        expecteWasm: {
          'test':
              '0061736D0100000001060160017E017E03020100070801046164643600000A16011400200042E40055044042010F0B42000F0042000B',
        },
      ),
    );

    test(
      'add7',
      () => _testWasm(
        language: 'dart',
        code: r'''
      
          int add7(int a) {
            if (a > 100) {
              a = a + 100;
            }
            else {
              a = a + 10;
            }
            
            return a ;
          }
          
        ''',
        functionName: 'add7',
        executions: {
          [111]: 211,
          [11]: 21,
        },
        expecteWasm: {
          'test':
              '0061736D0100000001060160017E017E03020100070801046164643700000A20011E00200042E400550440200042E4007C2100052000420A7C21000B20000F0B',
        },
      ),
    );

    test(
      'add8',
      () => _testWasm(
        language: 'dart',
        code: r'''
      
          int add8(int a) {
            if (a > 100) {
              return 1 ;
            } 
            else if ( a == 0 ) {
              return 0 ;
            }
            else {
              return -1 ;
            }
          }
          
        ''',
        functionName: 'add8',
        executions: {
          [101]: 1,
          [0]: 0,
          [10]: -1,
        },
        expecteWasm: {
          'test':
              '0061736D0100000001060160017E017E03020100070801046164643800000A21011F00200042E40055044042010F05200050044042000F05427F0F0B0B0042000B',
        },
      ),
    );

    test(
      'add9',
      () => _testWasm(
        language: 'dart',
        code: r'''
      
          int add9(int a) {
            if (a > 100) {
              return 100 ;
            } 
            else if ( a == 0 ) {
              return 0 ;
            }
            else if ( a == 1 ) {
              return 1 ;
            }
            else {
              return -1 ;
            }
          }
          
        ''',
        functionName: 'add9',
        executions: {
          [101]: 100,
          [0]: 0,
          [1]: 1,
          [10]: -1,
        },
        expecteWasm: {
          'test':
              '0061736D0100000001060160017E017E03020100070801046164643900000A2E012C00200042E40055044042E4000F05200050044042000F052000420151044042010F05427F0F0B0B0B0042000B',
        },
      ),
    );

    test(
      'add10',
      () => _testWasm(
        language: 'dart',
        code: r'''
      
          int add10(int a) {
            if (a > 100) {
              return 1 ;
            } 
            else if ( a == 0 ) {
              return 0 ;
            }
            
            return -11 ;
          }
          
        ''',
        functionName: 'add10',
        executions: {
          [101]: 1,
          [0]: 0,
          [10]: -11,
        },
        expecteWasm: {
          'test':
              '0061736D0100000001060160017E017E0302010007090105616464313000000A20011E00200042E40055044042010F05200050044042000F0B0B42750F0042000B',
        },
      ),
    );

    test(
      'add11',
      () => _testWasm(
        language: 'dart',
        code: r'''
      
          int add11(int a) {
            var x = a + 10;
            return x;
          }
          
        ''',
        functionName: 'add11',
        executions: {
          [101]: 111,
        },
        expecteWasm: {
          'test':
              '0061736D0100000001060160017E017E0302010007090105616464313100000A10010E01017E2000420A7C210120010F0B',
        },
      ),
    );

    test(
      'add12',
      () => _testWasm(
        language: 'dart',
        code: r'''
      
          double add12( int a, int b ) {
            double c = b / 2;
            var sumAC = a + c ;
            return sumAC;
          }
          
        ''',
        functionName: 'add12',
        executions: {
          [100, 31]: 115.5,
        },
        expecteWasm: {
          'test':
              '0061736D0100000001070160027E7E017C0302010007090105616464313200000A1C011A02017C017C2001B94202B9A321022000B92002A0210320030F0B',
        },
      ),
    );

    test(
      'add13',
      () => _testWasm(
        language: 'dart',
        code: r'''
      
          double add13(int a) {
            var x = a + 10 ;
            return x ;
          }
          
        ''',
        functionName: 'add13',
        executions: {
          [100]: 110,
        },
        expecteWasm: {
          'test':
              '0061736D0100000001060160017E017C0302010007090105616464313300000A11010F01017E2000420A7C21012001B90F0B',
        },
      ),
    );

    test(
      'increment1',
      () => _testWasm(
        language: 'dart',
        code: r'''
      
          int increment1(int a) {
            int x = a++;
            return x;
          }
          
        ''',
        functionName: 'increment1',
        executions: {
          [100]: 100,
        },
        expecteWasm: {
          'test':
              '0061736D0100000001060160017E017E03020100070E010A696E6372656D656E743100000A14011201017E2000200042017C2100210120010F0B',
        },
      ),
    );

    test(
      'increment2',
      () => _testWasm(
        language: 'dart',
        code: r'''
      
          int increment2(int a) {
            a++;
            int x = a++;
            return x;
          }
          
        ''',
        functionName: 'increment2',
        executions: {
          [100]: 101,
        },
        expecteWasm: {
          'test':
              '0061736D0100000001060160017E017E03020100070E010A696E6372656D656E743200000A1D011B01017E2000200042017C21002000200042017C2100210120010F0B',
        },
      ),
    );

    test(
      'increment3',
      () => _testWasm(
        language: 'dart',
        code: r'''
      
          int increment3(int a) {
            a++;
            int x = a++;
            return a;
          }
          
        ''',
        functionName: 'increment3',
        executions: {
          [100]: 102,
        },
        expecteWasm: {
          'test':
              '0061736D0100000001060160017E017E03020100070E010A696E6372656D656E743300000A1D011B01017E2000200042017C21002000200042017C2100210120000F0B',
        },
      ),
    );

    test(
      'preIncrement1',
      () => _testWasm(
        language: 'dart',
        code: r'''
      
          int preIncrement1(int a) {
            int x = ++a;
            return x;
          }
          
        ''',
        functionName: 'preIncrement1',
        executions: {
          [100]: 101,
        },
        expecteWasm: {
          'test':
              '0061736D0100000001060160017E017E030201000711010D707265496E6372656D656E743100000A14011201017E200042017C21002000210120010F0B',
        },
      ),
    );

    test(
      'preIncrement2',
      () => _testWasm(
        language: 'dart',
        code: r'''
      
          int preIncrement2(int a) {
            ++a;
            int x = ++a;
            return x;
          }
          
        ''',
        functionName: 'preIncrement2',
        executions: {
          [100]: 102,
        },
        expecteWasm: {
          'test':
              '0061736D0100000001060160017E017E030201000711010D707265496E6372656D656E743200000A1D011B01017E200042017C21002000200042017C21002000210120010F0B',
        },
      ),
    );

    test(
      'preIncrement3',
      () => _testWasm(
        language: 'dart',
        code: r'''
      
          int preIncrement3(int a) {
            ++a;
            int x = ++a;
            return a;
          }
          
        ''',
        functionName: 'preIncrement3',
        executions: {
          [100]: 102,
        },
        expecteWasm: {
          'test':
              '0061736D0100000001060160017E017E030201000711010D707265496E6372656D656E743300000A1D011B01017E200042017C21002000200042017C21002000210120000F0B',
        },
      ),
    );

    test(
      'decrement1',
      () => _testWasm(
        language: 'dart',
        code: r'''
      
          int decrement1(int a) {
            int x = a--;
            return x;
          }
          
        ''',
        functionName: 'decrement1',
        executions: {
          [100]: 100,
        },
        expecteWasm: {
          'test':
              '0061736D0100000001060160017E017E03020100070E010A64656372656D656E743100000A14011201017E2000200042017D2100210120010F0B',
        },
      ),
    );

    test(
      'decrement2',
      () => _testWasm(
        language: 'dart',
        code: r'''
      
          int decrement2(int a) {
            a--;
            int x = a--;
            return x;
          }
          
        ''',
        functionName: 'decrement2',
        executions: {
          [100]: 99,
        },
        expecteWasm: {
          'test':
              '0061736D0100000001060160017E017E03020100070E010A64656372656D656E743200000A1D011B01017E2000200042017D21002000200042017D2100210120010F0B',
        },
      ),
    );

    test(
      'decrement3',
      () => _testWasm(
        language: 'dart',
        code: r'''
      
          int decrement3(int a) {
            a--;
            int x = a--;
            return a;
          }
          
        ''',
        functionName: 'decrement3',
        executions: {
          [100]: 98,
        },
        expecteWasm: {
          'test':
              '0061736D0100000001060160017E017E03020100070E010A64656372656D656E743300000A1D011B01017E2000200042017D21002000200042017D2100210120000F0B',
        },
      ),
    );

    test(
      'preDecrement1',
      () => _testWasm(
        language: 'dart',
        code: r'''
      
          int preDecrement1(int a) {
            int x = --a;
            return x;
          }
          
        ''',
        functionName: 'preDecrement1',
        executions: {
          [100]: 99,
        },
        expecteWasm: {
          'test':
              '0061736D0100000001060160017E017E030201000711010D70726544656372656D656E743100000A14011201017E200042017D21002000210120010F0B',
        },
      ),
    );

    test(
      'preDecrement2',
      () => _testWasm(
        language: 'dart',
        code: r'''
      
          int preDecrement2(int a) {
            --a;
            int x = --a;
            return x;
          }
          
        ''',
        functionName: 'preDecrement2',
        executions: {
          [100]: 98,
        },
        expecteWasm: {
          'test':
              '0061736D0100000001060160017E017E030201000711010D70726544656372656D656E743200000A1D011B01017E200042017D21002000200042017D21002000210120010F0B',
        },
      ),
    );

    test(
      'preDecrement3',
      () => _testWasm(
        language: 'dart',
        code: r'''
      
          int preDecrement3(int a) {
            --a;
            int x = --a;
            return a;
          }
          
        ''',
        functionName: 'preDecrement3',
        executions: {
          [100]: 98,
        },
        expecteWasm: {
          'test':
              '0061736D0100000001060160017E017E030201000711010D70726544656372656D656E743300000A1D011B01017E200042017D21002000200042017D21002000210120000F0B',
        },
      ),
    );

    test(
      'operation1',
      () => _testWasm(
        language: 'dart',
        code: r'''
      
          double operation1( int v, double r, int balance ) {
            var total = v * r ;
          
            if ( total > balance ) {
              return 0;
            }
            
            return total ;
          }
          
        ''',
        functionName: 'operation1',
        executions: {
          [50, 0.33, 1000]: 16.5,
          [50, 30.0, 1000]: 0.0,
          [50, 30.0, 2000]: 1500.0,
          [50, 30, 2000]: 1500.0,
        },
        expecteWasm: {
          'test':
              '0061736D0100000001080160037E7C7E017C03020100070E010A6F7065726174696F6E3100000A1E011C01017C2000B92001A2210320032002B96404404200B90F0B20030F0B',
        },
      ),
    );

    test(
      'operation2',
      () => _testWasm(
        language: 'dart',
        code: r'''
      
          int operation2( int v, double r, int balance ) {
            var total = v * r ;
          
            if ( total > balance ) {
              return 0;
            }
            
            return total ;
          }
          
        ''',
        functionName: 'operation2',
        executions: {
          [50, 0.33, 1000]: 16.0,
          [50, 30.0, 1000]: 0.0,
          [50, 30.0, 2000]: 1500.0,
        },
        expecteWasm: {
          'test':
              '0061736D0100000001080160037E7C7E017E03020100070E010A6F7065726174696F6E3200000A1E011C01017C2000B92001A2210320032002B964044042000F0B2003B00F0B',
        },
      ),
    );

    test(
      'operation3',
      () => _testWasm(
        language: 'dart',
        code: r'''
      
          double operation3( int v, double r, int balance , double extra ) {
            var total = v * r ;
          
            total = total + extra;
          
            if ( total > balance ) {
              return 0;
            }
            
            return total ;
          }
          
        ''',
        functionName: 'operation3',
        executions: {
          [50, 0.33, 1000, 0.01]: 16.51,
          [50, 30.0, 1000, 0.02]: 0.0,
          [50, 30.0, 2000, 0.03]: 1500.03,
        },
        expecteWasm: {
          'test':
              '0061736D0100000001090160047E7C7E7C017C03020100070E010A6F7065726174696F6E3300000A25012301017C2000B92001A2210420042003A0210420042002B96404404200B90F0B20040F0B',
        },
      ),
    );

    test(
      'operation4',
      () => _testWasm(
        language: 'dart',
        code: r'''
      
          double operation4( int v, double r, int balance , double extra , double extraRatio ) {
            var total = v * r ;
          
            total = total + (extra * extraRatio);
          
            if ( total > balance ) {
              return 0;
            }
            
            return total ;
          }
          
        ''',
        functionName: 'operation4',
        executions: {
          [50, 0.33, 1000, 0.01, 1]: 16.51,
          [50, 0.33, 1000, 0.01, 0.5]: 16.505,
          [50, 30.0, 1000, 0.02, 1]: 0.0,
          [50, 30.0, 1000, 0.02, 2]: 0.0,
          [50, 30.0, 2000, 0.03, 1]: 1500.03,
          [50, 30.0, 2000, 0.03, 2]: 1500.06,
        },
        expecteWasm: {
          'test':
              '0061736D01000000010A0160057E7C7E7C7C017C03020100070E010A6F7065726174696F6E3400000A28012601017C2000B92001A22105200520032004A2A0210520052002B96404404200B90F0B20050F0B',
        },
      ),
    );

    test(
      'f\$10',
      () => _testWasm(
        language: 'dart',
        code: r'''
      
          int f$10( int a, double b , double c ) {
            var x = a * b;
            var y = x / c ;
            return y ;
          }
          
        ''',
        functionName: 'f\$10',
        executions: {
          [10, 5, 2]: 25,
          [10, 5, 3]: 16,
        },
        expecteWasm: {
          'test':
              '0061736D0100000001080160037E7C7C017E03020100070801046624313000000A1B011902017C017C2000B92001A2210320032002A321042004B00F0B',
        },
      ),
    );

    test(
      'f\$11',
      () => _testWasm(
        language: 'dart',
        code: r'''
      
          double f$11( int a, double b , double c ) {
            var x = a * b;
            var y = x / c ;
            return y ;
          }
          
        ''',
        functionName: 'f\$11',
        executions: {
          [10, 5, 2]: 25,
          [11, 3, 2]: 16.5,
        },
        expecteWasm: {
          'test':
              '0061736D0100000001080160037E7C7C017C03020100070801046624313100000A1A011802017C017C2000B92001A2210320032002A3210420040F0B',
        },
      ),
    );

    test(
      'f\$12',
      () => _testWasm(
        language: 'dart',
        code: r'''
      
          double f$12( int a, double b , double c ) {
            var x = a * b;
            var y = x ~/ c ;
            return y ;
          }
          
        ''',
        functionName: 'f\$12',
        executions: {
          [10, 5, 2]: 25,
          [11, 3, 2]: 16,
        },
        expecteWasm: {
          'test':
              '0061736D0100000001080160037E7C7C017C03020100070801046624313200000A1C011A02017C017E2000B92001A2210320032002A3B021042004B90F0B',
        },
      ),
    );

    test(
      'subHeavy1',
      () => _testWasm(
        language: 'dart',
        code: r'''

          int subHeavy1(int a, int b, int c) {
            int x = a - b - c - 5;
            return x;
          }

        ''',
        functionName: 'subHeavy1',
        executions: {
          [100, 20, 30]: 45,
          [50, 10, 5]: 30,
        },
        expecteWasm: {
          'test':
              '0061736D0100000001080160037E7E7E017E03020100070D010973756248656176793100000A16011401017E200020017D20027D42057D210320030F0B',
        },
      ),
    );

    test(
      'cmpLess',
      () => _testWasm(
        language: 'dart',
        code: r'''

          int cmpLess(int a) {
            if (a < 10) {
              return 1;
            }
            return 0;
          }

        ''',
        functionName: 'cmpLess',
        executions: {
          [5]: 1,
          [10]: 0,
          [20]: 0,
        },
        expecteWasm: {
          'test':
              '0061736D0100000001060160017E017E03020100070B0107636D704C65737300000A150113002000420A53044042010F0B42000F0042000B',
        },
      ),
    );

    test(
      'cmpLessEqual',
      () => _testWasm(
        language: 'dart',
        code: r'''

          int cmpLessEqual(int a) {
            if (a <= 10) {
              return 1;
            }
            return 0;
          }

        ''',
        functionName: 'cmpLessEqual',
        executions: {
          [5]: 1,
          [10]: 1,
          [11]: 0,
        },
        expecteWasm: {
          'test':
              '0061736D0100000001060160017E017E030201000710010C636D704C657373457175616C00000A150113002000420A57044042010F0B42000F0042000B',
        },
      ),
    );

    test(
      'cmpGreaterEqual',
      () => _testWasm(
        language: 'dart',
        code: r'''

          int cmpGreaterEqual(int a) {
            if (a >= 10) {
              return 1;
            }
            return 0;
          }

        ''',
        functionName: 'cmpGreaterEqual',
        executions: {
          [9]: 0,
          [10]: 1,
          [20]: 1,
        },
        expecteWasm: {
          'test':
              '0061736D0100000001060160017E017E030201000713010F636D7047726561746572457175616C00000A150113002000420A59044042010F0B42000F0042000B',
        },
      ),
    );

    test(
      'cmpNotEqual',
      () => _testWasm(
        language: 'dart',
        code: r'''

          int cmpNotEqual(int a) {
            if (a != 5) {
              return 1;
            }
            return 0;
          }

        ''',
        functionName: 'cmpNotEqual',
        executions: {
          [0]: 1,
          [5]: 0,
          [-3]: 1,
        },
        expecteWasm: {
          'test':
              '0061736D0100000001060160017E017E03020100070F010B636D704E6F74457175616C00000A150113002000420552044042010F0B42000F0042000B',
        },
      ),
    );

    test(
      'nestedIf1',
      () => _testWasm(
        language: 'dart',
        code: r'''

          int nestedIf1(int a, int b) {
            if (a > 1) {
              if (b > 1) {
                return 1;
              }
              return 2;
            }
            return 3;
          }

        ''',
        functionName: 'nestedIf1',
        executions: {
          [5, 5]: 1,
          [5, 1]: 2,
          [1, 5]: 3,
        },
        expecteWasm: {
          'test':
              '0061736D0100000001070160027E7E017E03020100070D01096E657374656449663100000A20011E00200042015504402001420155044042010F0B42020F0B42030F0042000B',
        },
      ),
    );

    test(
      'ifElseOnly',
      () => _testWasm(
        language: 'dart',
        code: r'''

          int ifElseOnly(int a) {
            if (a < 1) {
              return -1;
            } else {
              return 1;
            }
          }

        ''',
        functionName: 'ifElseOnly',
        executions: {
          [-5]: -1,
          [5]: 1,
          [2]: 1,
        },
        expecteWasm: {
          'test':
              '0061736D0100000001060160017E017E03020100070E010A6966456C73654F6E6C7900000A1601140020004201530440427F0F0542010F0B0042000B',
        },
      ),
    );

    test(
      'ternaryConditional',
      () => _testWasm(
        language: 'dart',
        code: r'''

          int ternaryConditional(int a) {
            return a > 0 ? 10 : 20;
          }

        ''',
        functionName: 'ternaryConditional',
        executions: {
          [5]: 10,
          [-5]: 20,
          [0]: 20,
        },
      ),
    );

    test(
      'closureCallback',
      () => _testWasm(
        language: 'dart',
        code: r'''

          int f1(int Function(int n) f) {
            var a = f(10);
            var b = f(20);
            return a + b;
          }

          int run() {
            return f1((int n) => n * 10);
          }

        ''',
        functionName: 'run',
        executions: {[]: 300},
      ),
    );

    test(
      'closureUntypedParam',
      () => _testWasm(
        language: 'dart',
        code: r'''

          int f1(int Function(int n) f) {
            var a = f(10);
            var b = f(20);
            return a + b;
          }

          int run() {
            return f1((n) => n * 10);
          }

        ''',
        functionName: 'run',
        executions: {[]: 300},
      ),
    );

    test(
      'closureCapture',
      () => _testWasm(
        language: 'dart',
        code: r'''

          int apply(int Function(int x) f, int v) {
            return f(v);
          }

          int makeAndRun(int n) {
            return apply((int x) => x + n, 5);
          }

          int run() {
            return makeAndRun(100);
          }

        ''',
        functionName: 'run',
        executions: {[]: 105},
      ),
    );

    test(
      'closureReturned',
      () => _testWasm(
        language: 'dart',
        code: r'''

          int Function(int) makeAdder(int n) {
            return (int x) => x + n;
          }

          int run() {
            var a = makeAdder(100);
            var b = makeAdder(1000);
            return a(5) + b(7);
          }

        ''',
        functionName: 'run',
        executions: {[]: 1112},
      ),
    );

    test(
      'multiIntParams',
      () => _testWasm(
        language: 'dart',
        code: r'''

          int multiIntParams(int a, int b, int c, int d) {
            int x = a + b;
            int y = c + d;
            int z = x * y;
            return z;
          }

        ''',
        functionName: 'multiIntParams',
        executions: {
          [1, 2, 3, 4]: 21,
          [2, 3, 4, 5]: 45,
        },
        expecteWasm: {
          'test':
              '0061736D0100000001090160047E7E7E7E017E030201000712010E6D756C7469496E74506172616D7300000A22012003017E017E017E200020017C2104200220037C2105200420057E210620060F0B',
        },
      ),
    );

    test(
      'multiDoubleParams',
      () => _testWasm(
        language: 'dart',
        code: r'''

          double multiDoubleParams(double a, double b, double c) {
            double x = a + b;
            double y = x * c;
            return y;
          }

        ''',
        functionName: 'multiDoubleParams',
        executions: {
          [1.5, 2.5, 2.0]: 8.0,
          [0.0, 0.0, 5.0]: 0.0,
        },
        expecteWasm: {
          'test':
              '0061736D0100000001080160037C7C7C017C03020100071501116D756C7469446F75626C65506172616D7300000A19011702017C017C20002001A0210320032002A2210420040F0B',
        },
      ),
    );

    test(
      'mixedParams',
      () => _testWasm(
        language: 'dart',
        code: r'''

          double mixedParams(int a, double b, int c, double d) {
            var x = a * b;
            var y = c * d;
            return x + y;
          }

        ''',
        functionName: 'mixedParams',
        executions: {
          [2, 1.5, 3, 2.0]: 9.0,
          [10, 0.5, 2, 1.5]: 8.0,
        },
        expecteWasm: {
          'test':
              '0061736D0100000001090160047E7C7E7C017C03020100070F010B6D69786564506172616D7300000A1E011C02017C017C2000B92001A221042002B92003A2210520042005A00F0B',
        },
      ),
    );

    test(
      'intDivLocal',
      () => _testWasm(
        language: 'dart',
        code: r'''

          int intDivLocal(int a, int b) {
            int q = a ~/ b;
            int r = a - (q * b);
            return r;
          }

        ''',
        functionName: 'intDivLocal',
        executions: {
          [17, 5]: 2,
          [20, 4]: 0,
          [10, 3]: 1,
        },
        expecteWasm: {
          'test':
              '0061736D0100000001070160027E7E017E03020100070F010B696E744469764C6F63616C00000A1F011D02017E017E2000B92001B9A3B021022000200220017E7D210320030F0B',
        },
      ),
    );

    test(
      'returnViaLocal',
      () => _testWasm(
        language: 'dart',
        code: r'''

          int returnViaLocal(int a, int b) {
            int sum = a + b;
            int diff = a - b;
            int result = sum * diff;
            return result;
          }

        ''',
        functionName: 'returnViaLocal',
        executions: {
          [10, 3]: 91,
          [5, 5]: 0,
        },
        expecteWasm: {
          'test':
              '0061736D0100000001070160027E7E017E030201000712010E72657475726E5669614C6F63616C00000A22012003017E017E017E200020017C2102200020017D2103200220037E210420040F0B',
        },
      ),
    );

    test(
      'doubleCompare',
      () => _testWasm(
        language: 'dart',
        code: r'''

          int doubleCompare(double a, double b) {
            if (a >= b) {
              return 1;
            }
            return 0;
          }

        ''',
        functionName: 'doubleCompare',
        executions: {
          [1.5, 1.0]: 1,
          [1.0, 1.0]: 1,
          [0.5, 1.0]: 0,
        },
        expecteWasm: {
          'test':
              '0061736D0100000001070160027C7C017E030201000711010D646F75626C65436F6D7061726500000A150113002000200166044042010F0B42000F0042000B',
        },
      ),
    );

    test(
      'arithMix1',
      () => _testWasm(
        language: 'dart',
        code: r'''

          int arithMix1(int a, int b) {
            int x = a * b - a + b;
            return x;
          }

        ''',
        functionName: 'arithMix1',
        executions: {
          [3, 4]: 13,
          [5, 2]: 7,
        },
        expecteWasm: {
          'test':
              '0061736D0100000001070160027E7E017E03020100070D010961726974684D69783100000A16011401017E200020017E20007D20017C210220020F0B',
        },
      ),
    );

    test(
      'whileSum',
      () => _testWasm(
        language: 'dart',
        code: r'''

          int whileSum(int n) {
            int sum = 0;
            int i = 0;
            while (i <= n) {
              sum = sum + i;
              i = i + 1;
            }
            return sum;
          }

        ''',
        functionName: 'whileSum',
        executions: {
          [0]: 0,
          [5]: 15,
          [10]: 55,
        },
      ),
    );

    test(
      'forSum',
      () => _testWasm(
        language: 'dart',
        code: r'''

          int forSum(int n) {
            int sum = 0;
            for (int i = 1; i <= n; i = i + 1) {
              sum = sum + i;
            }
            return sum;
          }

        ''',
        functionName: 'forSum',
        executions: {
          [0]: 0,
          [4]: 10,
          [5]: 15,
        },
      ),
    );

    test(
      'forFactorial',
      () => _testWasm(
        language: 'dart',
        code: r'''

          int forFactorial(int n) {
            int p = 1;
            for (int i = 1; i <= n; i = i + 1) {
              p = p * i;
            }
            return p;
          }

        ''',
        functionName: 'forFactorial',
        executions: {
          [1]: 1,
          [4]: 24,
          [5]: 120,
        },
      ),
    );

    test(
      'nestedLoop',
      () => _testWasm(
        language: 'dart',
        code: r'''

          int nestedLoop(int a, int b) {
            int count = 0;
            for (int i = 1; i <= a; i = i + 1) {
              for (int j = 1; j <= b; j = j + 1) {
                count = count + 1;
              }
            }
            return count;
          }

        ''',
        functionName: 'nestedLoop',
        executions: {
          [3, 4]: 12,
          [2, 5]: 10,
        },
      ),
    );

    test(
      'doubleAccumLoop',
      () => _testWasm(
        language: 'dart',
        code: r'''

          double doubleAccumLoop(int n) {
            double acc = 0.0;
            for (int i = 0; i < n; i = i + 1) {
              acc = acc + 0.5;
            }
            return acc;
          }

        ''',
        functionName: 'doubleAccumLoop',
        executions: {
          [0]: 0.0,
          [4]: 2.0,
          [10]: 5.0,
        },
      ),
    );
    test(
      'call simple (function calling function)',
      () => _testWasm(
        language: 'dart',
        code: r'''

          int sq(int x) {
            return x * x;
          }

          int f(int a) {
            return sq(a) + 1;
          }

        ''',
        functionName: 'f',
        executions: {
          [3]: 10,
          [5]: 26,
        },
      ),
    );

    test(
      'call chain (3-function chain)',
      () => _testWasm(
        language: 'dart',
        code: r'''

          int a(int x) {
            return x + 1;
          }

          int b(int x) {
            return a(x) * 2;
          }

          int c(int x) {
            return b(x) - 3;
          }

        ''',
        functionName: 'c',
        executions: {
          [5]: 9,
          [10]: 19,
        },
      ),
    );

    test(
      'call mixed int/double params',
      () => _testWasm(
        language: 'dart',
        code: r'''

          double half(double v) {
            return v / 2.0;
          }

          double g(int n) {
            return half(n) + 1.0;
          }

        ''',
        functionName: 'g',
        executions: {
          [4]: 3.0,
          [10]: 6.0,
        },
      ),
    );

    test(
      'call recursion (factorial)',
      () => _testWasm(
        language: 'dart',
        code: r'''

          int fact(int n) {
            if (n < 2) {
              return 1;
            }
            return n * fact(n - 1);
          }

        ''',
        functionName: 'fact',
        executions: {
          [0]: 1,
          [1]: 1,
          [5]: 120,
          [6]: 720,
        },
      ),
    );

    test(
      'call recursion (sum-to-n)',
      () => _testWasm(
        language: 'dart',
        code: r'''

          int sumTo(int n) {
            if (n < 1) {
              return 0;
            }
            return n + sumTo(n - 1);
          }

        ''',
        functionName: 'sumTo',
        executions: {
          [0]: 0,
          [1]: 1,
          [5]: 15,
          [10]: 55,
        },
      ),
    );
  });
}

Future<void> _testWasm({
  required String language,
  required String code,
  required String functionName,
  required Map<List, Object?> executions,
  Map<String, dynamic>? expecteWasm,
}) async {
  print('==================================================================');
  print("$language>> $functionName");

  for (var e in executions.entries) {
    var parameters = e.key;
    var expectedResult = e.value;
    print('  -- $parameters -> $expectedResult');
  }

  var vm = ApolloVM();

  var codeUnit = SourceCodeUnit(language, code, id: 'test');

  print(">> Loading code...");

  var loadOK = await vm.loadCodeUnit(codeUnit);

  if (!loadOK) {
    print("Can't load source code in `$language`!");
    return;
  }

  print('------------------------------------------------------------------');

  print(">> Regenerating `$language` code ...\n");

  var regeneratedCode = await vm.generateAllCodeIn(language).writeAllSources();

  print(regeneratedCode);

  print('------------------------------------------------------------------');

  print(">> Compiling `$language` code to Wasm...");

  var storageWasm = vm.generateAllIn<BytesOutput>('wasm');
  var wasmModules = await storageWasm.allEntries();

  expecteWasm ??= {};

  BytesOutput? compiledWasm;
  Uint8List? expectedWasmBytes;

  for (var namespace in wasmModules.entries) {
    for (var module in namespace.value.entries) {
      var moduleName = module.key;
      var wasm = module.value;
      var wasmBytes = wasm.output();

      var expectedBytes = expecteWasm[moduleName];
      if (expectedBytes is String) {
        expectedBytes = hex.decode(expectedBytes);
      }

      print('<<WASM: ${namespace.key}/$moduleName>>');
      print(wasm);

      print('<<WASM: HEX>>');
      print(hex.encode(wasmBytes));

      print('<<WASM: Bytes>>');
      print(wasmBytes);

      // _saveWasmFile(language, functionName, wasmBytes);

      expectedWasmBytes = expectedBytes;

      compiledWasm ??= wasm;
    }
  }

  expect(compiledWasm, isNotNull);

  print('------------------------------------------------------------------');

  {
    print(">> Running code...");

    var dartRunner = vm.createRunner('dart')!;

    // Map the `print` function in the VM:
    dartRunner.externalPrintFunction = (o) => print("» $o");

    for (var e in executions.entries) {
      var parameters = e.key;
      var expectedResult = e.value;

      print('<<<<<<<<<<<<<<<<<<<<<<<<<<<<');
      print('EXECUTE AST> $parameters -> $expectedResult');

      var astValue = await dartRunner.executeFunction(
        '',
        functionName,
        positionalParameters: parameters,
      );

      var result = astValue.getValueNoContext();
      print('Result: $result');

      expect(result, expectedResult);
      print('>>>>>>>>>>>>>>>>>>>>>>>>>>>>');
    }
  }

  print('------------------------------------------------------------------');

  final wasmRuntime = WasmRuntime();

  wasmRuntime.ensureBooted();

  if (wasmRuntime.isSupported) {
    print(">> Running compiled Wasm...");

    var vmWasm = ApolloVM();

    var wasmCodeUnit = BinaryCodeUnit(
      'wasm',
      compiledWasm!.output(),
      id: 'test.wasm',
      namespace: '',
    );

    var loadOK = await vmWasm.loadCodeUnit(wasmCodeUnit);
    expect(loadOK, isTrue);

    var wasmRunner = vmWasm.createRunner('wasm')!;

    // Map the `print` function in the VM:
    wasmRunner.externalPrintFunction = (o) => print("wasm» $o");

    for (var e in executions.entries) {
      var parameters = e.key;
      var expectedResult = e.value;

      print('<<<<<<<<<<<<<<<<<<<<<<<<<<<<');
      print('EXECUTE WASM> $parameters -> $expectedResult');

      ASTValue wasmAstValue;

      try {
        wasmAstValue = await wasmRunner.executeFunction(
          '',
          functionName,
          positionalParameters: parameters,
        );
      } catch (e) {
        print(e);

        var matchOffset = RegExp(
          r'Invalid input WebAssembly code at offset (\d+)',
        ).firstMatch('$e');

        if (matchOffset != null) {
          var offset = int.tryParse(matchOffset.group(1) ?? '');
          if (offset != null) {
            var output = compiledWasm.output();

            var codeBefore = output.sublist(0, offset);
            var codeAfter = output.sublist(offset);

            print('CODE ERROR AT:');
            print(codeBefore);
            print(codeAfter);
          }
        }

        rethrow;
      }

      var wasmResult = wasmAstValue.getValueNoContext();
      print('Wasm Result: $wasmResult');

      expect(wasmResult, expectedResult);
      print('>>>>>>>>>>>>>>>>>>>>>>>>>>>>');
    }
  } else {
    print(
      '** `WasmRuntime` not supported: ${wasmRuntime.platformVersion}\n** [LAST BOOT ERROR]: ${wasmRuntime.lastBootError}',
    );
  }

  var output = compiledWasm?.output();
  print('<< GENERATED WASM: HEX>>\n${hex.encode(output!)}');

  // Only assert exact bytes when an expectation was provided.
  if (expectedWasmBytes != null) {
    print('<< EXPECTED WASM: HEX>>\n${hex.encode(expectedWasmBytes)}');
    expect(output, expectedWasmBytes);
  }
}

/*
void _saveWasmFile(String language, String functionName, List<int> wasmBytes) {
  try {
    var fileName = 'apollovm-$language-$functionName-test.wasm';

    var file = File('/tmp/test-wasm/$fileName');
    file.writeAsBytesSync(wasmBytes);

    print('>> SAVED: $file');
  } catch (_) {}
}
 */
