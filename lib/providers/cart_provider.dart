import 'package:flutter/material.dart';
import '../../models/menu_item.dart';

class CartItem {
  final MenuItem item;
  int quantity;
  String specialInstructions;

  CartItem({
    required this.item,
    this.quantity = 1,
    this.specialInstructions = '',
  });

  double get totalPrice => item.price * quantity;
}

class CartProvider extends ChangeNotifier {
  final List<CartItem> _items = [];
  String? _tableId; // The table this cart belongs to

  List<CartItem> get items => _items;
  double get totalAmount => _items.fold(0, (sum, item) => sum + item.totalPrice);
  int get totalItems => _items.fold(0, (sum, item) => sum + item.quantity);
  String? get tableId => _tableId;

  void setTable(String tableId) {
    if (_tableId != tableId) {
      _tableId = tableId;
      _items.clear();
      notifyListeners();
    }
  }

  void addItem(MenuItem item, {int quantity = 1, String instructions = ''}) {
    if (!item.isAvailable) return;
    
    final existingIndex = _items.indexWhere((i) => i.item.id == item.id && i.specialInstructions == instructions);
    if (existingIndex >= 0) {
      _items[existingIndex].quantity += quantity;
    } else {
      _items.add(CartItem(item: item, quantity: quantity, specialInstructions: instructions));
    }
    notifyListeners();
  }

  void removeItem(CartItem cartItem) {
    _items.remove(cartItem);
    notifyListeners();
  }

  void updateQuantity(CartItem cartItem, int newQuantity) {
    if (newQuantity <= 0) {
      removeItem(cartItem);
    } else {
      cartItem.quantity = newQuantity;
      notifyListeners();
    }
  }

  void clearCart() {
    _items.clear();
    _tableId = null;
    notifyListeners();
  }
}
