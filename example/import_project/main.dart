import 'user.dart' show User;
import 'helpers.dart' as h;

void run() {
  var u = User('bob');
  var greeting = u.greet();
  print(greeting);
  print(h.shout(greeting));
}
