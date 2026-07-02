/// The status of an order.
enum OrderStatus { pending, shipped, delivered }

/// A customer order.
class Order {
  int number;
  double total;

  /// Whether this order has been paid in full.
  bool isPaid() {
    return total > 0;
  }
}

/// Computes the tax owed on [amount].
double taxFor(double amount) {
  return amount;
}
