import 'dart:async';

extension FutureOrExtension<T> on FutureOr<T> {
  bool get isResolved => this is! Future;

  FutureOr<T> resolve() {
    if (this is Future) {
      var future = this as Future<T>;
      return future.then((r) => r);
    } else {
      return this as T;
    }
  }

  FutureOr<R> resolveMapped<R>(FutureOr<R> Function(T r) mapper) {
    if (this is Future) {
      var future = this as Future<T>;
      return future.then((r) => mapper(r));
    } else {
      return mapper(this as T);
    }
  }

  FutureOr<R> resolveWith<R>(FutureOr<R> Function() mapper) {
    if (this is Future) {
      var future = this as Future<T>;
      return future.then((r) => mapper());
    } else {
      return mapper();
    }
  }

  FutureOr<void> onResolve<R>(void Function(T r) callback) {
    if (this is Future) {
      var future = this as Future<T>;
      return future.then((r) => callback(r));
    } else {
      callback(this as T);
    }
  }

  Future<T> get asFuture =>
      this is Future ? this as Future<T> : Future<T>.value(this);
}

extension ListFutureOrExtension<T> on List<FutureOr<T>> {
  bool get isAllFuture {
    for (var e in this) {
      if (e is! Future) return false;
    }
    return true;
  }

  bool get isAllResolved {
    for (var e in this) {
      if (e is Future) return false;
    }
    return true;
  }

  List<Future<T>> toFutures() =>
      map((e) => e is Future ? e as Future<T> : Future<T>.value(e)).toList();

  FutureOr<List<T>> resolveAll() {
    if (isEmpty) return <T>[];

    if (isAllResolved) {
      return cast<T>().toList();
    } else {
      return Future.wait(toFutures());
    }
  }

  FutureOr<R> resolveAllMapped<R>(FutureOr<R> Function(List<T> r) mapper) {
    if (isEmpty) return mapper(<T>[]);

    if (isAllResolved) {
      var l = cast<T>().toList();
      return mapper(l);
    } else {
      return Future.wait(toFutures()).resolveMapped(mapper);
    }
  }
}
