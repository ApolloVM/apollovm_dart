// ignore_for_file: prefer_interpolation_to_compose_strings

class User {
  String name;

  User(this.name);

  String greet() {
    return 'Hi ' + name;
  }
}
