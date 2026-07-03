@TestOn('vm')
library;

import 'dart:convert';

import 'package:apollovm/apollovm.dart';
import 'package:apollovm/apollovm_pub.dart';
import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

/// Builds a gzip-compressed tar archive with the given `lib/` files, exactly as
/// a pub package archive is laid out (files at the root, sources under `lib/`).
List<int> _buildArchive(Map<String, String> libFiles) {
  var archive = Archive();
  libFiles.forEach((libPath, source) {
    var bytes = utf8.encode(source);
    archive.addFile(ArchiveFile('lib/$libPath', bytes.length, bytes));
  });
  var tar = TarEncoder().encode(archive);
  return GZipEncoder().encode(tar);
}

/// A [MockClient] emulating a pub host: `/api/packages/<name>` returns the
/// version list; the archive URL returns the built `.tar.gz`.
MockClient _pubHost(
  Map<String, ({List<String> versions, List<int> archive})> packages, {
  void Function(http.BaseRequest request)? onRequest,
}) {
  return MockClient((request) async {
    onRequest?.call(request);
    var url = request.url.toString();

    for (var entry in packages.entries) {
      var name = entry.key;
      if (url.contains('/api/packages/$name')) {
        return http.Response(
          jsonEncode({
            'name': name,
            'versions': [
              for (var v in entry.value.versions)
                {
                  'version': v,
                  'archive_url': 'https://storage.example/$name-$v.tar.gz',
                },
            ],
          }),
          200,
        );
      }
      if (url.contains('$name-')) {
        return http.Response.bytes(entry.value.archive, 200);
      }
    }
    return http.Response('not found', 404);
  });
}

void main() {
  group('PubDevProvider (web-safe: MockClient + in-memory cache)', () {
    test('fetches, extracts, and resolves a package source', () async {
      var client = _pubHost({
        'greeter': (
          versions: ['1.0.0'],
          archive: _buildArchive({
            'greeter.dart':
                "class Greeter { Greeter(); String hi() { return 'hi'; } }",
          }),
        ),
      });

      var provider = PubDevProvider(
        host: 'https://pub.dev',
        client: client,
        cache: MemoryPackageCache(),
      );

      var src = await provider.resolvePackage('greeter', 'greeter.dart');
      expect(src, isNotNull);
      expect(src!.moduleId, 'package:greeter/greeter.dart');
      expect(src.source, contains('class Greeter'));

      // Unknown package / file → null.
      expect(await provider.resolvePackage('nope', 'x.dart'), isNull);
      expect(await provider.resolvePackage('greeter', 'missing.dart'), isNull);
    });

    test('honors pubspec version constraints', () async {
      var client = _pubHost({
        'foo': (
          versions: ['1.0.0', '1.5.0', '2.0.0'],
          archive: _buildArchive({'foo.dart': 'class Foo { Foo(); }'}),
        ),
      });

      // Constraint `^1.0.0` must pick 1.5.0 (highest satisfying), not 2.0.0.
      var requestedUrls = <String>[];
      var provider = PubDevProvider(
        host: 'https://pub.dev',
        client: _pubHost({
          'foo': (
            versions: ['1.0.0', '1.5.0', '2.0.0'],
            archive: _buildArchive({'foo.dart': 'class Foo { Foo(); }'}),
          ),
        }, onRequest: (r) => requestedUrls.add(r.url.toString())),
        pubspecYaml: 'dependencies:\n  foo: ^1.0.0\n',
      );

      var src = await provider.resolvePackage('foo', 'foo.dart');
      expect(src, isNotNull);
      expect(
        requestedUrls.any((u) => u.contains('foo-1.5.0.tar.gz')),
        isTrue,
        reason: 'should download 1.5.0 for constraint ^1.0.0',
      );
      // Never downloads 2.0.0.
      expect(requestedUrls.any((u) => u.contains('foo-2.0.0')), isFalse);
      client.close();
    });

    test('rewriteUrl routes every request through a CORS proxy', () async {
      var seen = <String>[];
      var provider = PubDevProvider(
        host: 'https://pub.dev',
        client: _pubHost({
          'p': (
            versions: ['1.0.0'],
            archive: _buildArchive({'p.dart': 'class P { P(); }'}),
          ),
        }, onRequest: (r) => seen.add(r.url.toString())),
        rewriteUrl: (u) => Uri.parse('https://proxy.example/${u.toString()}'),
      );

      await provider.resolvePackage('p', 'p.dart');
      expect(seen, isNotEmpty);
      expect(
        seen.every((u) => u.startsWith('https://proxy.example/')),
        isTrue,
        reason: 'proxy prefix applied to API and archive requests',
      );
    });

    test('end-to-end: cross-module execution via the pub importer', () async {
      var vm = ApolloVM();
      await vm.loadCodeUnit(
        SourceCodeUnit('dart', r'''
import 'package:greeter/greeter.dart';

String run() {
  var g = Greeter('bob');
  return g.hi();
}
''', id: 'main.dart'),
      );

      var provider = PubDevProvider(
        host: 'https://pub.dev',
        client: _pubHost({
          'greeter': (
            versions: ['1.0.0'],
            archive: _buildArchive({
              'greeter.dart': r'''
class Greeter {
  String name;
  Greeter(this.name);
  String hi() { return 'Hi ' + name; }
}
''',
            }),
          ),
        }),
        cache: MemoryPackageCache(),
      );

      var loader = DartPackageLoader(vm, provider);
      vm.moduleLoader = loader;

      expect(await loader.provision(), isEmpty);
      expect(vm.resolve(language: 'dart'), isEmpty);

      var runner = vm.createRunner('dart')!;
      var r = await runner.executeFunction('', 'run', positionalParameters: []);
      expect(r.getValueNoContext(), equals('Hi bob'));
    });

    test('MemoryPackageCache avoids re-downloading', () async {
      var downloads = <String>[];
      var provider = PubDevProvider(
        host: 'https://pub.dev',
        client: _pubHost(
          {
            'c': (
              versions: ['1.0.0'],
              archive: _buildArchive({
                'a.dart': 'class A { A(); }',
                'b.dart': 'class B { B(); }',
              }),
            ),
          },
          onRequest: (r) {
            if (r.url.toString().contains('.tar.gz')) {
              downloads.add(r.url.toString());
            }
          },
        ),
        cache: MemoryPackageCache(),
      );

      await provider.resolvePackage('c', 'a.dart');
      await provider.resolvePackage('c', 'b.dart'); // same package, cached
      expect(downloads, hasLength(1));
    });
  });
}
