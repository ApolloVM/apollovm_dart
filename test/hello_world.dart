class Foo {
  void main(List<String> args) {
    var a0 = args[0];

    print('Hello World!');
    print('- args: $args');
    print('- a0: $a0');

    for (var i = 0; i < 1; i += 1) {
      var e = args[i];
      print('$i> $e$e');
    }
  }
}
