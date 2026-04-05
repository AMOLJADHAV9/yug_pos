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
  String? _customerContact;
  String? _deliveryAddress;
  String? _waiterName;
  OrderType _orderType = OrderType.dineIn;
  String? _activeOrderId;
  int? _activeTokenNo;

  List<CartItem> get items => _items;
  double get totalAmount => _items.fold(0, (sum, item) => sum + item.totalPrice);
  int get totalItems => _items.fold(0, (sum, item) => sum + item.quantity);
  String? get tableId => _tableId;
  String? get tableName => _tableName;
  String? get customerName => _customerName;
  String? get customerContact => _customerContact;
  String? get deliveryAddress => _deliveryAddress;
  String? get waiterName => _waiterName;
  OrderType get orderType => _orderType;
  String? get activeOrderId => _activeOrderId;
  int? get activeTokenNo => _activeTokenNo;

  void setOrderType(OrderType type) {
    if (_orderType != type) {
       _orderType = type;
       if (type != OrderType.dineIn) _tableId = null;
       notifyListeners();
    }
  }

  void setCustomerName(String? name) {
    _customerName = name;
    notifyListeners();
  }

  void setCustomerContact(String? contact) {
    _customerContact = contact;
    notifyListeners();
  }

  void setDeliveryAddress(String? address) {
    _deliveryAddress = address;
    notifyListeners();
  }

  void setWaiterInfo(String name) {
    _waiterName = name;
    notifyListeners();
  }

  void setTable(String tableId, String tableName) {
    _tableId = tableId;
    _tableName = tableName;
    _items.clear();
    _activeOrderId = null; // New table session
    _activeTokenNo = null;
    _customerName = "Walk-in";
    notifyListeners();
  }

  void setActiveOrder(String id, {int? token, OrderType? type, String? tableName, String? tableId}) {
    _activeOrderId = id;
    _activeTokenNo = token;
    if (type != null) _orderType = type;
    if (tableName != null) {
      _tableName = tableName;
    }
    if (tableId != null) {
      _tableId = tableId;
    }
    _items.clear(); // Clear cart for new items to add
    notifyListeners();
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
    _tableName = null;
    _customerName = null;
    _waiterName = null;
    _customerName = "Walk-in";
    _customerContact = null;
    _deliveryAddress = null;
    _activeOrderId = null;
    _activeTokenNo = null;
    notifyListeners();
  }
}
