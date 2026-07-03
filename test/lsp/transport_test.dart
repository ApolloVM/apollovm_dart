import 'dart:async';
import 'dart:convert';

import 'package:apollovm/apollovm_lsp.dart';
import 'package:test/test.dart';

void main() {
  group('LspEndpoint dispatch (MessageLspEndpoint)', () {
    late List<Map<String, Object?>> out;
    late MessageLspEndpoint ep;
    setUp(() {
      out = [];
      ep = MessageLspEndpoint(out.add);
    });

    Future<Map<String, Object?>> waitId(int id) async {
      for (var i = 0; i < 1000; i++) {
        final m = out.firstWhere((m) => m['id'] == id, orElse: () => {});
        if (m.isNotEmpty) return m;
        await Future<void>.delayed(Duration.zero);
      }
      throw StateError('no reply');
    }

    test('request with no handler → methodNotFound', () async {
      ep.receive({'jsonrpc': '2.0', 'id': 1, 'method': 'x'});
      final r = await waitId(1);
      expect((r['error'] as Map)['code'], ResponseError.methodNotFound);
    });

    test('handler result is returned', () async {
      ep.onRequest = (method, params) => {'ok': method};
      ep.receive({'jsonrpc': '2.0', 'id': 2, 'method': 'ping'});
      final r = await waitId(2);
      expect((r['result'] as Map)['ok'], 'ping');
    });

    test('handler throwing ResponseError propagates the code', () async {
      ep.onRequest = (method, params) =>
          throw const ResponseError(ResponseError.invalidParams, 'bad');
      ep.receive({'jsonrpc': '2.0', 'id': 3, 'method': 'x'});
      final r = await waitId(3);
      expect((r['error'] as Map)['code'], ResponseError.invalidParams);
      expect((r['error'] as Map)['message'], 'bad');
    });

    test('handler throwing a generic error → internalError', () async {
      ep.onRequest = (method, params) => throw StateError('boom');
      ep.receive({'jsonrpc': '2.0', 'id': 4, 'method': 'x'});
      final r = await waitId(4);
      expect((r['error'] as Map)['code'], ResponseError.internalError);
    });

    test('notifications reach onNotification and produce no reply', () async {
      String? seen;
      ep.onNotification = (method, params) => seen = method;
      ep.receive({'jsonrpc': '2.0', 'method': 'note', 'params': {}});
      await Future<void>.delayed(Duration.zero);
      expect(seen, 'note');
      expect(out, isEmpty);
    });

    test('a message without a string method is ignored', () async {
      ep.receive({'jsonrpc': '2.0', 'id': 9});
      await Future<void>.delayed(Duration.zero);
      expect(out, isEmpty);
    });

    test('sendNotification writes a framed message object', () {
      ep.sendNotification('m', {'a': 1});
      expect(out.single['method'], 'm');
      expect((out.single['params'] as Map)['a'], 1);
    });

    test('close completes done', () async {
      var done = false;
      unawaited(ep.done.then((_) => done = true));
      ep.close();
      await ep.done;
      expect(done, isTrue);
    });
  });

  group('StreamLspEndpoint framing', () {
    test(
      'parses a Content-Length framed request from the byte stream',
      () async {
        final input = StreamController<List<int>>();
        final output = <int>[];
        final sink = _CollectingSink(output);
        final ep = StreamLspEndpoint(input.stream, sink);
        ep.onRequest = (method, params) => {'echo': method};
        ep.listen();

        _writeFrame(input, {'jsonrpc': '2.0', 'id': 1, 'method': 'hi'});
        await _until(() => _frames(output).any((m) => m['id'] == 1));
        final reply = _frames(output).firstWhere((m) => m['id'] == 1);
        expect((reply['result'] as Map)['echo'], 'hi');
        await input.close();
      },
    );

    test(
      'ignores a frame with no Content-Length, then processes a good one',
      () async {
        final input = StreamController<List<int>>();
        final output = <int>[];
        final ep = StreamLspEndpoint(input.stream, _CollectingSink(output));
        ep.onRequest = (method, params) => 'ok';
        ep.listen();

        // Bad header block (no Content-Length) followed by a valid frame.
        input.add(utf8.encode('Bad-Header: 1\r\n\r\n'));
        _writeFrame(input, {'jsonrpc': '2.0', 'id': 7, 'method': 'good'});
        await _until(() => _frames(output).any((m) => m['id'] == 7));
        expect(_frames(output).firstWhere((m) => m['id'] == 7)['result'], 'ok');
        await input.close();
      },
    );

    test('done completes when the input stream closes', () async {
      final input = StreamController<List<int>>();
      final ep = StreamLspEndpoint(input.stream, _CollectingSink([]));
      ep.listen();
      final doneFuture = ep.done;
      await input.close();
      await doneFuture; // must complete
    });
  });
}

void _writeFrame(StreamController<List<int>> input, Map<String, Object?> msg) {
  final body = utf8.encode(json.encode(msg));
  input.add(utf8.encode('Content-Length: ${body.length}\r\n\r\n'));
  input.add(body);
}

List<Map<String, Object?>> _frames(List<int> bytes) {
  final out = <Map<String, Object?>>[];
  var cursor = 0;
  while (true) {
    var headerEnd = -1;
    for (var i = cursor; i + 3 < bytes.length; i++) {
      if (bytes[i] == 13 &&
          bytes[i + 1] == 10 &&
          bytes[i + 2] == 13 &&
          bytes[i + 3] == 10) {
        headerEnd = i;
        break;
      }
    }
    if (headerEnd < 0) break;
    final header = utf8.decode(bytes.sublist(cursor, headerEnd));
    final m = RegExp(
      r'Content-Length:\s*(\d+)',
      caseSensitive: false,
    ).firstMatch(header);
    if (m == null) break;
    final len = int.parse(m.group(1)!);
    final bodyStart = headerEnd + 4;
    if (bytes.length < bodyStart + len) break;
    out.add(
      json.decode(utf8.decode(bytes.sublist(bodyStart, bodyStart + len)))
          as Map<String, Object?>,
    );
    cursor = bodyStart + len;
  }
  return out;
}

Future<void> _until(bool Function() cond) async {
  for (var i = 0; i < 2000; i++) {
    if (cond()) return;
    await Future<void>.delayed(Duration.zero);
  }
  throw StateError('condition not met');
}

class _CollectingSink implements StreamSink<List<int>> {
  final List<int> bytes;
  final _done = Completer<void>();
  _CollectingSink(this.bytes);

  @override
  void add(List<int> data) => bytes.addAll(data);
  @override
  void addError(Object error, [StackTrace? stackTrace]) {}
  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final c in stream) {
      bytes.addAll(c);
    }
  }

  @override
  Future<void> close() {
    if (!_done.isCompleted) _done.complete();
    return _done.future;
  }

  @override
  Future<void> get done => _done.future;
}
