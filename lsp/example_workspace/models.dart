/// A user of the system.
///
/// Holds an identifier and a display name.
class User {
  int id;
  String name;

  /// Returns a greeting addressed to this user.
  String greeting() {
    return 'Hello, $name';
  }
}

/// Finds a user by identifier.
///
/// Returns a [User] built from the given [id].
User findUser(int id) {
  var u = User();
  return u;
}
