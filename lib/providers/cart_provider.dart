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

enum OrderType { dineIn, takeaway, delivery }

class CartProvider extends ChangeNotifier {
  final List<CartItem> _items = [];
  String? _tableId;
  String? _tableName;
  String? _customerName;
  String? _waiterName;
  OrderType _orderType = OrderType.dineIn;

  List<CartItem> get items => _items;
  double get totalAmount => _items.fold(0, (sum, item) => sum + item.totalPrice);
  int get totalItems => _items.fold(0, (sum, item) => sum + item.quantity);
  String? get tableId => _tableId;
  String? get tableName => _tableName;
  String? get customerName => _customerName;
  String? get waiterName => _waiterName;
  OrderType get orderType => _orderType;

  void setOrderType(OrderType type) {
    if (_orderType != type) {
       _orderType = type;
       if (type != OrderType.dineIn) _tableId = null;
       notifyListeners();
    }
  }

  void setCustomerName(String? name) {
    _customerName = (name == null || name.isEmpty) ? "Walk-in" : name;
    notifyListeners();
  }

  void setWaiterInfo(String name) {
    _waiterName = name;
    notifyListeners();
  }

  void setTable(String tableId, String tableName) {
    if (_tableId != tableId) {
      _tableId = tableId;
      _tableName = tableName;
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
    _customerName = null;
    _waiterName = null;
    _orderType = OrderType.dineIn;
    notifyListeners();
  }
}
