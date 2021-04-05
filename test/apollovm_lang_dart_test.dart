import 'package:apollovm/apollovm.dart';
import 'package:test/test.dart';

void main() {
  group('Dart', () {
    test('Basic main(List<Object>)', () async {
      var vm = ApolloVM();

      var codeUnit = CodeUnit(
          'dart',
          r'''
            void main(List<Object> args) {
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
          ''',
          'test');

      var loadOK = await vm.loadCodeUnit(codeUnit);

      expect(loadOK, isTrue, reason: 'Error loading Dart code!');

      var dartRunner = vm.createRunner('dart')!;

      var output = [];
      dartRunner.externalPrintFunction = (o) => output.add(o);

      dartRunner.executeFunction('', 'main', [
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

      expect(
          allSourcesDart,
          matches(RegExp(r'\s*'
              r'void\s+main\(List<Object> args\)\s*\{'
              r'\s*var\s+title\s+=\s+args\[0\]\s*;'
              r'\s*var\s+a\s+=\s+args\[1\]\s*;'
              r'\s*var\s+b\s+=\s+args\[2\]\s*;'
              r'\s*var\s+c\s+=\s+args\[3\]\s*;'
              r'\s*var\s+sumAB\s+=\s+a\s*\+\s*b\s*;'
              r'\s*var\s+sumABC\s+=\s+a\s*\+\s*b\s*\+\s*c\s*;'
              r'\s*print\(title\)\s*;'
              r'\s*print\(sumAB\)\s*;'
              r'\s*print\(sumABC\)\s*;'
              r'\s*\}\s*')));
    });

    test('Basic main(List<String>)', () async {
      var vm = ApolloVM();

      var codeUnit = CodeUnit(
          'dart',
          r'''
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
          ''',
          'test');

      var loadOK = await vm.loadCodeUnit(codeUnit);

      expect(loadOK, isTrue, reason: 'Error loading Dart code!');

      var dartRunner = vm.createRunner('dart')!;

      var output = [];
      dartRunner.externalPrintFunction = (o) => output.add(o);

      dartRunner.executeFunction('', 'main', [
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

      expect(
          allSourcesDart,
          matches(RegExp(r'\s*'
              r'void\s+main\(List<String> args\)\s*\{'
              r'\s*var\s+title\s+=\s+args\[0\]\s*;'
              r'\s*var\s+a\s+=\s+args\[1\]\s*;'
              r'\s*var\s+b\s+=\s+args\[2\]\s*;'
              r'\s*var\s+c\s+=\s+args\[3\]\s*;'
              r'\s*var\s+sumAB\s+=\s+a\s*\+\s*b\s*;'
              r'\s*var\s+sumABC\s+=\s+a\s*\+\s*b\s*\+\s*c\s*;'
              r'\s*print\(title\)\s*;'
              r'\s*print\(sumAB\)\s*;'
              r'\s*print\(sumABC\)\s*;'
              r'\s*\}\s*')));
    });

    test('Basic main(List<Object>) with inline String', () async {
      var vm = ApolloVM();

      var codeUnit = CodeUnit(
          'dart',
          r'''
            void main(List<Object> args) {
              var title = args[0];
              var a = args[1];
              var b = args[2];
              var s1 = 'inline';
              var s2 = r'string';
              var c = s1 + ' \t' +"\t " + s2 ;
              var sumAB = a + b ;
              var sumABC = a + b + c;
              print(title);
              print(sumAB);
              print(sumABC);
            }
          ''',
          'test');

      var loadOK = await vm.loadCodeUnit(codeUnit);

      expect(loadOK, isTrue, reason: 'Error loading Dart code!');

      var dartRunner = vm.createRunner('dart')!;

      var output = [];
      dartRunner.externalPrintFunction = (o) => output.add(o);

      dartRunner.executeFunction('', 'main', [
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

      expect(allSourcesDart, equals(r'''<<<< [SOURCES_BEGIN] >>>>
<<<< NAMESPACE="" >>>>
<<<< CODE_UNIT_START="/test" >>>>
  void main(List<Object> args) {
    var title = args[0];
    var a = args[1];
    var b = args[2];
    var s1 = 'inline';
    var s2 = 'string';
    var c = s1 + ' \t' + '\t ' + s2;
    var sumAB = a + b;
    var sumABC = a + b + c;
    print(title);
    print(sumAB);
    print(sumABC);
  }
<<<< CODE_UNIT_END="/test" >>>>
<<<< [SOURCES_END] >>>>
'''));
    });

    test('Basic main(List<Object>) with multiline String', () async {
      var vm = ApolloVM();

      var codeUnit = CodeUnit(
          'dart',
          '''
            void main(List<Object> args) {
              var title = args[0];
              var a = args[1];
              var b = args[2];
              var l = \'''line1
line2
line3
\''';
              var s = a + '\\\\::' + l + b;
              print(title);
              print(s);
            }
          ''',
          'test');

      print(codeUnit.source);

      var loadOK = await vm.loadCodeUnit(codeUnit);

      expect(loadOK, isTrue, reason: 'Error loading Dart code!');

      var dartRunner = vm.createRunner('dart')!;

      var output = [];
      dartRunner.externalPrintFunction = (o) => output.add(o);

      dartRunner.executeFunction('', 'main', [
        ['Multiline:', 10, 20]
      ]);

      print('---------------------------------------');
      print('OUTPUT:');
      output.forEach((o) => print('>> $o'));

      expect(output, equals(['Multiline:', '10\\::line1\nline2\nline3\n20']));

      print('---------------------------------------');
      // Regenerate code:
      var codeStorageDart = vm.generateAllCodeIn('dart');
      var allSourcesDart = codeStorageDart.writeAllSources().toString();
      print(allSourcesDart);

      expect(allSourcesDart, equals(r'''<<<< [SOURCES_BEGIN] >>>>
<<<< NAMESPACE="" >>>>
<<<< CODE_UNIT_START="/test" >>>>
  void main(List<Object> args) {
    var title = args[0];
    var a = args[1];
    var b = args[2];
    var l = 'line1\nline2\nline3\n';
    var s = a + r'\::' + l + b;
    print(title);
    print(s);
  }
<<<< CODE_UNIT_END="/test" >>>>
<<<< [SOURCES_END] >>>>
'''));
    });

    test('Basic main(List<String>) with raw strings', () async {
      var vm = ApolloVM();

      var codeUnit = CodeUnit(
          'dart',
          r'''
            void main(List<String> args) {
              var s1 = 'single \'quote\'';
              var s2 = "double \"quote\"";
              var r1 = r"single \'quote\'";
              var r2 = r'double \"quote\"'; 
              print(s1);
              print(s2);
              print(r1);
              print(r2);
            }
          ''',
          'test');

      var loadOK = await vm.loadCodeUnit(codeUnit);

      expect(loadOK, isTrue, reason: 'Error loading Dart code!');

      var dartRunner = vm.createRunner('dart')!;

      var output = [];
      dartRunner.externalPrintFunction = (o) => output.add(o);

      dartRunner.executeFunction('', 'main', []);

      expect(
          output,
          equals([
            r"single 'quote'",
            r'double "quote"',
            r"single \'quote\'",
            r'double \"quote\"'
          ]));

      print('---------------------------------------');
      print('OUTPUT:');
      output.forEach((o) => print('>> $o'));

      print('---------------------------------------');
      // Regenerate code:
      var codeStorageDart = vm.generateAllCodeIn('dart');
      var allSourcesDart = codeStorageDart.writeAllSources().toString();
      print(allSourcesDart);

      expect(allSourcesDart, equals(r'''<<<< [SOURCES_BEGIN] >>>>
<<<< NAMESPACE="" >>>>
<<<< CODE_UNIT_START="/test" >>>>
  void main(List<String> args) {
    var s1 = "single 'quote'";
    var s2 = 'double "quote"';
    var r1 = r"single \'quote\'";
    var r2 = r'double \"quote\"';
    print(s1);
    print(s2);
    print(r1);
    print(r2);
  }
<<<< CODE_UNIT_END="/test" >>>>
<<<< [SOURCES_END] >>>>
'''));
    });

    test('Basic main(List<String>) with raw multiline strings', () async {
      var vm = ApolloVM();

      var codeUnit = CodeUnit(
          'dart',
          r"""
            void main(List<String> args) {
              var m1 = '''single \'quote\'''';
              var rm1 = r'''double \"quote\"''';"""
              r'''
              var m2 = """double \"quote\"""";
              var rm2 = r"""single \'quote\'""";
              print(m1);
              print(m2);
              print(rm1);
              print(rm2);
            }
          ''',
          'test');

      var loadOK = await vm.loadCodeUnit(codeUnit);

      expect(loadOK, isTrue, reason: 'Error loading Dart code!');

      var dartRunner = vm.createRunner('dart')!;

      var output = [];
      dartRunner.externalPrintFunction = (o) => output.add(o);

      dartRunner.executeFunction('', 'main', []);

      expect(
          output,
          equals([
            "single \'quote\'",
            'double \"quote\"',
            r'double \"quote\"',
            r"single \'quote\'",
          ]));

      print('---------------------------------------');
      print('OUTPUT:');
      output.forEach((o) => print('>> $o'));

      print('---------------------------------------');
      // Regenerate code:
      var codeStorageDart = vm.generateAllCodeIn('dart');
      var allSourcesDart = codeStorageDart.writeAllSources().toString();
      print(allSourcesDart);

      expect(allSourcesDart, equals(r'''<<<< [SOURCES_BEGIN] >>>>
<<<< NAMESPACE="" >>>>
<<<< CODE_UNIT_START="/test" >>>>
  void main(List<String> args) {
    var m1 = "single 'quote'";
    var rm1 = r'double \"quote\"';
    var m2 = 'double "quote"';
    var rm2 = r"single \'quote\'";
    print(m1);
    print(m2);
    print(rm1);
    print(rm2);
  }
<<<< CODE_UNIT_END="/test" >>>>
<<<< [SOURCES_END] >>>>
'''));
    });
  });
}
